#!/usr/bin/env ruby

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "acceptance-reuse"
require_relative "release-policy"

class AcceptanceReuseTest < Minitest::Test
  def load_contract
    @policy = ReleasePolicy.load(File.expand_path("../release-policy.json", __dir__))
    @repository = @policy.fetch("verifierRepository")
    @source_repository = @policy.fetch("sourceRepository")
    @validate = ->(value) { ReleasePolicy.validate_candidate!(value, @policy) }
    @contract_error = ReleasePolicy::Error
    @declared_policy = File.expand_path("../acceptance-reuse-policy.json", __dir__)
  end

  def setup
    load_contract
    @temporary = Dir.mktmpdir("acceptance-reuse-test-")
    @root = Pathname.new(@temporary)
    git("init", "-q")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.invalid")
    git("config", "commit.gpgsign", "false")
    git("remote", "add", "origin", @repository)
    @root.join("host").mkpath
    @root.join("host/view.txt").write("consumer\n")
    @before = commit
    @root.join("unrelated.txt").write("unrelated documentation\n")
    @after = commit
    @source = candidate("a" * 40)
    @current = candidate("b" * 40, changed: "native-harmonyos-har")
    @target = "native-ios-device"
    @scopes = @policy.fetch("acceptance").fetch("manualTargets").to_h do |target|
      [target, {"artifactRoles" => ["native-ios-xcframework"], "inputPaths" => ["host"]}]
    end
    @verifier = {"repository" => @repository, "commit" => @after, "dirty" => false}
    @run = {
      "schemaVersion" => 1, "kind" => "plugin-candidate-manual-run", "status" => "passed",
    }.merge(AcceptanceReuse.identity(@source, AcceptanceReuse.checksum(@source), @target)).merge(
      "environment" => {"deviceModel" => "Fixture device", "operatingSystem" => "Fixture OS", "runtime" => "Release consumer"},
      "scenarios" => @policy.dig("acceptance", "manualScenarios"),
      "notes" => "Fixture only",
      "recordedAt" => (Time.now.utc - 60).iso8601(6),
      "verifier" => {"repository" => @repository, "commit" => @before, "dirty" => false}
    )
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary
  end

  def git(*arguments)
    GitInputDigest.git(@root, *arguments).strip
  end

  def commit
    git("add", ".")
    git("commit", "-qm", "fixture")
    git("rev-parse", "HEAD")
  end

  def candidate(commit, changed: nil)
    qualifications = @policy.fetch("qualifications").to_h { |key| [key, true] }
    roles = @policy.dig("artifactRoles", "required") + @policy.dig("artifactRoles", "conditional").values.flatten
    entries = roles.sort.map do |role|
      {"role" => role, "file" => "artifacts/#{role}", "bytes" => 1,
       "sha256" => Digest::SHA256.hexdigest(role == changed ? role + "changed" : role)}
    end
    payload = entries.map { |entry| %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n" }.join
    digest = Digest::SHA256.hexdigest(payload)
    {
      "schemaVersion" => @policy.fetch("candidateSchemaVersion"), "kind" => "plugin-release-candidate",
      "state" => "candidate", "acceptanceEligible" => true, "plugin" => "levixel", "version" => "1.0.0",
      "candidateId" => "levixel-1.0.0-#{commit[0, 12]}-#{digest[0, 12]}", "artifactSetSha256" => digest,
      "source" => {"repository" => @source_repository, "commit" => commit, "dirty" => false},
      "acceptance" => @policy.fetch("acceptance"), "qualifications" => qualifications, "artifacts" => entries
    }
  end

  def build
    AcceptanceReuse.build(candidate: @current, source_candidate: @source, source_run: @run, target: @target,
                          verifier: @verifier, scopes: @scopes, validate_candidate: @validate, verifier_root: @root)
  end

  def validate(record, root: @root)
    AcceptanceReuse.validate!(record, candidate: @current, candidate_digest: AcceptanceReuse.checksum(@current),
                              target: @target, verifier: @verifier, scopes: @scopes,
                              validate_candidate: @validate, verifier_root: root)
  end

  def test_unrelated_changes_preserve_original_evidence_and_environment
    record = build
    assert_equal "plugin-candidate-manual-reuse", record.fetch("kind")
    assert_equal @run, record.dig("source", "evidence")
    assert_equal @source, record.dig("source", "candidate")
    assert_equal @before, record.dig("source", "evidence", "verifier", "commit")
    assert_equal @after, record.dig("verifier", "commit")
    assert_equal record, validate(record)
  end

  def test_every_target_uses_its_declared_scope
    @policy.dig("acceptance", "manualTargets").each do |target|
      @target = target
      @run.merge!(AcceptanceReuse.identity(@source, AcceptanceReuse.checksum(@source), target))
      assert_equal target, build.fetch("target")
    end
  end

  def test_repository_reuse_policy_covers_the_release_contract
    scopes = AcceptanceReuse.load_policy(
      @declared_policy, plugin: "levixel", acceptance: @policy.fetch("acceptance"),
      artifact_roles: @current.fetch("artifacts").map { |entry| entry.fetch("role") }
    )
    assert_equal @policy.dig("acceptance", "manualTargets").sort, scopes.keys.sort
  end

  def test_consumed_artifact_change_is_rejected
    @current = candidate("b" * 40, changed: "native-ios-xcframework")
    assert_match(/Consumed artifact changed/, assert_raises(AcceptanceReuse::Error) { build }.message)
  end

  def test_failed_incomplete_dirty_or_misidentified_original_is_rejected
    mutations = [
      ->(run) { run["status"] = "failed" },
      ->(run) { run["scenarios"] = [] },
      ->(run) { run["environment"]["runtime"] = "" },
      ->(run) { run["verifier"]["dirty"] = true },
      ->(run) { run["verifier"]["repository"] = "https://example.invalid/wrong.git" },
      ->(run) { run["candidateId"] = "wrong" },
      ->(run) { run["target"] = "wrong" },
      ->(run) { run["unexpected"] = true },
      ->(run) { run["kind"] = "plugin-candidate-manual-reuse" },
      ->(run) { run["recordedAt"] = (Time.now.utc + 3600).iso8601(6) },
    ]
    original = AcceptanceReuse.json(@run)
    mutations.each do |mutation|
      @run = JSON.parse(original)
      mutation.call(@run)
      assert_raises(AcceptanceReuse::Error) { build }
    end
  end

  def test_changed_host_and_changed_file_mode_are_rejected
    @root.join("host/view.txt").write("different consumer")
    @verifier["commit"] = commit
    assert_match(/Verifier inputs changed/, assert_raises(AcceptanceReuse::Error) { build }.message)
    @root.join("host/view.txt").write("consumer\n")
    File.chmod(0o755, @root.join("host/view.txt"))
    @verifier["commit"] = commit
    assert_raises(AcceptanceReuse::Error) { build }
  end

  def test_new_and_deleted_inputs_are_not_ignored
    @root.join("host/new.txt").write("new dependency")
    @verifier["commit"] = commit
    assert_raises(AcceptanceReuse::Error) { build }
    @root.join("host/new.txt").delete
    @root.join("host/view.txt").delete
    @verifier["commit"] = commit
    assert_raises(GitInputDigest::Error) { build }
  end

  def test_missing_history_and_nonancestor_are_rejected
    @run["verifier"]["commit"] = "f" * 40
    assert_raises(AcceptanceReuse::Error) { build }
    @run["verifier"]["commit"] = @after
    @verifier["commit"] = @before
    assert_raises(AcceptanceReuse::Error) { build }
  end

  def test_source_and_proof_tampering_are_rejected
    record = build
    [
      ->(value) { value["inputDigest"] = "f" * 64 },
      ->(value) { value["source"]["candidateManifestSha256"] = "f" * 64 },
      ->(value) { value["source"]["evidenceSha256"] = "f" * 64 },
      ->(value) { value["source"]["evidence"]["notes"] = "edited" },
      ->(value) { value["source"]["candidate"]["source"]["dirty"] = true },
      ->(value) { value["candidateManifestSha256"] = "f" * 64 },
      ->(value) { value["recordedAt"] = (Time.now.utc + 3600).iso8601(6) },
      ->(value) { value["status"] = "pending" },
      ->(value) { value["unknown"] = true },
    ].each do |mutation|
      changed = JSON.parse(AcceptanceReuse.json(record))
      mutation.call(changed)
      assert_raises(AcceptanceReuse::Error, @contract_error) { validate(changed) }
    end
  end

  def test_verifier_checkout_is_required_and_origin_is_checked
    record = build
    assert_raises(AcceptanceReuse::Error) { validate(record, root: nil) }
    git("remote", "set-url", "origin", "https://example.invalid/wrong.git")
    assert_raises(AcceptanceReuse::Error) { validate(record) }
  end

  def test_unknown_target_and_missing_scope_fail
    @scopes.delete(@target)
    assert_raises(KeyError) { build }
  end

  def test_symlinks_and_unsafe_scopes_are_rejected
    File.symlink("../unrelated.txt", @root.join("host/link"))
    @verifier["commit"] = commit
    assert_raises(GitInputDigest::Error) { build }
    @scopes[@target]["inputPaths"] = ["../escape"]
    assert_raises(GitInputDigest::Error) { build }
  end

  def test_policy_rejects_missing_targets_unknown_roles_and_empty_inputs
    path = @root.join("policy.json")
    value = reuse_policy
    arguments = {plugin: "levixel", acceptance: @policy.fetch("acceptance"),
                 artifact_roles: @current.fetch("artifacts").map { |entry| entry.fetch("role") }}
    path.write(AcceptanceReuse.json(value))
    assert_equal @scopes, AcceptanceReuse.load_policy(path, **arguments)
    [
      ->(changed) { changed["targets"].delete(@target) },
      ->(changed) { changed["targets"][@target]["artifactRoles"] = ["unknown"] },
      ->(changed) { changed["targets"][@target]["inputSets"] = [] },
      ->(changed) { changed["targets"][@target]["inputSets"] = ["unknown"] },
      ->(changed) { changed["inputSets"][@target] = ["../escape"] },
      ->(changed) { changed["inputSets"]["unused"] = ["host"] },
    ].each do |mutation|
      changed = JSON.parse(AcceptanceReuse.json(value))
      mutation.call(changed)
      path.write(AcceptanceReuse.json(changed))
      assert_raises(AcceptanceReuse::Error) { AcceptanceReuse.load_policy(path, **arguments) }
    end
  end


  def reuse_policy
    {
      "schemaVersion" => 1, "kind" => "manual-acceptance-reuse-policy", "plugin" => "levixel",
      "inputSets" => @scopes.to_h { |target, scope| [target, scope.fetch("inputPaths")] },
      "targets" => @scopes.to_h do |target, scope|
        [target, {"artifactRoles" => scope.fetch("artifactRoles"), "inputSets" => [target]}]
      end
    }
  end

  def materialize(value, directory, contents = {})
    value = JSON.parse(JSON.generate(value))
    value.fetch("artifacts").each do |entry|
      path = directory.join(entry.fetch("file"))
      FileUtils.mkdir_p(path.parent)
      path.binwrite(contents.fetch(entry.fetch("role"), entry.fetch("role") + "\n"))
      entry["bytes"] = path.size
      entry["sha256"] = Digest::SHA256.file(path).hexdigest
    end
    payload = value.fetch("artifacts").sort_by { |entry| entry.fetch("role") }.map do |entry|
      %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
    end.join
    value["artifactSetSha256"] = Digest::SHA256.hexdigest(payload)
    value["candidateId"] = "#{value.fetch("plugin")}-#{value.fetch("version")}-#{value.dig("source", "commit")[0, 12]}-#{value.fetch("artifactSetSha256")[0, 12]}"
    directory.join("candidate.json").write(AcceptanceReuse.json(value))
    value
  end

  def test_publish_gate_independently_checks_reuse
    product = @root.join("product")
    FileUtils.mkdir_p(product.join("scripts"))
    original = Pathname.new(__dir__).parent
    %w[verify-publish-candidate.rb native-release-manifest.rb native-artifact-reuse.rb
       release-policy.rb acceptance-reuse.rb git-input-digest.rb].each do |name|
      FileUtils.cp(original.join("scripts", name), product.join("scripts", name))
    end
    FileUtils.cp(original.join("release-policy.json"), product.join("release-policy.json"))
    FileUtils.cp(original.join("native-reuse-policy.json"), product.join("native-reuse-policy.json"))
    product.join("plugin.yaml").write("id: levixel\nversion: 1.0.0\n")
    product.join("acceptance-reuse-policy.json").write(AcceptanceReuse.json(
      reuse_policy
    ))
    # This fixture tests the evidence gate, not platform binary construction.
    provenance = product.join("scripts/verify-native-manifest-ios-provenance.sh")
    provenance.write("#!/bin/sh\nexit 0\n")
    File.chmod(0o755, provenance)
    GitInputDigest.git(product, "init", "-q")
    GitInputDigest.git(product, "config", "user.name", "Test")
    GitInputDigest.git(product, "config", "user.email", "test@example.invalid")
    GitInputDigest.git(product, "config", "commit.gpgsign", "false")
    GitInputDigest.git(product, "config", "tag.gpgsign", "false")
    GitInputDigest.git(product, "add", ".")
    GitInputDigest.git(product, "commit", "-qm", "fixture")
    product_commit = GitInputDigest.git(product, "rev-parse", "HEAD").strip
    GitInputDigest.git(product, "tag", "-a", "1.0.0", "-m", "fixture")
    @current = candidate(product_commit)
    native_roles = @current.fetch("artifacts").map { |entry| entry.fetch("role") }.select do |role|
      role.start_with?("native-") && !role.start_with?("native-build-")
    end
    native_manifest = {
      "schemaVersion" => 2, "plugin" => "levixel", "version" => "1.0.0", "commit" => product_commit,
      "dirty" => false, "androidMavenSigned" => true,
      "buildProvenance" => {"iosXcframework" => {"sourceCommit" => product_commit, "sourceDigest" => "d" * 64}},
      "artifacts" => native_roles.map do |role|
        content = role + "\n"
        {"file" => role, "bytes" => content.bytesize, "sha256" => Digest::SHA256.hexdigest(content)}
      end
    }
    current_dir = @root.join("current-candidate")
    @current = materialize(@current, current_dir, "native-build-manifest" => AcceptanceReuse.json(native_manifest))
    @source = materialize(@source, @root.join("source-candidate"))
    @run.merge!(AcceptanceReuse.identity(@source, AcceptanceReuse.checksum(@source), @target))
    reuse = build
    digest = AcceptanceReuse.checksum(@current)
    automated = @policy.dig("acceptance", "automatedTargets").to_h do |target|
      run = {"schemaVersion" => 1, "kind" => "plugin-candidate-automated-run", "status" => "passed",
             "exitCode" => 0}.merge(AcceptanceReuse.identity(@current, digest, target)).merge(
        "command" => ["verification/levixel/verify.sh", "--candidate", @current.fetch("candidateId"), target],
        "startedAt" => (Time.now.utc - 20).iso8601(6), "completedAt" => (Time.now.utc - 10).iso8601(6),
        "verifier" => {"repository" => @repository, "commit" => @after, "headAfter" => @after,
                       "dirtyBefore" => false, "dirtyAfter" => false}
      )
      [target, {"status" => "passed", "evidence" => run.merge("runSha256" => AcceptanceReuse.checksum(run))}]
    end
    manual = @policy.dig("acceptance", "manualTargets").to_h do |target|
      run = @run.merge(AcceptanceReuse.identity(@current, digest, target)).merge("verifier" => @verifier)
      run = reuse if target == @target
      [target, {"status" => "passed", "evidence" => run.merge("runSha256" => AcceptanceReuse.checksum(run))}]
    end
    receipt = {
      "schemaVersion" => @policy.fetch("acceptanceReceiptSchemaVersion"), "kind" => "plugin-candidate-acceptance",
      "status" => "accepted", "plugin" => "levixel", "version" => "1.0.0", "candidateId" => @current.fetch("candidateId"),
      "artifactSetSha256" => @current.fetch("artifactSetSha256"), "candidateManifestSha256" => digest,
      "candidateSource" => @current.fetch("source"), "acceptanceRequirements" => @current.fetch("acceptance"),
      "checks" => {"automatedConsumers" => automated, "manualDeviceMatrix" => manual},
      "verifier" => @verifier, "recordedAt" => Time.now.utc.iso8601(6)
    }
    receipt_path = @root.join("receipt.json")
    receipt_path.write(AcceptanceReuse.json(receipt))
    command = [RbConfig.ruby, product.join("scripts/verify-publish-candidate.rb").to_s,
               "--candidate", current_dir.join("candidate.json").to_s, "--acceptance", receipt_path.to_s]
    output, error, status = Open3.capture3(*command, "--verifier-repository", @root.to_s)
    assert status.success?, error
    assert_match(/Verified accepted/, output)
    _output, error, status = Open3.capture3(*command)
    refute status.success?
    assert_match(/explicit verifier repository/, error)
    changed = manual.fetch(@target).fetch("evidence")
    changed["inputDigest"] = "f" * 64
    changed["runSha256"] = AcceptanceReuse.checksum(changed.reject { |key, _value| key == "runSha256" })
    receipt_path.write(AcceptanceReuse.json(receipt))
    _output, error, status = Open3.capture3(*command, "--verifier-repository", @root.to_s)
    refute status.success?
    assert_match(/Verifier inputs changed/, error)
  end

  def test_clean_head_rejects_dirty_files_and_commit_change
    assert_equal @after, GitInputDigest.clean_head!(@root)
    @root.join("dirty.txt").write("not committed")
    assert_raises(GitInputDigest::Error) { GitInputDigest.clean_head!(@root) }
    commit
    assert_raises(GitInputDigest::Error) { GitInputDigest.clean_head!(@root, @after) }
  end
end
