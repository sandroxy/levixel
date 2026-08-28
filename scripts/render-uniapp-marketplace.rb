#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

unless ARGV.length == 6
  warn "Usage: render-uniapp-marketplace.rb TEMPLATE PACKAGE_JSON CHANGELOG VERSION NATIVE_VERSION CHECKSUM"
  exit 1
end

template_path, package_path, changelog_path, version, native_version, checksum = ARGV

abort "Invalid product version: #{version}" unless version.match?(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)
abort "Invalid native version: #{native_version}" unless native_version.match?(/\A\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?\z/)
abort "Invalid SHA-256: #{checksum}" unless checksum.match?(/\A[0-9a-f]{64}\z/)

package = JSON.parse(File.read(package_path))
client = package.fetch("uni_modules").fetch("platforms").fetch("client")
classic = client.fetch("uni-app").fetch("app")
vapor = client.fetch("uni-app-x").fetch("app")

minimum_version = lambda do |value, label|
  match = value.to_s.match(/\d+(?:\.\d+){1,2}/)
  abort "Cannot resolve #{label} from #{value.inspect}" unless match

  match[0]
end

changelog_lines = File.readlines(changelog_path, chomp: true)
heading_pattern = /\A##\s+#{Regexp.escape(version)}(?:\s+-.*)?\z/
start_index = changelog_lines.index { |line| line.match?(heading_pattern) }
abort "#{changelog_path} does not contain a #{version} section" unless start_index

end_index = changelog_lines.each_index.find do |index|
  index > start_index && changelog_lines[index].start_with?("## ")
end || changelog_lines.length

changelog = changelog_lines[(start_index + 1)...end_index]
  .drop_while(&:empty?)
  .reverse
  .drop_while(&:empty?)
  .reverse
  .join("\n")
abort "#{changelog_path} contains an empty #{version} section" if changelog.empty?

replacements = {
  "@VERSION@" => version,
  "@NATIVE_VERSION@" => native_version,
  "@CHECKSUM@" => checksum,
  "@HBUILDERX_MIN@" => minimum_version.call(package.fetch("engines").fetch("HBuilderX"), "HBuilderX minimum"),
  "@CLASSIC_ANDROID_MIN@" => classic.fetch("android").fetch("minVersion"),
  "@CLASSIC_IOS_MIN@" => classic.fetch("ios").fetch("minVersion"),
  "@X_ANDROID_MIN@" => vapor.fetch("android").fetch("minVersion"),
  "@X_IOS_MIN@" => vapor.fetch("ios").fetch("minVersion"),
  "@CHANGELOG@" => changelog
}

rendered = File.read(template_path)
replacements.each do |placeholder, value|
  abort "Template is missing #{placeholder}" unless rendered.include?(placeholder)

  rendered = rendered.gsub(placeholder, value)
end

unresolved = rendered.scan(/@[A-Z][A-Z0-9_]*@/).uniq
abort "Unresolved Marketplace placeholders: #{unresolved.join(", ")}" unless unresolved.empty?

print rendered
