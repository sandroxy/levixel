#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "tmpdir"

options = {
  artifacts: [],
  qualifications: {},
}

OptionParser.new do |parser|
  parser.banner = "Usage: snapshot-release-candidate.rb [options]"
  parser.on("--plugin ID") { |value| options[:plugin] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--repository URL") { |value| options[:repository] = value }
  parser.on("--commit SHA") { |value| options[:commit] = value }
  parser.on("--dirty BOOLEAN") { |value| options[:dirty] = value }
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--output-root PATH") { |value| options[:output_root] = value }
  parser.on("--state STATE") { |value| options[:state] = value }
  parser.on("--artifact ROLE=PATH") { |value| options[:artifacts] << value }
  parser.on("--qualification KEY=VALUE") do |value|
    key, raw = value.split("=", 2)
    abort("Invalid qualification: #{value}") unless key&.match?(/\A[a-z][A-Za-z0-9]*\z/) && raw
    parsed = case raw
             when "true" then true
             when "false" then false
             else raw
             end
    options[:qualifications][key] = parsed
  end
end.parse!

abort("Unexpected arguments: #{ARGV.join(" ")}") unless ARGV.empty?

required = %i[plugin version repository commit dirty root output_root state]
missing = required.reject { |key| options[key] && !options[key].empty? }
abort("Missing required options: #{missing.join(", ")}") unless missing.empty?
abort("At least one --artifact is required") if options[:artifacts].empty?

plugin = options.fetch(:plugin)
version = options.fetch(:version)
repository = options.fetch(:repository)
commit = options.fetch(:commit)
dirty = case options.fetch(:dirty)
        when "true" then true
        when "false" then false
        else abort("Dirty must be true or false")
        end
state = options.fetch(:state)
abort("Invalid plugin id: #{plugin}") unless plugin.match?(/\A[a-z][a-z0-9-]*\z/)
abort("Candidate versions must be stable SemVer: #{version}") unless
  version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)
abort("Invalid source commit: #{commit}") unless commit.match?(/\A[0-9a-f]{40}\z/)
abort("State must be candidate or rehearsal") unless %w[candidate rehearsal].include?(state)
abort("A dirty source cannot produce an acceptance candidate") if state == "candidate" && dirty

root = Pathname.new(options.fetch(:root)).realpath
dist_root = root.join("dist")
output_root = Pathname.new(options.fetch(:output_root)).expand_path
FileUtils.mkdir_p(output_root)

role_sources = options.fetch(:artifacts).map do |argument|
  role, raw_path = argument.split("=", 2)
  abort("Invalid artifact argument: #{argument}") unless
    role&.match?(/\A[a-z][a-z0-9-]*\z/) && raw_path
  source = Pathname.new(raw_path).expand_path
  abort("Artifact is not a regular file: #{source}") unless source.file?
  source = source.realpath
  begin
    relative = source.relative_path_from(dist_root)
  rescue ArgumentError
    abort("Artifact must be below #{dist_root}: #{source}")
  end
  abort("Artifact escapes #{dist_root}: #{source}") if relative.each_filename.any? { |part| part == ".." }
  [role, source, Pathname.new("artifacts").join(relative)]
end

duplicates = role_sources.map(&:first).group_by(&:itself).select { |_role, values| values.length > 1 }.keys
abort("Duplicate artifact roles: #{duplicates.join(", ")}") unless duplicates.empty?
duplicate_paths = role_sources.map(&:last).group_by(&:itself).select { |_path, values| values.length > 1 }.keys
abort("Duplicate artifact paths: #{duplicate_paths.join(", ")}") unless duplicate_paths.empty?

entries = role_sources.map do |role, source, destination|
  {
    "role" => role,
    "file" => destination.to_s,
    "bytes" => source.size,
    "sha256" => Digest::SHA256.file(source).hexdigest,
  }
end.sort_by { |entry| entry.fetch("role") }

set_payload = entries.map do |entry|
  %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
end.join
artifact_set_sha256 = Digest::SHA256.hexdigest(set_payload)
candidate_id = [plugin, version, commit[0, 12], artifact_set_sha256[0, 12]].join("-")
candidate_dir = output_root.join(version, candidate_id)

manifest = {
  "schemaVersion" => 2,
  "kind" => "plugin-release-candidate",
  "state" => state,
  "acceptanceEligible" => state == "candidate",
  "plugin" => plugin,
  "version" => version,
  "candidateId" => candidate_id,
  "artifactSetSha256" => artifact_set_sha256,
  "source" => {
    "repository" => repository,
    "commit" => commit,
    "dirty" => dirty,
  },
  "qualifications" => options.fetch(:qualifications).sort.to_h,
  "artifacts" => entries,
}
manifest_json = JSON.pretty_generate(manifest) + "\n"

verify_existing = lambda do
  manifest_path = candidate_dir.join("candidate.json")
  abort("Existing candidate has no manifest: #{candidate_dir}") unless manifest_path.file?
  abort("Existing candidate manifest differs: #{manifest_path}") unless manifest_path.read == manifest_json
  entries.each do |entry|
    path = candidate_dir.join(entry.fetch("file"))
    abort("Existing candidate artifact is missing: #{path}") unless path.file?
    abort("Existing candidate artifact size differs: #{path}") unless path.size == entry.fetch("bytes")
    abort("Existing candidate artifact checksum differs: #{path}") unless
      Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
  end
end

if candidate_dir.exist?
  verify_existing.call
else
  FileUtils.mkdir_p(candidate_dir.parent)
  temporary_root = Pathname.new(Dir.mktmpdir(".#{candidate_id}-", candidate_dir.parent.to_s))
  begin
    role_sources.each do |_role, source, destination|
      output = temporary_root.join(destination)
      FileUtils.mkdir_p(output.parent)
      FileUtils.copy_file(source, output)
    end
    temporary_root.join("candidate.json").write(manifest_json)
    FileUtils.mv(temporary_root, candidate_dir)
  ensure
    FileUtils.remove_entry(temporary_root) if temporary_root.exist?
  end
  verify_existing.call
end

puts candidate_dir.join("candidate.json")
puts "candidateId=#{candidate_id}"
puts "artifactSetSha256=#{artifact_set_sha256}"
