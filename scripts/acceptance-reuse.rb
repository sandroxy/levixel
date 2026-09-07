require "digest"
require "json"
require "pathname"
require "time"
require "uri"
require_relative "git-input-digest"

# A reuse record is a new verification of old evidence, never a new device run.
# Product and verifier repositories independently own this protocol and policy.
module AcceptanceReuse
  class Error < StandardError; end

  module_function

  def fields!(value, expected, label)
    raise Error, "Unexpected #{label} fields" unless
      value.is_a?(Hash) && value.keys.sort == expected.sort
  end

  def json(value)
    JSON.pretty_generate(value) + "\n"
  end

  def checksum(value)
    Digest::SHA256.hexdigest(json(value))
  end

  def load_policy(path, plugin:, acceptance:, artifact_roles:)
    policy = JSON.parse(File.read(path))
    fields!(policy, %w[inputSets kind plugin schemaVersion targets], "manual reuse policy")
    raise Error, "Unexpected manual reuse policy" unless
      policy.fetch("schemaVersion") == 1 && policy.fetch("kind") == "manual-acceptance-reuse-policy" &&
        policy.fetch("plugin") == plugin
    input_sets = policy.fetch("inputSets")
    raise Error, "Manual reuse must declare named input sets" unless input_sets.is_a?(Hash) && !input_sets.empty?
    input_sets.each do |name, paths|
      raise Error, "Invalid manual input set: #{name}" unless name.match?(/\A[a-z][a-z0-9-]*\z/)
      raise Error, "Input set must be sorted, unique, and non-empty: #{name}" unless
        paths.is_a?(Array) && !paths.empty? && paths.all? { |path| path.is_a?(String) } && paths == paths.sort.uniq
      paths.each do |path|
        raise Error, "Unsafe verifier input scope: #{path.inspect}" unless
          path.match?(/\A[A-Za-z0-9_.\/-]+\z/) &&
            path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
      end
    end
    targets = policy.fetch("targets")
    raise Error, "Reuse policy must cover the declared manual targets exactly" unless
      targets.is_a?(Hash) && targets.keys.sort == acceptance.fetch("manualTargets").sort
    targets.each do |target, scope|
      fields!(scope, %w[artifactRoles inputSets], "reuse scope #{target}")
      %w[artifactRoles inputSets].each do |field|
        values = scope.fetch(field)
        raise Error, "Reuse #{field} must be sorted, unique, and non-empty: #{target}" unless
          values.is_a?(Array) && !values.empty? && values.all? { |value| value.is_a?(String) } &&
            values == values.sort.uniq
      end
      raise Error, "Reuse scope names unknown artifacts: #{target}" unless
        (scope.fetch("artifactRoles") - artifact_roles).empty?
      raise Error, "Reuse scope names unknown input sets: #{target}" unless
        (scope.fetch("inputSets") - input_sets.keys).empty?
    end
    used_sets = targets.values.flat_map { |scope| scope.fetch("inputSets") }.uniq.sort
    raise Error, "Manual reuse policy contains unused input sets" unless used_sets == input_sets.keys.sort
    targets.to_h do |target, scope|
      [target, {"artifactRoles" => scope.fetch("artifactRoles"),
                "inputPaths" => scope.fetch("inputSets").flat_map { |name| input_sets.fetch(name) }.uniq.sort}]
    end
  rescue JSON::ParserError, KeyError, Errno::ENOENT => error
    raise Error, "Cannot load manual reuse policy: #{error.message}"
  end

  def identity(candidate, digest, target)
    {
      "plugin" => candidate.fetch("plugin"),
      "version" => candidate.fetch("version"),
      "candidateId" => candidate.fetch("candidateId"),
      "artifactSetSha256" => candidate.fetch("artifactSetSha256"),
      "candidateManifestSha256" => digest,
      "target" => target,
    }
  end

  def same_identity!(run, candidate, digest, target)
    identity(candidate, digest, target).each do |key, value|
      raise Error, "Manual evidence #{key} differs" unless run.fetch(key) == value
    end
  end

  def validate_verifier!(verifier, repository)
    fields!(verifier, %w[commit dirty repository], "manual verifier")
    raise Error, "Manual evidence requires a clean, identified verifier" unless
      verifier.fetch("repository") == repository && verifier.fetch("dirty") == false &&
        verifier.fetch("commit").is_a?(String) && verifier.fetch("commit").match?(/\A[0-9a-f]{40}\z/)
  end

  def source_run!(run, candidate:, digest:, target:, repository:)
    fields!(run, %w[
      artifactSetSha256 candidateId candidateManifestSha256 environment kind notes plugin
      recordedAt scenarios schemaVersion status target verifier version
    ], "original manual run")
    raise Error, "Reuse requires an original passed manual run, not another reuse record" unless
      run.fetch("schemaVersion") == 1 && run.fetch("kind") == "plugin-candidate-manual-run" &&
        run.fetch("status") == "passed"
    same_identity!(run, candidate, digest, target)
    fields!(run.fetch("environment"), %w[deviceModel operatingSystem runtime], "original test environment")
    raise Error, "Original manual environment is incomplete" unless
      run.fetch("environment").values.all? { |value| value.is_a?(String) && !value.strip.empty? }
    raise Error, "Original manual run lacks complete scenario coverage" unless
      run.fetch("scenarios") == candidate.dig("acceptance", "manualScenarios")
    raise Error, "Invalid original manual notes" unless run.fetch("notes").is_a?(String)
    validate_verifier!(run.fetch("verifier"), repository)
    Time.iso8601(run.fetch("recordedAt"))
  end

  def repository!(root, expected)
    raise Error, "Reuse verification requires an explicit verifier repository checkout" unless root
    path = Pathname.new(root)
    raise Error, "Verifier repository path must be absolute" unless path.absolute? && path.directory?
    url = URI.parse(expected)
    origin = GitInputDigest.git(path, "remote", "get-url", "origin").strip
    allowed = [expected, "git@#{url.host}:#{url.path.delete_prefix('/')}"]
    raise Error, "Verifier checkout has an unexpected origin" unless allowed.include?(origin)
    top = GitInputDigest.git(path, "rev-parse", "--show-toplevel").strip
    raise Error, "Verifier path must name the repository root" unless Pathname.new(top).realpath == path.realpath
    path.realpath
  end

  def validate!(record, candidate:, candidate_digest:, target:, verifier:, scopes:,
                validate_candidate:, verifier_root:, latest: Time.now.utc)
    fields!(record, %w[
      artifactSetSha256 candidateId candidateManifestSha256 inputDigest kind plugin recordedAt
      schemaVersion source status target verifier version
    ], "manual reuse record")
    raise Error, "Unexpected manual reuse record" unless
      record.fetch("schemaVersion") == 1 && record.fetch("kind") == "plugin-candidate-manual-reuse" &&
        record.fetch("status") == "passed"
    same_identity!(record, candidate, candidate_digest, target)
    raise Error, "Reuse verifier differs from the receipt" unless record.fetch("verifier") == verifier
    validate_verifier!(verifier, verifier.fetch("repository"))
    source = record.fetch("source")
    fields!(source, %w[candidate candidateManifestSha256 evidence evidenceSha256], "manual reuse source")
    origin = source.fetch("candidate")
    validate_candidate.call(origin)
    raise Error, "Reuse requires eligible candidates of the same plugin, version, and acceptance contract" unless
      origin.fetch("state") == "candidate" && origin.fetch("acceptanceEligible") == true &&
        candidate.fetch("state") == "candidate" && candidate.fetch("acceptanceEligible") == true &&
        %w[plugin version acceptance].all? { |key| origin.fetch(key) == candidate.fetch(key) }
    raise Error, "Original candidate digest differs" unless checksum(origin) == source.fetch("candidateManifestSha256")
    run = source.fetch("evidence")
    raise Error, "Original manual evidence digest differs" unless checksum(run) == source.fetch("evidenceSha256")
    source_time = source_run!(run, candidate: origin, digest: source.fetch("candidateManifestSha256"),
                             target: target, repository: verifier.fetch("repository"))
    recorded_at = Time.iso8601(record.fetch("recordedAt"))
    raise Error, "Manual reuse chronology is invalid" unless source_time <= recorded_at && recorded_at <= latest
    scope = scopes.fetch(target)
    origin_artifacts = origin.fetch("artifacts").to_h { |entry| [entry.fetch("role"), entry] }
    current_artifacts = candidate.fetch("artifacts").to_h { |entry| [entry.fetch("role"), entry] }
    scope.fetch("artifactRoles").each do |role|
      before = origin_artifacts.fetch(role)
      after = current_artifacts.fetch(role)
      raise Error, "Consumed artifact changed; repeat manual acceptance: #{role}" unless
        %w[bytes sha256].all? { |key| before.fetch(key) == after.fetch(key) }
    end
    input_digest = record.fetch("inputDigest")
    raise Error, "Invalid manual reuse input digest" unless
      input_digest.is_a?(String) && input_digest.match?(/\A[0-9a-f]{64}\z/)
    root = repository!(verifier_root, verifier.fetch("repository"))
    source_commit = run.dig("verifier", "commit")
    current_commit = verifier.fetch("commit")
    GitInputDigest.ancestor!(root, source_commit, current_commit)
    [source_commit, current_commit].each do |commit|
      raise Error, "Verifier inputs changed; repeat manual acceptance for #{target}" unless
        GitInputDigest.digest(root, commit, scope.fetch("inputPaths")) == input_digest
    end
    record
  rescue KeyError, ArgumentError, TypeError, GitInputDigest::Error => error
    raise Error, "Invalid manual reuse evidence: #{error.message}"
  end

  def build(candidate:, source_candidate:, source_run:, target:, verifier:, scopes:,
            validate_candidate:, verifier_root:, now: Time.now.utc)
    record = {
      "schemaVersion" => 1,
      "kind" => "plugin-candidate-manual-reuse",
      "status" => "passed",
    }.merge(identity(candidate, checksum(candidate), target)).merge(
      "inputDigest" => GitInputDigest.digest(verifier_root, verifier.fetch("commit"), scopes.fetch(target).fetch("inputPaths")),
      "source" => {
        "candidate" => source_candidate,
        "candidateManifestSha256" => checksum(source_candidate),
        "evidence" => source_run,
        "evidenceSha256" => checksum(source_run),
      },
      "verifier" => verifier,
      "recordedAt" => now.iso8601(6)
    )
    validate!(record, candidate: candidate, candidate_digest: checksum(candidate), target: target,
              verifier: verifier, scopes: scopes, validate_candidate: validate_candidate,
              verifier_root: verifier_root, latest: now)
  end
end
