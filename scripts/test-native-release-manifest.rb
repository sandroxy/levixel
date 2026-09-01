#!/usr/bin/env ruby

require "json"
require_relative "native-release-manifest"

artifact = {"file" => "levixel-1.3.0.aar", "bytes" => 1, "sha256" => "a" * 64}
manifest = {
  "schemaVersion" => 2,
  "plugin" => "levixel",
  "version" => "1.3.0",
  "commit" => "b" * 40,
  "dirty" => false,
  "androidMavenSigned" => true,
  "buildProvenance" => {
    "iosXcframework" => {
      "sourceCommit" => "b" * 40,
      "sourceDigest" => "d" * 64,
    },
  },
  "artifacts" => [artifact],
}
NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: "1.3.0")

reject = lambda do |label, &mutation|
  changed = JSON.parse(JSON.generate(manifest))
  mutation.call(changed)
  begin
    NativeReleaseManifest.validate!(changed, plugin: "levixel", version: "1.3.0")
  rescue NativeReleaseManifest::Error
    next
  end
  abort("Native manifest contract accepted #{label}")
end

reject.call("a legacy schema for 1.3.0") { |value| value["schemaVersion"] = 1 }
reject.call("a missing iOS provenance") { |value| value.delete("buildProvenance") }
reject.call("an unexpected top-level field") { |value| value["unverified"] = true }
reject.call("an invalid source digest") do |value|
  value.dig("buildProvenance", "iosXcframework")["sourceDigest"] = "unknown"
end
reject.call("an invalid iOS source commit") do |value|
  value.dig("buildProvenance", "iosXcframework")["sourceCommit"] = "unknown"
end

accepted_candidate = JSON.parse(JSON.generate(manifest))
accepted_candidate.dig("buildProvenance", "iosXcframework")["sourceCommit"] = "c" * 40
NativeReleaseManifest.validate!(accepted_candidate, plugin: "levixel", version: "1.3.0")

legacy = JSON.parse(JSON.generate(manifest))
legacy["schemaVersion"] = 1
legacy["version"] = "1.2.0"
legacy.delete("androidMavenSigned")
legacy.delete("buildProvenance")
legacy.fetch("artifacts").first["file"] = "levixel-1.2.0.aar"
NativeReleaseManifest.validate!(legacy, plugin: "levixel", version: "1.2.0")

puts "Verified versioned native release manifest contracts."
