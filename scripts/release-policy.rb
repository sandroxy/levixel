#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"
require "uri"

module ReleasePolicy
  class Error < StandardError; end

  ID_PATTERN = /\A[a-z][a-z0-9-]*\z/
  QUALIFICATION_PATTERN = /\A[a-z][A-Za-z0-9]*\z/
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  SEMVER_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/

  module_function

  def load(path)
    policy = JSON.parse(File.read(path))
    validate_policy!(policy)
    policy
  rescue JSON::ParserError, Errno::ENOENT => error
    raise Error, "Unable to load release policy: #{error.message}"
  end

  def validate_policy!(policy)
    expect_fields!(
      policy,
      %w[
        acceptance acceptanceReceiptSchemaVersion artifactRoles candidateSchemaVersion
        kind plugin qualifications schemaVersion sourceRepository verifierRepository
      ],
      "release policy"
    )
    raise Error, "Unexpected release policy schema" unless policy.fetch("schemaVersion") == 1
    raise Error, "Unexpected release policy kind" unless policy.fetch("kind") == "plugin-release-policy"
    plugin = policy.fetch("plugin")
    raise Error, "Invalid release policy plugin" unless plugin.is_a?(String) && plugin.match?(ID_PATTERN)
    %w[sourceRepository verifierRepository].each do |field|
      validate_https_repository!(policy.fetch(field), field)
    end
    %w[candidateSchemaVersion acceptanceReceiptSchemaVersion].each do |field|
      value = policy.fetch(field)
      raise Error, "Invalid #{field}" unless value.is_a?(Integer) && value.positive?
    end

    qualifications = policy.fetch("qualifications")
    validate_sorted_unique_array!(qualifications, QUALIFICATION_PATTERN, "release qualifications")
    raise Error, "Release policy must declare qualifications" if qualifications.empty?

    artifact_roles = policy.fetch("artifactRoles")
    expect_fields!(artifact_roles, %w[conditional required], "artifact role policy")
    required_roles = artifact_roles.fetch("required")
    validate_sorted_unique_array!(required_roles, ID_PATTERN, "required artifact roles")
    raise Error, "Release policy must declare artifact roles" if required_roles.empty?
    conditional = artifact_roles.fetch("conditional")
    raise Error, "Conditional artifact roles must be an object" unless conditional.is_a?(Hash)
    unknown_conditions = conditional.keys - qualifications
    raise Error, "Unknown artifact role conditions: #{unknown_conditions.join(", ")}" unless unknown_conditions.empty?
    conditional.each do |qualification, roles|
      validate_sorted_unique_array!(roles, ID_PATTERN, "artifact roles for #{qualification}")
      raise Error, "Conditional artifact roles cannot be empty: #{qualification}" if roles.empty?
    end
    all_roles = required_roles + conditional.values.flatten
    duplicates = duplicates_in(all_roles)
    raise Error, "Artifact roles overlap: #{duplicates.join(", ")}" unless duplicates.empty?

    acceptance = policy.fetch("acceptance")
    expect_fields!(acceptance, %w[automatedTargets manualTargets], "acceptance policy")
    automated = acceptance.fetch("automatedTargets")
    manual = acceptance.fetch("manualTargets")
    validate_sorted_unique_array!(automated, ID_PATTERN, "automated acceptance targets")
    validate_sorted_unique_array!(manual, ID_PATTERN, "manual acceptance targets")
    raise Error, "Release policy must declare acceptance targets" if automated.empty? && manual.empty?
    overlap = automated & manual
    raise Error, "Acceptance targets overlap: #{overlap.join(", ")}" unless overlap.empty?
    policy
  rescue KeyError => error
    raise Error, "Incomplete release policy: #{error.message}"
  end

  def validate_candidate!(candidate, policy)
    expect_fields!(
      candidate,
      %w[
        acceptance acceptanceEligible artifactSetSha256 artifacts candidateId kind plugin
        qualifications schemaVersion source state version
      ],
      "candidate manifest"
    )
    raise Error, "Unexpected candidate schema" unless
      candidate.fetch("schemaVersion") == policy.fetch("candidateSchemaVersion")
    raise Error, "Unexpected candidate kind" unless candidate.fetch("kind") == "plugin-release-candidate"
    raise Error, "Candidate plugin differs from release policy" unless
      candidate.fetch("plugin") == policy.fetch("plugin")
    version = candidate.fetch("version")
    raise Error, "Invalid candidate version" unless version.is_a?(String) && version.match?(SEMVER_PATTERN)

    state = candidate.fetch("state")
    raise Error, "Candidate state must be candidate or rehearsal" unless %w[candidate rehearsal].include?(state)
    acceptance_eligible = candidate.fetch("acceptanceEligible")
    raise Error, "Candidate acceptance flag differs from its state" unless
      acceptance_eligible == (state == "candidate")

    source = candidate.fetch("source")
    expect_fields!(source, %w[commit dirty repository], "candidate source")
    raise Error, "Candidate source repository differs from release policy" unless
      source.fetch("repository") == policy.fetch("sourceRepository")
    commit = source.fetch("commit")
    raise Error, "Invalid candidate source commit" unless
      commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
    dirty = source.fetch("dirty")
    raise Error, "Invalid candidate dirty flag" unless [true, false].include?(dirty)
    raise Error, "An acceptance candidate cannot come from a dirty source" if state == "candidate" && dirty

    raise Error, "Candidate acceptance matrix differs from release policy" unless
      candidate.fetch("acceptance") == policy.fetch("acceptance")
    qualifications = candidate.fetch("qualifications")
    raise Error, "Candidate qualifications must be an object" unless qualifications.is_a?(Hash)
    expected_qualifications = policy.fetch("qualifications")
    raise Error, "Candidate qualification fields differ from release policy" unless
      qualifications.keys.sort == expected_qualifications
    raise Error, "Candidate qualifications must be boolean" unless
      qualifications.values.all? { |value| [true, false].include?(value) }
    if state == "candidate" && qualifications.values.any? { |value| value != true }
      raise Error, "Acceptance candidate lacks a required qualification"
    end

    artifacts = candidate.fetch("artifacts")
    raise Error, "Candidate artifacts must be a non-empty array" unless artifacts.is_a?(Array) && !artifacts.empty?
    artifacts.each do |entry|
      expect_fields!(entry, %w[bytes file role sha256], "candidate artifact")
      role = entry.fetch("role")
      raise Error, "Invalid candidate artifact role" unless role.is_a?(String) && role.match?(ID_PATTERN)
      file = entry.fetch("file")
      raise Error, "Invalid candidate artifact path" unless file.is_a?(String) && !file.empty?
      path = Pathname.new(file)
      raise Error, "Unsafe candidate artifact path" if
        path.absolute? || path.cleanpath.to_s != file || path.each_filename.any? { |part| part == ".." }
      raise Error, "Invalid candidate artifact byte count" unless entry.fetch("bytes").is_a?(Integer) && entry.fetch("bytes") >= 0
      raise Error, "Invalid candidate artifact checksum" unless
        entry.fetch("sha256").is_a?(String) && entry.fetch("sha256").match?(SHA256_PATTERN)
    end
    roles = artifacts.map { |entry| entry.fetch("role") }
    raise Error, "Candidate artifact roles differ from release policy" unless
      roles.sort == expected_artifact_roles(policy, qualifications)
    raise Error, "Candidate contains duplicate artifact paths" unless
      artifacts.map { |entry| entry.fetch("file") }.uniq.length == artifacts.length
    set_payload = artifacts.sort_by { |entry| entry.fetch("role") }.map do |entry|
      %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
    end.join
    artifact_set_sha256 = Digest::SHA256.hexdigest(set_payload)
    raise Error, "Candidate artifact-set digest differs" unless
      candidate.fetch("artifactSetSha256") == artifact_set_sha256
    expected_id = [
      policy.fetch("plugin"), version, commit[0, 12], artifact_set_sha256[0, 12]
    ].join("-")
    raise Error, "Candidate id differs from its content" unless candidate.fetch("candidateId") == expected_id
    candidate
  rescue KeyError => error
    raise Error, "Incomplete candidate manifest: #{error.message}"
  end

  def expected_artifact_roles(policy, qualifications)
    roles = policy.dig("artifactRoles", "required").dup
    policy.dig("artifactRoles", "conditional").each do |qualification, conditional_roles|
      roles.concat(conditional_roles) if qualifications.fetch(qualification)
    end
    roles.sort
  end

  def expect_fields!(object, fields, label)
    raise Error, "#{label} must be an object" unless object.is_a?(Hash)
    actual = object.keys.sort
    expected = fields.sort
    raise Error, "#{label} fields differ: #{actual.inspect}" unless actual == expected
  end

  def validate_sorted_unique_array!(values, pattern, label)
    raise Error, "#{label} must be an array" unless values.is_a?(Array)
    raise Error, "#{label} contain an invalid value" unless
      values.all? { |value| value.is_a?(String) && value.match?(pattern) }
    raise Error, "#{label} must be sorted and unique" unless values == values.sort.uniq
  end

  def validate_https_repository!(value, label)
    uri = URI.parse(value)
    raise Error, "#{label} must be an HTTPS repository URL" unless
      uri.is_a?(URI::HTTPS) && uri.host && !uri.path.empty?
  rescue URI::InvalidURIError
    raise Error, "#{label} must be an HTTPS repository URL"
  end

  def duplicates_in(values)
    values.group_by(&:itself).select { |_value, entries| entries.length > 1 }.keys.sort
  end
end

if $PROGRAM_NAME == __FILE__
  abort("Usage: #{$PROGRAM_NAME} /absolute/path/to/release-policy.json") unless ARGV.length == 1
  path = File.expand_path(ARGV.fetch(0))
  policy = ReleasePolicy.load(path)
  puts "Verified #{policy.fetch("plugin")} release policy."
end
