#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tempfile"
require_relative "release-policy"

options = {
  automated_targets: [],
  artifacts: [],
  manual_targets: [],
  qualifications: {},
}

OptionParser.new do |parser|
  parser.banner = "Usage: snapshot-release-candidate.rb [options]"
  parser.on("--plugin ID") { |value| options[:plugin] = value }
  parser.on("--policy FILE") { |value| options[:policy] = value }
  parser.on("--version VERSION") { |value| options[:version] = value }
  parser.on("--repository URL") { |value| options[:repository] = value }
  parser.on("--commit SHA") { |value| options[:commit] = value }
  parser.on("--dirty BOOLEAN") { |value| options[:dirty] = value }
  parser.on("--root PATH") { |value| options[:root] = value }
  parser.on("--state STATE") { |value| options[:state] = value }
  parser.on("--automated-target TARGET") { |value| options[:automated_targets] << value }
  parser.on("--manual-target TARGET") { |value| options[:manual_targets] << value }
  parser.on("--artifact ROLE=PATH") { |value| options[:artifacts] << value }
  parser.on("--qualification KEY=VALUE") do |value|
    key, raw = value.split("=", 2)
    abort("Invalid qualification: #{value}") unless key&.match?(/\A[a-z][A-Za-z0-9]*\z/) && raw
    abort("Duplicate qualification: #{key}") if options[:qualifications].key?(key)
    parsed = case raw
             when "true" then true
             when "false" then false
             else abort("Qualification must be true or false: #{value}")
             end
    options[:qualifications][key] = parsed
  end
end.parse!

abort("Unexpected arguments: #{ARGV.join(" ")}") unless ARGV.empty?

required = %i[plugin policy version repository commit dirty root state]
missing = required.reject { |key| options[key] && !options[key].empty? }
abort("Missing required options: #{missing.join(", ")}") unless missing.empty?
abort("At least one --artifact is required") if options[:artifacts].empty?
abort("At least one acceptance target is required") if
  options[:automated_targets].empty? && options[:manual_targets].empty?

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
policy_argument = Pathname.new(options.fetch(:policy))
abort("Release policy path must be absolute") unless policy_argument.absolute?
policy_path = policy_argument.realpath
expected_policy_path = root.join("release-policy.json").realpath
abort("Release policy must be #{expected_policy_path}") unless policy_path == expected_policy_path
begin
  policy = ReleasePolicy.load(policy_path)
rescue ReleasePolicy::Error => error
  abort(error.message)
end
abort("Candidate plugin differs from release policy") unless plugin == policy.fetch("plugin")
abort("Candidate repository differs from release policy") unless repository == policy.fetch("sourceRepository")
abort("Candidate qualification fields differ from release policy") unless
  options.fetch(:qualifications).keys.sort == policy.fetch("qualifications")

target_pattern = /\A[a-z][a-z0-9-]*\z/
acceptance_targets = options.fetch(:automated_targets) + options.fetch(:manual_targets)
invalid_targets = acceptance_targets.reject { |target| target.match?(target_pattern) }
abort("Invalid acceptance targets: #{invalid_targets.join(", ")}") unless invalid_targets.empty?
duplicate_targets = acceptance_targets.group_by(&:itself).select { |_target, values| values.length > 1 }.keys
abort("Duplicate acceptance targets: #{duplicate_targets.join(", ")}") unless duplicate_targets.empty?
provided_acceptance = {
  "automatedTargets" => options.fetch(:automated_targets).sort,
  "manualTargets" => options.fetch(:manual_targets).sort,
}
abort("Candidate acceptance matrix differs from release policy") unless
  provided_acceptance == policy.fetch("acceptance")

dist_root = root.join("dist")
abort("Release output directory must not be a symbolic link") if dist_root.symlink?
FileUtils.mkdir_p(dist_root)
manifest_path = dist_root.join("candidate.json")
abort("Candidate manifest must be a regular file") if
  manifest_path.symlink? || (manifest_path.exist? && !manifest_path.file?)

