#!/usr/bin/env ruby

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require_relative "native-release-manifest"

class NativeArtifactReuseTest < Minitest::Test
  def setup
    @repository = Pathname.new(__dir__).parent
    @policy = ReleasePolicy.load(@repository.join("release-policy.json"))
    @definitions = NativeArtifactReuse.groups(policy: @policy)
    @temporary = Dir.mktmpdir("native-artifact-reuse-test-")
    @root = Pathname.new(@temporary)
    git("init", "-q")
    git("config", "user.name", "Test")
    git("config", "user.email", "test@example.invalid")
    git("config", "commit.gpgsign", "false")
    @definitions.values.flat_map { |group| group.fetch("inputs") }.uniq.each do |scope|
      path = @root.join(scope)
      path = path.join("input.txt") if @repository.join(scope).directory?
      FileUtils.mkdir_p(path.parent)
      path.write("tracked input\n")
    end
    @before = commit
    @root.join("unrelated.txt").write("unrelated\n")
    @after = commit
    @snapshot = @root.join("snapshot")
    qualifications = @policy.fetch("qualifications").to_h { |key| [key, true] }
    @entries = ReleasePolicy.expected_artifact_roles(@policy, qualifications).sort.map do |role|
      file = @snapshot.join("artifacts", role)
      FileUtils.mkdir_p(file.parent)
      file.write(role + "\n")
      {"role" => role, "file" => "artifacts/#{role}", "bytes" => file.size,
       "sha256" => Digest::SHA256.file(file).hexdigest}
    end
    payload = @entries.map { |entry| %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n" }.join
    digest = Digest::SHA256.hexdigest(payload)
    @candidate = {
      "schemaVersion" => @policy.fetch("candidateSchemaVersion"), "kind" => "plugin-release-candidate",
      "state" => "candidate", "acceptanceEligible" => true, "plugin" => "levixel", "version" => "1.0.0",
      "candidateId" => "levixel-1.0.0-#{@before[0, 12]}-#{digest[0, 12]}", "artifactSetSha256" => digest,
      "source" => {"repository" => @policy.fetch("sourceRepository"), "commit" => @before, "dirty" => false},
      "acceptance" => @policy.fetch("acceptance"), "qualifications" => qualifications, "artifacts" => @entries
    }
    @candidate_path = @snapshot.join("candidate.json")
    @candidate_path.write(NativeArtifactReuse.canonical_json(@candidate))
    native_roles = @definitions.values.flat_map { |group| group.fetch("roles") }
    @manifest = {
      "schemaVersion" => 2, "plugin" => "levixel", "version" => "1.0.0", "commit" => @after,
      "dirty" => false, "androidMavenSigned" => true,
      "buildProvenance" => {"iosXcframework" => {"sourceCommit" => @before, "sourceDigest" => "d" * 64}},
      "artifacts" => @entries.select { |entry| native_roles.include?(entry.fetch("role")) }.map do |entry|
        {"file" => File.basename(entry.fetch("file")), "bytes" => entry.fetch("bytes"), "sha256" => entry.fetch("sha256")}
      end
    }
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

  def proof(names = @definitions.keys)
    {
      "sourceCandidate" => @candidate,
      "sourceCandidateSha256" => Digest::SHA256.hexdigest(NativeArtifactReuse.canonical_json(@candidate)),
      "platformInputs" => names.to_h do |name|
        [name, GitInputDigest.digest(@root, @before, @definitions.fetch(name).fetch("inputs"))]
      end
    }
  end

  def test_canonical_json_preserves_the_published_layout_including_empty_containers
    value = {"manualTargets" => [], "nested" => [{}, []], "text" => "[] {} \"换行\"\n", "flags" => [true, false, nil, 12]}
    expected = <<~'JSON'
      {
        "manualTargets": [

        ],
        "nested": [
          {
          },
          [

          ]
        ],
        "text": "[] {} \"换行\"\n",
        "flags": [
          true,
          false,
          null,
          12
        ]
      }
    JSON
    assert_equal expected, NativeArtifactReuse.canonical_json(value)
    assert_equal value, JSON.parse(NativeArtifactReuse.canonical_json(value))
    assert_equal "[\n\n]\n", NativeArtifactReuse.canonical_json([])
    assert_equal "{\n}\n", NativeArtifactReuse.canonical_json({})
  end

  def test_source_snapshot_content_changes_still_invalidate_its_digest
    record = proof
    record.fetch("sourceCandidate").fetch("acceptance")["manualTargets"] = ["device"]
    error = assert_raises(NativeArtifactReuse::Error) do
      NativeArtifactReuse.validate!(record, manifest: @manifest)
    end
    assert_match(/source manifest digest differs/, error.message)
  end

  def test_each_configured_group_can_be_reused_independently
    @definitions.each_key do |name|
      record = proof([name])
      assert_equal record, NativeArtifactReuse.validate!(record, manifest: @manifest)
      NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after)
      @manifest.fetch("buildProvenance")["artifactReuse"] = record
      assert_equal @manifest, NativeReleaseManifest.validate!(@manifest, plugin: "levixel", version: "1.0.0")
    end
  end

  def test_full_snapshot_is_verified_without_mutation
    original = @candidate_path.binread
    loaded, directory = NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy)
    assert_equal @candidate, loaded
    assert_equal @snapshot.realpath, directory
    assert_equal original, @candidate_path.binread
  end

  def test_unselected_artifact_tampering_also_rejects_the_source_snapshot
    @snapshot.join(@entries.last.fetch("file")).write("modified")
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy) }
  end

  def test_changed_acceptance_requirements_do_not_rebuild_unchanged_binaries
    @candidate["acceptance"] = {"manualTargets" => ["device"], "manualScenarios" => ["open-and-close"]}
    @candidate_path.write(NativeArtifactReuse.canonical_json(@candidate))
    assert_raises(ReleasePolicy::Error) { ReleasePolicy.validate_candidate!(@candidate, @policy) }
    loaded, = NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy)
    assert_equal @candidate, loaded
    NativeArtifactReuse.validate!(proof, manifest: @manifest)
    NativeArtifactReuse.verify_inputs!(proof, root: @root, commit: @after)
  end

  def test_symlink_and_missing_artifact_reject_the_snapshot
    path = @snapshot.join(@entries.first.fetch("file"))
    path.delete
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy) }
    File.symlink(@snapshot.join(@entries.last.fetch("file")), path)
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.load_candidate!(@candidate_path, policy: @policy) }
  end

  def test_changed_native_input_invalidates_only_its_group
    record = proof
    @root.join("native/harmonyos/input.txt").write("new implementation")
    @after = commit
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after) }
    unaffected = proof(@definitions.keys - ["harmonyos"])
    NativeArtifactReuse.verify_inputs!(unaffected, root: @root, commit: @after)
  end

  def test_ios_project_scheme_and_workspace_are_in_scope
    %w[Levixel.xcodeproj/xcshareddata/xcschemes/Levixel.xcscheme Levixel.xcodeproj/project.xcworkspace/contents.xcworkspacedata].each do |relative|
      path = @root.join("native/ios", relative)
      FileUtils.mkdir_p(path.parent)
      path.write("changed build input")
      @after = commit
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(proof(["ios"]), root: @root, commit: @after) }
    end
  end

  def test_packaging_and_legal_input_changes_reject_reuse
    ["scripts/package-native-android.sh", "LICENSE"].each do |relative|
      @root.join(relative).write("changed")
      @after = commit
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(proof(["android"]), root: @root, commit: @after) }
    end
  end

  def test_unknown_empty_or_forged_proof_rejected
    [
      ->(value) { value["platformInputs"] = {} },
      ->(value) { value["platformInputs"]["unknown"] = "a" * 64 },
      ->(value) { value["platformInputs"]["android"] = "invalid" },
      ->(value) { value["sourceCandidateSha256"] = "a" * 64 },
      ->(value) { value["extra"] = true },
    ].each do |mutation|
      record = JSON.parse(NativeArtifactReuse.canonical_json(proof))
      mutation.call(record)
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.validate!(record, manifest: @manifest) }
    end
  end

  def test_changed_artifact_or_unsigned_destination_rejects_reuse
    @manifest["androidMavenSigned"] = false
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.validate!(proof, manifest: @manifest) }
    @manifest["androidMavenSigned"] = true
    @manifest.fetch("artifacts").first["sha256"] = "f" * 64
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.validate!(proof, manifest: @manifest) }
  end

  def test_wrong_commit_or_missing_history_rejects_reuse
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(proof, root: @root, commit: "f" * 40) }
    record = proof
    record["platformInputs"]["android"] = "f" * 64
    assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.verify_inputs!(record, root: @root, commit: @after) }
  end

  def test_policy_cannot_omit_duplicate_or_invent_roles
    configuration = JSON.parse(@repository.join("native-reuse-policy.json").read)
    [
      ->(value) { value["groups"].delete("ios") },
      ->(value) { value["groups"]["ios"]["roles"] = ["unknown"] },
      ->(value) { value["groups"]["ios"]["directory"] = "../../escape" },
      ->(value) { value["groups"]["ios"]["inputs"] = [] },
    ].each do |mutation|
      changed = JSON.parse(JSON.generate(configuration))
      mutation.call(changed)
      path = @root.join("policy.json")
      path.write(JSON.pretty_generate(changed))
      assert_raises(NativeArtifactReuse::Error) { NativeArtifactReuse.groups(policy: @policy, path: path) }
    end
  end

  def preparation_fixture(in_place: false)
    # Compiler and cryptographic primitives have separate tests. This fixture
    # exercises the real orchestration, copying, manifest, and Git-input gates.
    %w[prepare-native-release.sh reuse-native-artifacts.rb native-release-manifest.rb
       native-artifact-reuse.rb git-input-digest.rb release-policy.rb
       verify-native-manifest-ios-provenance.sh].each do |name|
      FileUtils.cp(@repository.join("scripts", name), @root.join("scripts", name))
    end
    %w[release-policy.json native-reuse-policy.json].each do |name|
      FileUtils.cp(@repository.join(name), @root.join(name))
    end
    @root.join("plugin.yaml").write("id: levixel\nversion: 1.0.0\n")
    @root.join(".gitignore").write("/dist/\n/snapshot/\n")
    scripts = {
      "assert-release-version-available.sh" => "exit 0\n",
      "verify-release-readiness.sh" => "exit 0\n",
      "verify-native-all.sh" => "printf 'verify-native\\n' >> \"$LEVIXEL_TEST_EVENTS\"\n",
      "package-native-all.sh" => "echo 'Unexpected full rebuild' >&2\nexit 91\n",
      "prepare-maven-central-bundle.sh" => "echo 'Unexpected re-signing' >&2\nexit 92\n",
      "compute-ios-source-digest.rb" => "printf '#{'a' * 64}\\n'\n",
      "verify-ios-xcframework-provenance.sh" => "printf '%s #{'a' * 64}\\n' \"$(git rev-list --max-parents=0 HEAD)\"\n",
    }
    @definitions.each_key { |name| scripts["package-native-#{name}.sh"] = "echo 'Unexpected selected-group rebuild' >&2\nexit 93\n" }
    scripts.each do |name, content|
      path = @root.join("scripts", name)
      path.write("#!/bin/sh\nset -eu\n" + content)
      File.chmod(0o755, path)
    end
    @root.join("scripts/verify-maven-reuse.rb").write(<<~RUBY)
      module MavenReuse
        class Error < StandardError; end
        def self.verify!(**arguments)
          File.open(ENV.fetch("LEVIXEL_TEST_EVENTS"), "a") { |file| file.puts("verify-existing-signatures") }
        end
      end
    RUBY
    @before = commit
    @root.join("unrelated.txt").write("new release orchestration commit\n")
    @after = commit
    filenames = {
      "native-android-aar" => "levixel-1.0.0.aar",
      "native-android-maven-repository" => "levixel-1.0.0-maven.zip",
      "native-android-maven-central-bundle" => "levixel-1.0.0-maven-central.zip",
      "native-ios-xcframework" => "levixel-1.0.0.xcframework.zip",
      "native-ios-swift-package" => "levixel-1.0.0-swift-package.zip",
      "native-harmonyos-har" => "levixel-1.0.0.har",
    }
    contents = filenames.to_h { |role, _filename| [role, role + "\n"] }
    @manifest["commit"] = @before
    @manifest["buildProvenance"] = {"iosXcframework" => {
      "sourceCommit" => git("rev-list", "--max-parents=0", "HEAD"), "sourceDigest" => "a" * 64
    }}
    @manifest["artifacts"] = filenames.map do |role, filename|
      data = contents.fetch(role)
      {"file" => filename, "bytes" => data.bytesize, "sha256" => Digest::SHA256.hexdigest(data)}
    end
    contents["native-build-manifest"] = JSON.pretty_generate(@manifest) + "\n"
    if in_place
      @snapshot = @root.join("dist")
      @candidate_path = @snapshot.join("candidate.json")
    end
    @entries.each do |entry|
      role = entry.fetch("role")
      primary = role.delete_prefix("checksum-")
      if filenames.key?(primary)
        filename = filenames.fetch(primary)
        if role.start_with?("checksum-")
          contents[role] = "#{Digest::SHA256.hexdigest(contents.fetch(primary))}  #{filename}\n"
          filename += ".sha256"
        end
        directory = in_place ? @definitions.values.find { |group| group.fetch("roles").include?(primary) }.fetch("directory") : "artifacts"
        entry["file"] = "#{directory}/#{filename}"
      end
      path = @snapshot.join(entry.fetch("file"))
      path.parent.mkpath
      path.write(contents.fetch(role, role + "\n"))
      entry["bytes"] = path.size
      entry["sha256"] = Digest::SHA256.file(path).hexdigest
    end
    payload = @entries.sort_by { |entry| entry.fetch("role") }.map do |entry|
      %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
    end.join
    @candidate["source"]["commit"] = @before
    @candidate["artifactSetSha256"] = Digest::SHA256.hexdigest(payload)
    @candidate["candidateId"] = "levixel-1.0.0-#{@before[0, 12]}-#{@candidate.fetch('artifactSetSha256')[0, 12]}"
    @candidate_path.write(NativeArtifactReuse.canonical_json(@candidate))
    @root.join("dist").mkpath
    @environment = {
      "LEVIXEL_SIGNING_KEY" => nil, "LEVIXEL_SIGNING_PASSWORD" => nil,
      "LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_ZIP" => nil, "LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_SHA256" => nil,
      "LEVIXEL_IOS_BINARY_URL" => nil, "LEVIXEL_TEST_EVENTS" => @root.join("dist/events").to_s
    }
  end

  def test_preparation_can_reuse_every_group_without_signing_or_rebuilding
    preparation_fixture
    original = @candidate_path.binread
    command = ["/bin/bash", @root.join("scripts/prepare-native-release.sh").to_s, "--reuse-candidate", @candidate_path.to_s]
    @definitions.each_key { |name| command.concat(["--reuse", name]) }
    output, error, status = Open3.capture3(@environment, *command, chdir: @root.to_s)
    assert status.success?, output + error
    events = @root.join("dist/events").read.lines.map(&:chomp)
    assert_equal %w[verify-existing-signatures verify-native], events
    released = JSON.parse(@root.join("dist/native-release/levixel-native-1.0.0.json").read)
    assert_equal @after, released.fetch("commit")
    assert_equal @candidate, released.dig("buildProvenance", "artifactReuse", "sourceCandidate")
    assert_equal @definitions.keys.sort, released.dig("buildProvenance", "artifactReuse", "platformInputs").keys.sort
    assert_equal original, @candidate_path.binread
    @definitions.each_value do |group|
      group.fetch("roles").each do |role|
        entry = @entries.find { |item| item.fetch("role") == role }
        output_file = @root.join("dist", group.fetch("directory"), File.basename(entry.fetch("file")))
        assert_equal @snapshot.join(entry.fetch("file")).binread, output_file.binread
      end
    end
    assert_equal @after, GitInputDigest.clean_head!(@root)
  end

  def test_current_provenance_verifier_uses_the_explicit_release_source_and_history
    preparation_fixture
    @manifest["commit"] = @after
    @manifest.fetch("buildProvenance")["artifactReuse"] = proof
    manifest_path = @root.join("manifest.json")
    manifest_path.write(JSON.pretty_generate(@manifest) + "\n")
    ios = @entries.find { |entry| entry.fetch("role") == "native-ios-xcframework" }
    # A frozen tag can contain the old validator. Only its source/digest helpers
    # and history should be used, not that outdated manifest reader.
    @root.join("scripts/native-artifact-reuse.rb").write("abort 'Outdated manifest reader was used'\n")
    output, error, status = Open3.capture3(
      "/bin/bash", @repository.join("scripts/verify-native-manifest-ios-provenance.sh").to_s,
      manifest_path.to_s, @snapshot.join(ios.fetch("file")).to_s, "1.0.0", @root.to_s,
      chdir: @root.to_s
    )
    assert status.success?, output + error
    assert_match(/Verified iOS binary provenance/, output)
  end

  def test_current_platform_outputs_are_reused_in_place
    preparation_fixture(in_place: true)
    paths = @definitions.values.flat_map { |group| group.fetch("roles") }.map do |role|
      @snapshot.join(@entries.find { |entry| entry.fetch("role") == role }.fetch("file"))
    end
    before = paths.to_h { |path| [path, [path.stat.ino, path.mtime, path.binread]] }
    arguments = @definitions.keys.flat_map { |name| ["--reuse", name] }
    _output, error, status = Open3.capture3(
      @environment, "/bin/bash", @root.join("scripts/prepare-native-release.sh").to_s,
      "--reuse-candidate", @candidate_path.to_s, *arguments, chdir: @root.to_s
    )
    assert status.success?, error
    paths.each { |path| assert_equal before.fetch(path), [path.stat.ino, path.mtime, path.binread] }
  end

  def test_reuse_does_not_waive_credentials_for_an_unselected_signing_group
    preparation_fixture
    _output, error, status = Open3.capture3(
      @environment, "/bin/bash", @root.join("scripts/prepare-native-release.sh").to_s,
      "--reuse-candidate", @candidate_path.to_s, "--reuse", "ios", chdir: @root.to_s
    )
    refute status.success?
    assert_match(/requires LEVIXEL_SIGNING_KEY/, error)
    refute @root.join("dist/events").exist?
    refute @root.join("dist/native-release/levixel-native-1.0.0.json").exist?
  end

  def test_unselected_changed_group_is_built_without_rebuilding_reused_groups
    preparation_fixture
    @root.join("native/harmonyos/input.txt").write("changed native implementation")
    script = @root.join("scripts/package-native-harmonyos.sh")
    script.write(<<~SHELL)
      #!/bin/sh
      set -eu
      printf 'build-unselected\n' >> "$LEVIXEL_TEST_EVENTS"
      mkdir -p dist/native-harmonyos
      cd dist/native-harmonyos
      printf 'rebuilt artifact\n' > levixel-1.0.0.har
      shasum -a 256 levixel-1.0.0.har > levixel-1.0.0.har.sha256
    SHELL
    @after = commit
    command = ["/bin/bash", @root.join("scripts/prepare-native-release.sh").to_s, "--reuse-candidate", @candidate_path.to_s]
    (@definitions.keys - ["harmonyos"]).each { |name| command.concat(["--reuse", name]) }
    output, error, status = Open3.capture3(@environment, *command, chdir: @root.to_s)
    assert status.success?, output + error
    assert_equal %w[verify-existing-signatures build-unselected verify-native], @root.join("dist/events").read.lines.map(&:chomp)
    manifest = JSON.parse(@root.join("dist/native-release/levixel-native-1.0.0.json").read)
    assert_equal @after, manifest.fetch("commit")
    refute manifest.dig("buildProvenance", "artifactReuse", "platformInputs").key?("harmonyos")
    entry = manifest.fetch("artifacts").find { |artifact| artifact.fetch("file") == "levixel-1.0.0.har" }
    assert_equal Digest::SHA256.hexdigest("rebuilt artifact\n"), entry.fetch("sha256")
    assert_equal @after, GitInputDigest.clean_head!(@root)
  end

  def test_reuse_proof_cannot_be_written_into_the_source_snapshot
    preparation_fixture
    original = @candidate_path.binread
    proof_path = @snapshot.join("proof.json")
    _output, error, status = Open3.capture3(
      @environment, RbConfig.ruby, @root.join("scripts/reuse-native-artifacts.rb").to_s,
      "--candidate", @candidate_path.to_s, "--group", "ios", "--proof", proof_path.to_s,
      chdir: @root.to_s
    )
    refute status.success?
    assert_match(/must not be written inside the source snapshot/, error)
    refute proof_path.exist?
    refute @root.join("dist/native-ios").exist?
    assert_equal original, @candidate_path.binread
  end
end
