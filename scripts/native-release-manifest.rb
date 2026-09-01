#!/usr/bin/env ruby

module NativeReleaseManifest
  class Error < StandardError; end

  SHA40_PATTERN = /\A[0-9a-f]{40}\z/
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  SEMVER_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/

  module_function

  def validate!(manifest, plugin:, version:)
    raise Error, "Native release manifest must be an object" unless manifest.is_a?(Hash)
    raise Error, "Invalid native release version: #{version}" unless
      version.is_a?(String) && version.match?(SEMVER_PATTERN)
    expected_fields = %w[
      androidMavenSigned artifacts buildProvenance commit dirty plugin schemaVersion version
    ]
    raise Error, "Native release manifest fields differ" unless manifest.keys.sort == expected_fields.sort
    raise Error, "Unexpected native release manifest schema" unless manifest.fetch("schemaVersion") == 2
    raise Error, "Unexpected native release plugin" unless manifest.fetch("plugin") == plugin
    raise Error, "Native release version mismatch" unless manifest.fetch("version") == version
    commit = manifest.fetch("commit")
    raise Error, "Invalid native release commit" unless
      commit.is_a?(String) && commit.match?(SHA40_PATTERN)
    raise Error, "Invalid native release dirty flag" unless [true, false].include?(manifest.fetch("dirty"))
    artifacts = manifest.fetch("artifacts")
    raise Error, "Native release artifacts must be a non-empty array" unless
      artifacts.is_a?(Array) && !artifacts.empty?
    artifacts.each do |entry|
      raise Error, "Invalid native artifact record" unless
        entry.is_a?(Hash) && entry.keys.sort == %w[bytes file sha256]
      raise Error, "Invalid native artifact filename" unless
        entry.fetch("file").is_a?(String) && !entry.fetch("file").empty? &&
          File.basename(entry.fetch("file")) == entry.fetch("file")
      raise Error, "Invalid native artifact byte count" unless
        entry.fetch("bytes").is_a?(Integer) && entry.fetch("bytes").positive?
      checksum = entry.fetch("sha256")
      raise Error, "Invalid native artifact checksum" unless
        checksum.is_a?(String) && checksum.match?(SHA256_PATTERN)
    end
    raise Error, "Duplicate native artifact filenames" unless
      artifacts.map { |entry| entry.fetch("file") }.uniq.length == artifacts.length

    raise Error, "Invalid Maven signing qualification" unless
      [true, false].include?(manifest.fetch("androidMavenSigned"))
    provenance = manifest.fetch("buildProvenance")
    raise Error, "Invalid native build provenance" unless
      provenance.is_a?(Hash) && provenance.keys.sort == ["iosXcframework"]
    ios = provenance.fetch("iosXcframework")
    raise Error, "Invalid iOS XCFramework provenance fields" unless
      ios.is_a?(Hash) && ios.keys.sort == %w[sourceCommit sourceDigest]
    ios_commit = ios.fetch("sourceCommit")
    ios_digest = ios.fetch("sourceDigest")
    raise Error, "Invalid iOS XCFramework source commit" unless
      ios_commit.is_a?(String) && ios_commit.match?(SHA40_PATTERN)
    raise Error, "Invalid iOS XCFramework source digest" unless
      ios_digest.is_a?(String) && ios_digest.match?(SHA256_PATTERN)
    manifest
  rescue KeyError => error
    raise Error, "Incomplete native release manifest: #{error.message}"
  end
end
