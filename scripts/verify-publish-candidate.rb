#!/usr/bin/env ruby

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

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
product_manifest = if root.join("plugin.json").file?
                     JSON.parse(root.join("plugin.json").read)
                   else
                     YAML.load_file(root.join("plugin.yaml"))
                   end
plugin = product_manifest.fetch("id")
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
abort("Unexpected candidate schema") unless candidate.fetch("schemaVersion") == 2
abort("Unexpected candidate kind") unless candidate.fetch("kind") == "plugin-release-candidate"
abort("Candidate is not acceptance eligible") unless
  candidate.fetch("state") == "candidate" && candidate.fetch("acceptanceEligible") == true
abort("Candidate plugin differs from the product manifest") unless candidate.fetch("plugin") == plugin
abort("Candidate version differs from the product manifest") unless candidate.fetch("version") == version
source = candidate.fetch("source")
abort("Candidate source is dirty") unless source.fetch("dirty") == false
commit = source.fetch("commit")
abort("Invalid candidate source commit") unless commit.match?(/\A[0-9a-f]{40}\z/)
qualifications = candidate.fetch("qualifications")
required_qualifications = {
  "levixel" => %w[androidMavenSigned nativeManifestVerified packageIdentitiesVerified versionUnpublished],
  "sfiora" => %w[androidMavenSigned nativeManifestVerified adapterProvenanceVerified versionUnpublished],
}.fetch(plugin, %w[versionUnpublished])
missing_qualifications = required_qualifications.reject { |name| qualifications[name] == true }
abort("Candidate lacks required qualifications: #{missing_qualifications.join(", ")}") unless
  missing_qualifications.empty?

entries = candidate.fetch("artifacts")
abort("Candidate artifacts must be a non-empty array") unless entries.is_a?(Array) && !entries.empty?
roles = entries.map { |entry| entry.fetch("role") }
abort("Candidate contains duplicate artifact roles") unless roles.uniq.length == roles.length
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

acceptance = JSON.parse(acceptance_argument.read)
abort("Unexpected acceptance receipt schema") unless acceptance.fetch("schemaVersion") == 1
abort("Unexpected acceptance receipt kind") unless acceptance.fetch("kind") == "plugin-candidate-acceptance"
abort("Candidate has not been accepted") unless acceptance.fetch("status") == "accepted"
{
  "plugin" => plugin,
  "version" => version,
  "candidateId" => expected_candidate_id,
  "artifactSetSha256" => artifact_set_sha256,
  "candidateSource" => source,
}.each do |key, expected|
  abort("Acceptance receipt #{key} differs from the candidate") unless acceptance.fetch(key) == expected
end
checks = acceptance.fetch("checks")
abort("Automated consumer acceptance did not pass") unless checks.fetch("automatedConsumers") == "passed"
abort("Manual device acceptance did not pass") unless checks.fetch("manualDeviceMatrix") == "passed"
verifier = acceptance.fetch("verifier")
abort("Acceptance was recorded from a dirty verifier worktree") unless verifier.fetch("dirty") == false
abort("Acceptance verifier commit is invalid") unless verifier.fetch("commit").match?(/\A[0-9a-f]{40}\z/)

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