role_sources = options.fetch(:artifacts).map do |argument|
  role, raw_path = argument.split("=", 2)
  abort("Invalid artifact argument: #{argument}") unless
    role&.match?(/\A[a-z][a-z0-9-]*\z/) && raw_path
  source = Pathname.new(raw_path).expand_path
  abort("Artifact is not a regular file: #{source}") unless source.file?
  begin
    relative = source.realpath.relative_path_from(dist_root)
  rescue ArgumentError
    abort("Artifact must be below #{dist_root}: #{source}")
  end
  abort("Artifact escapes #{dist_root}: #{source}") if relative.each_filename.any? { |part| part == ".." }
  cursor = source
  loop do
    abort("Artifact uses a symbolic link: #{cursor}") if cursor.symlink?
    break if cursor.realpath == dist_root
    cursor = cursor.parent
  end
  source = source.realpath
  abort("Candidate manifest cannot be an artifact") if source == manifest_path
  [role, source, relative]
end

duplicates = role_sources.map(&:first).group_by(&:itself).select { |_role, values| values.length > 1 }.keys
abort("Duplicate artifact roles: #{duplicates.join(", ")}") unless duplicates.empty?
duplicate_paths = role_sources.map(&:last).group_by(&:itself).select { |_path, values| values.length > 1 }.keys
abort("Duplicate artifact paths: #{duplicate_paths.join(", ")}") unless duplicate_paths.empty?
expected_roles = ReleasePolicy.expected_artifact_roles(policy, options.fetch(:qualifications))
actual_roles = role_sources.map(&:first).sort
abort("Candidate artifact roles differ from release policy") unless actual_roles == expected_roles

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

manifest = {
  "schemaVersion" => policy.fetch("candidateSchemaVersion"),
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
  "acceptance" => {
    "automatedTargets" => options.fetch(:automated_targets).sort,
    "manualTargets" => options.fetch(:manual_targets).sort,
  },
  "qualifications" => options.fetch(:qualifications).sort.to_h,
  "artifacts" => entries,
}
begin
  ReleasePolicy.validate_candidate!(manifest, policy)
rescue ReleasePolicy::Error => error
  abort(error.message)
end
manifest_json = JSON.pretty_generate(manifest) + "\n"

# Retention protects the latest release tag and the files explicitly selected
# above. A tag is a local retention boundary, not proof of registry publication.
tags, error, status = Open3.capture3("git", "-C", root.to_s, "tag", "--list")
abort("Unable to resolve release retention: #{error.strip}") unless status.success?
version_pattern = /(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)/
latest_tag = tags.lines.map(&:strip).select { |tag| tag.match?(/\A#{version_pattern}\z/) }
  .max_by { |tag| tag.split(".").map(&:to_i) }
retained_versions = [version, latest_tag].compact
selected_paths = role_sources.map { |_role, source, _relative| source }
obsolete = role_sources.flat_map do |_role, source, _relative|
  name = source.basename.to_s
  match = name.match(version_pattern)
  next [] unless match
  pattern = /\A#{Regexp.escape(match.pre_match)}(#{version_pattern})#{Regexp.escape(match.post_match)}\z/
  source.parent.children.select do |path|
    found = path.basename.to_s.match(pattern)
    found && !retained_versions.include?(found[1]) && !selected_paths.include?(path) &&
      path.file? && !path.symlink?
  end
end.uniq

entries.each do |entry|
  path = dist_root.join(entry.fetch("file"))
  abort("Artifact changed while recording the candidate: #{path}") unless
    path.file? && path.size == entry.fetch("bytes") &&
      Digest::SHA256.file(path).hexdigest == entry.fetch("sha256")
end

unless manifest_path.file? && manifest_path.read == manifest_json
  Tempfile.create([".candidate-", ".json"], dist_root.to_s) do |temporary|
    temporary.write(manifest_json)
    temporary.flush
    File.chmod(0o644, temporary.path)
    File.rename(temporary.path, manifest_path)
  end
end
obsolete.each(&:unlink)
warn "Removed #{obsolete.length} superseded release output files; retained #{retained_versions.join(', ')}." unless obsolete.empty?

puts manifest_path
puts "candidateId=#{candidate_id}"
puts "artifactSetSha256=#{artifact_set_sha256}"
