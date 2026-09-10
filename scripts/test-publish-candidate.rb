#!/usr/bin/env ruby

require "minitest/autorun"
require "fileutils"
require "open3"
require "pathname"
require "tmpdir"
require "time"
require_relative "native-artifact-reuse"

class PublishCandidateTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir("publish-candidate-test-")
    @root = Pathname.new(@temporary)
    @product = @root.join("product")
    @product.join("scripts").mkpath
    source = Pathname.new(__dir__).parent
    %w[verify-publish-candidate.rb snapshot-release-candidate.rb release-policy.rb
       native-release-manifest.rb native-artifact-reuse.rb git-input-digest.rb].each do |file|
      FileUtils.cp(source.join("scripts", file), @product.join("scripts", file))
    end
    %w[release-policy.json native-reuse-policy.json].each do |file|
      FileUtils.cp(source.join(file), @product.join(file))
    end
    @policy = ReleasePolicy.load(@product.join("release-policy.json"))
    @product.join("plugin.yaml").write("id: levixel\nversion: 1.0.0\n")
    @product.join(".gitignore").write("/dist/\n")
    # This fixture exercises publication checks, not native binary compilation.
    provenance = @product.join("scripts/verify-native-manifest-ios-provenance.sh")
    provenance.write("#!/bin/sh\nexit 0\n")
    File.chmod(0o755, provenance)
    git("init", "-q")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.invalid")
    git("config", "commit.gpgsign", "false")
    git("config", "tag.gpgsign", "false")
    git("add", ".")
    git("commit", "-qm", "fixture")
    @commit = git("rev-parse", "HEAD").strip
    git("tag", "-a", "1.0.0", "-m", "fixture")
    @candidate_root = @product.join("dist")
    qualifications = @policy.fetch("qualifications").to_h { |key| [key, true] }
    roles = ReleasePolicy.expected_artifact_roles(@policy, qualifications)
    contents = roles.to_h { |role| [role, role + "\n"] }
    native_roles = roles.select { |role| role.start_with?("native-") && !role.start_with?("native-build-") }
    native_manifest = {
      "schemaVersion" => 2, "plugin" => "levixel", "version" => "1.0.0",
      "commit" => @commit, "dirty" => false, "androidMavenSigned" => true,
      "buildProvenance" => {"iosXcframework" => {"sourceCommit" => @commit, "sourceDigest" => "d" * 64}},
      "artifacts" => native_roles.map do |role|
        content = contents.fetch(role)
        {"file" => role, "bytes" => content.bytesize, "sha256" => Digest::SHA256.hexdigest(content)}
      end,
    }
    contents["native-build-manifest"] = JSON.pretty_generate(native_manifest) + "\n"
    entries = contents.map do |role, content|
      path = @candidate_root.join("packages", role)
      path.parent.mkpath
      path.binwrite(content)
      {"role" => role, "file" => "packages/#{role}", "bytes" => path.size,
       "sha256" => Digest::SHA256.file(path).hexdigest}
    end
    set_payload = entries.sort_by { |entry| entry.fetch("role") }.map do |entry|
      %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
    end.join
    digest = Digest::SHA256.hexdigest(set_payload)
    @candidate = {
      "schemaVersion" => @policy.fetch("candidateSchemaVersion"), "kind" => "plugin-release-candidate",
      "state" => "candidate", "acceptanceEligible" => true, "plugin" => "levixel", "version" => "1.0.0",
      "candidateId" => "levixel-1.0.0-#{@commit[0, 12]}-#{digest[0, 12]}", "artifactSetSha256" => digest,
      "source" => {"repository" => @policy.fetch("sourceRepository"), "commit" => @commit, "dirty" => false},
      "acceptance" => @policy.fetch("acceptance"), "qualifications" => qualifications, "artifacts" => entries,
    }
    @candidate_path = @candidate_root.join("candidate.json")
    @candidate_path.write(JSON.pretty_generate(@candidate) + "\n")
    @candidate_digest = Digest::SHA256.file(@candidate_path).hexdigest
    @verifier = {"repository" => @policy.fetch("verifierRepository"), "commit" => "f" * 40, "dirty" => false}
    automated = @policy.dig("acceptance", "automatedTargets").to_h do |target|
      run = {
        "schemaVersion" => 1, "kind" => "plugin-candidate-automated-run",
        "status" => "passed", "exitCode" => 0, "plugin" => "levixel", "version" => "1.0.0",
        "candidateId" => @candidate.fetch("candidateId"), "artifactSetSha256" => digest,
        "candidateManifestSha256" => @candidate_digest, "target" => target,
        "command" => ["verification/levixel/verify.sh", "--candidate", @candidate.fetch("candidateId"), target],
        "startedAt" => (Time.now.utc - 20).iso8601(6), "completedAt" => (Time.now.utc - 10).iso8601(6),
        "verifier" => {"repository" => @verifier.fetch("repository"), "commit" => @verifier.fetch("commit"),
                       "headAfter" => @verifier.fetch("commit"), "dirtyBefore" => false, "dirtyAfter" => false},
      }
      [target, {"status" => "passed", "evidence" => run.merge("runSha256" => Digest::SHA256.hexdigest(JSON.pretty_generate(run) + "\n"))}]
    end
    @receipt = {
      "schemaVersion" => @policy.fetch("acceptanceReceiptSchemaVersion"), "kind" => "plugin-candidate-acceptance",
      "status" => "accepted", "plugin" => "levixel", "version" => "1.0.0",
      "candidateId" => @candidate.fetch("candidateId"), "artifactSetSha256" => digest,
      "candidateManifestSha256" => @candidate_digest, "candidateSource" => @candidate.fetch("source"),
      "acceptanceRequirements" => @candidate.fetch("acceptance"),
      "checks" => {"automatedConsumers" => automated},
      "verifier" => @verifier, "recordedAt" => Time.now.utc.iso8601(6),
    }
    @receipt_path = @root.join("receipt.json")
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary
  end

  def git(*args)
    out, err, status = Open3.capture3("git", "-C", @product.to_s, *args)
    raise err unless status.success?
    out
  end

  def run_gate
    @receipt_path.write(JSON.pretty_generate(@receipt) + "\n")
    Open3.capture3(
      RbConfig.ruby, @product.join("scripts/verify-publish-candidate.rb").to_s,
      "--candidate", @candidate_path.to_s, "--acceptance", @receipt_path.to_s
    )
  end

  def assert_rejected(pattern)
    _out, err, status = run_gate
    refute status.success?, "Gate accepted invalid input"
    assert_match pattern, err
  end

  def test_verified_artifacts_do_not_require_manual_paperwork
    out, err, status = run_gate
    assert status.success?, err
    assert_match(/Verified automated checks and artifacts/, out)
    assert_match(/native-android-aar=/, out)
    assert_equal ["automatedConsumers"], @receipt.fetch("checks").keys
  end

  def test_incomplete_or_failed_automated_checks_cannot_publish
    checks = @receipt.dig("checks", "automatedConsumers")
    target = checks.keys.first
    original = checks.delete(target)
    assert_rejected(/Automated acceptance targets differ/)
    checks[target] = {"status" => "pending"}
    assert_rejected(/Automated consumer acceptance did not pass/)
    checks[target] = original.merge("status" => "failed")
    assert_rejected(/Automated consumer acceptance did not pass/)
  end

  def test_results_for_another_candidate_cannot_publish
    @receipt["candidateManifestSha256"] = "a" * 64
    assert_rejected(/Acceptance receipt candidateManifestSha256 differs/)
  end

  def test_modified_artifacts_cannot_publish
    @candidate_root.join(@candidate.fetch("artifacts").first.fetch("file")).write("changed bytes")
    assert_rejected(/artifact byte count differs|artifact checksum differs/)
  end

  def test_dirty_or_different_source_cannot_publish
    @product.join("source-change.txt").write("changed release source")
    assert_rejected(/requires a clean source worktree/)
    git("add", ".")
    git("commit", "-qm", "changed fixture")
    assert_rejected(/Current source commit differs/)
  end

  def test_canonical_tag_must_be_annotated_and_point_to_the_candidate
    git("tag", "-d", "1.0.0")
    assert_rejected(/Canonical annotated tag .* is missing/)
    git("tag", "1.0.0")
    assert_rejected(/Canonical annotated tag .* is missing/)
    git("tag", "-d", "1.0.0")
    other_commit = git("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "other fixture").strip
    git("tag", "-a", "1.0.0", other_commit, "-m", "wrong fixture target")
    assert_rejected(/does not point to the accepted source commit/)
  end

  def test_candidate_references_one_artifact_set_and_retires_only_known_old_outputs
    command = [RbConfig.ruby, @product.join("scripts/snapshot-release-candidate.rb").to_s,
               "--plugin", "levixel", "--policy", @product.join("release-policy.json").to_s,
               "--version", "2.0.0", "--repository", @policy.fetch("sourceRepository"),
               "--commit", @commit, "--dirty", "false", "--root", @product.to_s,
               "--state", "candidate"]
    @candidate.fetch("qualifications").each { |key, value| command += ["--qualification", "#{key}=#{value}"] }
    @policy.dig("acceptance", "automatedTargets").each { |target| command += ["--automated-target", target] }
    files = @candidate.fetch("artifacts").map do |entry|
      path = @candidate_root.join("packages", "#{entry.fetch('role')}-2.0.0.bin")
      path.write(entry.fetch("role"))
      command += ["--artifact", "#{entry.fetch('role')}=#{path}"]
      path
    end
    older = files.first.sub("2.0.0", "0.9.0")
    stable = files.first.sub("2.0.0", "1.0.0")
    unknown = @candidate_root.join("packages/unrelated-0.9.0.txt")
    [older, stable, unknown].each { |path| path.write("retention fixture") }
    original_stat = files.first.stat
    output, error, status = Open3.capture3(*command)
    assert status.success?, error
    assert_equal @candidate_path.realpath.to_s, output.lines.first.strip
    manifest = JSON.parse(@candidate_path.read)
    loaded, = NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy)
    assert_equal manifest, loaded
    assert_equal files.map(&:to_s).sort,
                 manifest.fetch("artifacts").map { |entry| @candidate_root.join(entry.fetch("file")).to_s }.sort
    assert_equal original_stat.ino, files.first.stat.ino
    assert_equal original_stat.mtime, files.first.stat.mtime
    refute older.exist?
    assert stable.file?
    assert unknown.file?
    refute @candidate_root.join("candidates").exist?
    files.first.write("changed artifact")
    _output, error, status = Open3.capture3(*command)
    assert status.success?, error
    refute_equal manifest.fetch("candidateId"), JSON.parse(@candidate_path.read).fetch("candidateId")
    assert_equal [@candidate_path], @candidate_root.glob("*.json")
    older.write("must survive a failed candidate")
    files.first.unlink
    _output, error, status = Open3.capture3(*command)
    refute status.success?
    assert_match(/not a regular file/, error)
    assert older.file?
  end
end
