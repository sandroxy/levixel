#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "time"
require "yaml"
require_relative "release-policy"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: verify-publish-candidate.rb --candidate FILE --acceptance FILE"
  parser.on("--candidate FILE") { |value| options[:candidate] = value }
  parser.on("--acceptance FILE") { |value| options[:acceptance] = value }
end.parse!

required = %i[candidate acceptance]
missing = required.reject { |key| options[key] && !options[key].empty? }
abort("Missing required options: #{missing.join(", ")}") unless missing.empty?
abort("Unexpected arguments: #{ARGV.join(" ")}") unless ARGV.empty?

root = Pathname.new(__dir__).parent.realpath
begin
  release_policy = ReleasePolicy.load(root.join("release-policy.json"))
rescue ReleasePolicy::Error => error
  abort(error.message)
end
product_manifest = if root.join("plugin.json").file?
                     JSON.parse(root.join("plugin.json").read)
                   else
                     YAML.load_file(root.join("plugin.yaml"))
                   end
plugin = release_policy.fetch("plugin")
abort("Product manifest plugin differs from release policy") unless product_manifest.fetch("id") == plugin
version = product_manifest.fetch("version").to_s

candidate_argument = Pathname.new(options.fetch(:candidate))
acceptance_argument = Pathname.new(options.fetch(:acceptance))
abort("Candidate manifest path must be absolute") unless candidate_argument.absolute?
abort("Acceptance receipt path must be absolute") unless acceptance_argument.absolute?
abort("Candidate manifest is missing: #{candidate_argument}") unless candidate_argument.file?
abort("Acceptance receipt is missing: #{acceptance_argument}") unless acceptance_argument.file?

candidate_path = candidate_argument.realpath
candidate_root = candidate_path.parent.realpath
candidate = JSON.parse(candidate_path.read)
begin
  ReleasePolicy.validate_candidate!(candidate, release_policy)
rescue ReleasePolicy::Error => error
  abort(error.message)
end
abort("Candidate is not acceptance eligible") unless candidate.fetch("state") == "candidate"
abort("Candidate version differs from the product manifest") unless candidate.fetch("version") == version
source = candidate.fetch("source")
commit = source.fetch("commit")
acceptance_requirements = candidate.fetch("acceptance")

entries = candidate.fetch("artifacts")
entries.each do |entry|
  relative = Pathname.new(entry.fetch("file"))
  abort("Unsafe candidate artifact path: #{relative}") if
    relative.absolute? || relative.cleanpath != relative || relative.each_filename.any? { |part| part == ".." }
  path = candidate_root.join(relative)
  abort("Candidate artifact is missing: #{path}") unless path.file?
  cursor = candidate_root
  relative.each_filename do |part|
    cursor = cursor.join(part)
    abort("Candidate artifacts must not use symbolic links: #{cursor}") if cursor.symlink?
  end
  abort("Candidate artifact has an invalid byte count") unless entry.fetch("bytes").is_a?(Integer)
  abort("Candidate artifact byte count differs: #{path}") unless path.size == entry.fetch("bytes")
  sha256 = entry.fetch("sha256")
  abort("Candidate artifact has an invalid checksum") unless sha256.match?(/\A[0-9a-f]{64}\z/)
  abort("Candidate artifact checksum differs: #{path}") unless Digest::SHA256.file(path).hexdigest == sha256
end

set_payload = entries.sort_by { |entry| entry.fetch("role") }.map do |entry|
  %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
end.join
artifact_set_sha256 = Digest::SHA256.hexdigest(set_payload)
abort("Candidate artifact-set digest differs") unless candidate.fetch("artifactSetSha256") == artifact_set_sha256
expected_candidate_id = [plugin, version, commit[0, 12], artifact_set_sha256[0, 12]].join("-")
abort("Candidate id differs from its content") unless candidate.fetch("candidateId") == expected_candidate_id
candidate_manifest_sha256 = Digest::SHA256.file(candidate_path).hexdigest

acceptance = JSON.parse(acceptance_argument.read)
abort("Unexpected acceptance receipt schema") unless
  acceptance.fetch("schemaVersion") == release_policy.fetch("acceptanceReceiptSchemaVersion")
abort("Unexpected acceptance receipt kind") unless acceptance.fetch("kind") == "plugin-candidate-acceptance"
abort("Candidate has not been accepted") unless acceptance.fetch("status") == "accepted"
expected_acceptance_fields = %w[
  acceptanceRequirements artifactSetSha256 candidateId candidateManifestSha256
  candidateSource checks kind plugin recordedAt schemaVersion status verifier version
]
abort("Acceptance receipt has unexpected fields") unless acceptance.keys.sort == expected_acceptance_fields.sort
{
  "plugin" => plugin,
  "version" => version,
  "candidateId" => expected_candidate_id,
  "artifactSetSha256" => artifact_set_sha256,
  "candidateManifestSha256" => candidate_manifest_sha256,
  "candidateSource" => source,
  "acceptanceRequirements" => acceptance_requirements,
}.each do |key, expected|
  abort("Acceptance receipt #{key} differs from the candidate") unless acceptance.fetch(key) == expected
end
checks = acceptance.fetch("checks")
abort("Acceptance checks have unexpected fields") unless
  checks.is_a?(Hash) && checks.keys.sort == %w[automatedConsumers manualDeviceMatrix]
