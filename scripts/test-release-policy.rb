#!/usr/bin/env ruby

require "digest"
require "json"
require_relative "release-policy"

root = File.expand_path("..", __dir__)
policy = ReleasePolicy.load(File.join(root, "release-policy.json"))
qualifications = policy.fetch("qualifications").to_h { |name| [name, true] }
artifacts = ReleasePolicy.expected_artifact_roles(policy, qualifications).map do |role|
  {
    "role" => role,
    "file" => "artifacts/#{role}",
    "bytes" => 1,
    "sha256" => "a" * 64,
  }
end
set_payload = artifacts.sort_by { |entry| entry.fetch("role") }.map do |entry|
  %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
end.join
artifact_set_sha256 = Digest::SHA256.hexdigest(set_payload)
commit = "c" * 40
candidate = {
  "schemaVersion" => policy.fetch("candidateSchemaVersion"),
  "kind" => "plugin-release-candidate",
  "state" => "candidate",
  "acceptanceEligible" => true,
  "plugin" => policy.fetch("plugin"),
  "version" => "1.0.0",
  "candidateId" => "#{policy.fetch("plugin")}-1.0.0-#{commit[0, 12]}-#{artifact_set_sha256[0, 12]}",
  "artifactSetSha256" => artifact_set_sha256,
  "source" => {
    "repository" => policy.fetch("sourceRepository"),
    "commit" => commit,
    "dirty" => false,
  },
  "acceptance" => policy.fetch("acceptance"),
  "qualifications" => qualifications,
  "artifacts" => artifacts,
}

ReleasePolicy.validate_candidate!(candidate, policy)

rehearsal = JSON.parse(JSON.generate(candidate))
rehearsal["state"] = "rehearsal"
rehearsal["acceptanceEligible"] = false
rehearsal.fetch("source")["dirty"] = true
rehearsal["qualifications"] = policy.fetch("qualifications").to_h { |name| [name, false] }
rehearsal["artifacts"] = artifacts.select do |entry|
  ReleasePolicy.expected_artifact_roles(policy, rehearsal.fetch("qualifications")).include?(entry.fetch("role"))
end
rehearsal_payload = rehearsal.fetch("artifacts").sort_by { |entry| entry.fetch("role") }.map do |entry|
  %w[role file bytes sha256].map { |key| entry.fetch(key) }.join("\t") + "\n"
end.join
rehearsal_set = Digest::SHA256.hexdigest(rehearsal_payload)
rehearsal["artifactSetSha256"] = rehearsal_set
rehearsal["candidateId"] = "#{policy.fetch("plugin")}-1.0.0-#{commit[0, 12]}-#{rehearsal_set[0, 12]}"
ReleasePolicy.validate_candidate!(rehearsal, policy)

assert_rejected = lambda do |label, &mutation|
  changed = JSON.parse(JSON.generate(candidate))
  mutation.call(changed)
  begin
    ReleasePolicy.validate_candidate!(changed, policy)
  rescue ReleasePolicy::Error
    next
  end
  abort("Release policy accepted #{label}")
end

assert_rejected.call("another plugin") { |value| value["plugin"] = "another-plugin" }
assert_rejected.call("another repository") do |value|
  value.fetch("source")["repository"] = "https://github.com/example/other.git"
end
assert_rejected.call("a reduced automated matrix") do |value|
  value.fetch("acceptance").fetch("automatedTargets").shift
end
assert_rejected.call("a reduced manual scenario matrix") do |value|
  value.fetch("acceptance").fetch("manualScenarios").shift
end
assert_rejected.call("a reduced artifact set") { |value| value.fetch("artifacts").shift }
assert_rejected.call("an unsafe artifact path") { |value| value.fetch("artifacts").first["file"] = "../payload" }
assert_rejected.call("a different artifact-set digest") { |value| value["artifactSetSha256"] = "b" * 64 }
assert_rejected.call("a different candidate id") { |value| value["candidateId"] = "policy-test" }
assert_rejected.call("an extra qualification") { |value| value.fetch("qualifications")["otherCheck"] = true }
assert_rejected.call("a false candidate qualification") do |value|
  value.fetch("qualifications")[policy.fetch("qualifications").first] = false
end

puts "Verified fail-closed #{policy.fetch("plugin")} release policy."
