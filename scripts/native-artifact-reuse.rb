require "digest"
require "json"
require "pathname"
require_relative "git-input-digest"
require_relative "release-policy"

module NativeArtifactReuse
  class Error < StandardError; end

  module_function

  def fields!(value, fields, label)
    raise Error, "Unexpected #{label} fields" unless value.is_a?(Hash) && value.keys.sort == fields.sort
  end

  # Preserve the JSON 2.1 layout used by published candidate digests. Newer
  # JSON gems compact empty containers even when pretty_generate is requested.
  def canonical_json(value, depth = 0)
    indent = "  " * depth
    encoded = case value
              when Hash
                members = value.map do |key, item|
                  "#{indent}  #{JSON.generate(key.to_s)}: #{canonical_json(item, depth + 1)}"
                end
                "{\n" + members.join(",\n") + (members.empty? ? "" : "\n") + "#{indent}}"
              when Array
                members = value.map { |item| "#{indent}  #{canonical_json(item, depth + 1)}" }
                "[\n" + members.join(",\n") + "\n#{indent}]"
              else
                JSON.generate(value)
              end
    depth.zero? ? encoded + "\n" : encoded
  end

  def groups(policy: ReleasePolicy.load(File.expand_path("../release-policy.json", __dir__)),
             path: File.expand_path("../native-reuse-policy.json", __dir__))
    configuration = JSON.parse(File.read(path))
    fields!(configuration, %w[groups kind schemaVersion], "native reuse policy")
    raise Error, "Unexpected native reuse policy" unless
      configuration.fetch("schemaVersion") == 1 && configuration.fetch("kind") == "native-artifact-reuse-policy"
    groups = configuration.fetch("groups")
    raise Error, "Native reuse groups must be declared" unless groups.is_a?(Hash) && !groups.empty?
    groups.each do |name, group|
      raise Error, "Invalid native reuse group" unless name.match?(/\A[a-z][a-z0-9-]*\z/)
      fields!(group, %w[directory inputs roles], "native reuse group #{name}")
      raise Error, "Invalid native output directory" unless
        group.fetch("directory").is_a?(String) && group.fetch("directory").match?(/\Anative-[a-z][a-z0-9-]*\z/)
      %w[inputs roles].each do |field|
        values = group.fetch(field)
        raise Error, "Native #{field} must be sorted, unique, and non-empty" unless
          values.is_a?(Array) && !values.empty? && values.all? { |value| value.is_a?(String) } &&
            values == values.sort.uniq
      end
      group.fetch("inputs").each do |input|
        raise Error, "Unsafe native input scope: #{input.inspect}" unless
          input.match?(/\A[A-Za-z0-9_.\/-]+\z/) &&
            input.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
      end
    end
    roles = groups.values.flat_map { |group| group.fetch("roles") }
    expected = (policy.dig("artifactRoles", "required") +
      policy.dig("artifactRoles", "conditional").values.flatten).select do |role|
      role.start_with?("native-") && !role.start_with?("native-build-")
    end
    raise Error, "Native reuse roles must cover the release policy exactly once" unless
      roles.sort == expected.sort && roles.uniq == roles
    groups
  rescue JSON::ParserError, KeyError, Errno::ENOENT => error
    raise Error, "Invalid native reuse policy: #{error.message}"
  end

  def validate!(proof, manifest:, policy: ReleasePolicy.load(File.expand_path("../release-policy.json", __dir__)))
    fields!(proof, %w[platformInputs sourceCandidate sourceCandidateSha256], "native reuse proof")
    source = proof.fetch("sourceCandidate")
    ReleasePolicy.validate_artifact_snapshot!(source, policy)
    raise Error, "Native reuse requires an eligible candidate of the same version" unless
      source.fetch("state") == "candidate" && source.fetch("acceptanceEligible") == true &&
        source.fetch("version") == manifest.fetch("version") && source.fetch("plugin") == manifest.fetch("plugin")
    raise Error, "Native reuse source manifest digest differs" unless
      Digest::SHA256.hexdigest(canonical_json(source)) == proof.fetch("sourceCandidateSha256")
    raise Error, "Native reuse cannot certify a dirty or unsigned release" unless
      manifest.fetch("dirty") == false && manifest.fetch("androidMavenSigned") == true
    definitions = groups(policy: policy)
    inputs = proof.fetch("platformInputs")
    raise Error, "Native reuse must name known platforms" unless
      inputs.is_a?(Hash) && !inputs.empty? && (inputs.keys - definitions.keys).empty?
    artifacts = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
    source_artifacts = source.fetch("artifacts").to_h { |entry| [entry.fetch("role"), entry] }
    inputs.each do |platform, digest|
      raise Error, "Invalid native input digest: #{platform}" unless
        digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      definitions.fetch(platform).fetch("roles").each do |role|
        origin = source_artifacts.fetch(role)
        destination = artifacts.fetch(File.basename(origin.fetch("file")))
        raise Error, "Reused native artifact differs: #{role}" unless
          %w[bytes sha256].all? { |key| destination.fetch(key) == origin.fetch(key) }
      end
    end
    proof
  rescue ReleasePolicy::Error, KeyError => error
    raise Error, "Invalid native reuse proof: #{error.message}"
  end

  def verify_inputs!(proof, root:, commit:, definitions: groups)
    source_commit = proof.dig("sourceCandidate", "source", "commit")
    GitInputDigest.ancestor!(root, source_commit, commit)
    proof.fetch("platformInputs").each do |platform, digest|
      scopes = definitions.fetch(platform).fetch("inputs")
      raise Error, "Tracked #{platform} build inputs changed; rebuild that platform" unless
        GitInputDigest.digest(root, source_commit, scopes) == digest &&
          GitInputDigest.digest(root, commit, scopes) == digest
    end
  rescue GitInputDigest::Error, KeyError => error
    raise Error, "Cannot verify native reuse inputs: #{error.message}"
  end

  def load_candidate!(path, policy:)
    path = Pathname.new(path)
    raise Error, "Candidate path must be an absolute regular file" unless
      path.absolute? && path.file? && !path.symlink?
    candidate = JSON.parse(path.read)
    ReleasePolicy.validate_artifact_snapshot!(candidate, policy)
    raise Error, "Reuse requires a canonical, eligible candidate manifest" unless
      candidate.fetch("state") == "candidate" && candidate.fetch("acceptanceEligible") == true &&
        path.binread == canonical_json(candidate)
    root = path.realpath.parent
    candidate.fetch("artifacts").each do |entry|
      cursor = root
      Pathname.new(entry.fetch("file")).each_filename do |part|
        cursor = cursor.join(part)
        raise Error, "Candidate artifact uses a symbolic link: #{cursor}" if cursor.symlink?
      end
      raise Error, "Candidate artifact changed or is missing: #{cursor}" unless
        cursor.file? && cursor.size == entry.fetch("bytes") &&
          Digest::SHA256.file(cursor).hexdigest == entry.fetch("sha256")
    end
    [candidate, root]
  rescue ReleasePolicy::Error, JSON::ParserError, Errno::ENOENT => error
    raise Error, "Cannot read reuse candidate: #{error.message}"
  end
end