automated_checks = checks.fetch("automatedConsumers")
manual_checks = checks.fetch("manualDeviceMatrix")
abort("Automated acceptance targets differ from the candidate") unless
  automated_checks.keys.sort == acceptance_requirements.fetch("automatedTargets").sort
abort("Manual acceptance targets differ from the candidate") unless
  manual_checks.keys.sort == acceptance_requirements.fetch("manualTargets").sort
abort("Automated consumer acceptance did not pass") unless
  automated_checks.values.all? do |entry|
    entry.is_a?(Hash) && entry.keys.sort == %w[evidence status] && entry.fetch("status") == "passed"
  end
abort("Manual device acceptance did not pass") unless
  manual_checks.values.all? do |entry|
    entry.is_a?(Hash) && entry.keys == ["status"] && entry.fetch("status") == "passed"
  end
verifier = acceptance.fetch("verifier")
abort("Acceptance verifier has unexpected fields") unless
  verifier.is_a?(Hash) && verifier.keys.sort == %w[commit dirty repository]
abort("Acceptance verifier repository is invalid") unless
  verifier.fetch("repository") == release_policy.fetch("verifierRepository")
abort("Acceptance was recorded from a dirty verifier worktree") unless verifier.fetch("dirty") == false
abort("Acceptance verifier commit is invalid") unless verifier.fetch("commit").match?(/\A[0-9a-f]{40}\z/)
Time.iso8601(acceptance.fetch("recordedAt"))
automated_checks.each do |target, entry|
  evidence = entry.fetch("evidence")
  expected_evidence_fields = %w[
    artifactSetSha256 candidateId candidateManifestSha256 command completedAt exitCode
    kind plugin runSha256 schemaVersion startedAt status target verifier version
  ]
  abort("Automated evidence has unexpected fields: #{target}") unless
    evidence.is_a?(Hash) && evidence.keys.sort == expected_evidence_fields.sort
  abort("Automated evidence schema differs: #{target}") unless
    evidence.fetch("schemaVersion") == 1 &&
      evidence.fetch("kind") == "plugin-candidate-automated-run" &&
      evidence.fetch("status") == "passed" && evidence.fetch("exitCode") == 0
  abort("Automated evidence target differs: #{target}") unless evidence.fetch("target") == target
  abort("Automated evidence candidate differs: #{target}") unless
    evidence.fetch("plugin") == plugin && evidence.fetch("version") == version &&
      evidence.fetch("candidateId") == expected_candidate_id &&
      evidence.fetch("artifactSetSha256") == artifact_set_sha256 &&
      evidence.fetch("candidateManifestSha256") == candidate_manifest_sha256 &&
      evidence.fetch("command") == [
        "verification/#{plugin}/verify.sh", "--candidate", expected_candidate_id, target
      ]
  run_sha256 = evidence.fetch("runSha256")
  abort("Automated evidence digest is invalid: #{target}") unless run_sha256.match?(/\A[0-9a-f]{64}\z/)
  original_run = evidence.reject { |key, _value| key == "runSha256" }
  abort("Automated evidence digest differs: #{target}") unless
    Digest::SHA256.hexdigest(JSON.pretty_generate(original_run) + "\n") == run_sha256
  evidence_verifier = evidence.fetch("verifier")
  abort("Automated evidence verifier fields differ: #{target}") unless
    evidence_verifier.is_a?(Hash) &&
      evidence_verifier.keys.sort == %w[commit dirtyAfter dirtyBefore headAfter repository]
  abort("Automated evidence verifier differs: #{target}") unless
    evidence_verifier.fetch("repository") == verifier.fetch("repository") &&
      evidence_verifier.fetch("commit") == verifier.fetch("commit") &&
      evidence_verifier.fetch("headAfter") == verifier.fetch("commit") &&
      evidence_verifier.fetch("dirtyBefore") == false &&
      evidence_verifier.fetch("dirtyAfter") == false
  started_at = Time.iso8601(evidence.fetch("startedAt"))
  completed_at = Time.iso8601(evidence.fetch("completedAt"))
  abort("Automated evidence time range differs: #{target}") if completed_at < started_at
end

head, status = Open3.capture2("git", "-C", root.to_s, "rev-parse", "HEAD")
abort("Unable to resolve current source commit") unless status.success?
head = head.strip
abort("Current source commit differs from the accepted candidate") unless head == commit
status_output, status = Open3.capture2("git", "-C", root.to_s, "status", "--porcelain")
abort("Unable to inspect source worktree") unless status.success?
abort("Publication requires a clean source worktree") unless status_output.empty?

tag_type, status = Open3.capture2("git", "-C", root.to_s, "cat-file", "-t", "refs/tags/#{version}")
abort("Canonical annotated tag #{version} is missing") unless status.success? && tag_type.strip == "tag"
tag_commit, status = Open3.capture2("git", "-C", root.to_s, "rev-list", "-n", "1", "refs/tags/#{version}")
abort("Unable to resolve canonical tag #{version}") unless status.success?
abort("Canonical tag #{version} does not point to the accepted source commit") unless tag_commit.strip == commit

puts "Verified accepted #{plugin} #{version} candidate #{expected_candidate_id}."
entries.sort_by { |entry| entry.fetch("role") }.each do |entry|
  puts "#{entry.fetch("role")}=#{candidate_root.join(entry.fetch("file"))}"
end
