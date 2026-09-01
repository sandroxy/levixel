#!/usr/bin/env ruby

require "digest"
require "open3"
require "optparse"
require "pathname"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: #{$PROGRAM_NAME} [--commit SHA]"
  parser.on("--commit SHA") { |value| options[:commit] = value }
end.parse!
abort("Unexpected arguments: #{ARGV.join(" ")}") unless ARGV.empty?

root = Pathname.new(__dir__).parent.realpath
inputs = [
  "native/ios/Levixel",
  "native/ios/Levixel.xcodeproj",
]

commit = options[:commit]
if commit
  abort("Invalid source commit: #{commit}") unless commit.match?(/\A[0-9a-f]{40}\z/)
  _output, error, status = Open3.capture3(
    "git", "-C", root.to_s, "cat-file", "-e", "#{commit}^{commit}"
  )
  abort("Unable to resolve iOS source commit #{commit}: #{error}") unless status.success?
  output, error, status = Open3.capture3(
    "git", "-C", root.to_s, "ls-tree", "-r", "-z", "--name-only", commit, "--", *inputs
  )
else
  output, error, status = Open3.capture3(
    "git", "-C", root.to_s, "ls-files", "-z", "--cached", "--others",
    "--exclude-standard", "--", *inputs
  )
end
abort("Unable to enumerate iOS build inputs: #{error}") unless status.success?

paths = output.split("\0").reject(&:empty?).sort
abort("No iOS build inputs were found") if paths.empty?

digest = Digest::SHA256.new
digest << "levixel-ios-source-digest-v1\0"
paths.each do |relative_path|
  content = if commit
              blob, blob_error, blob_status = Open3.capture3(
                "git", "-C", root.to_s, "cat-file", "blob", "#{commit}:#{relative_path}"
              )
              abort("Unable to read #{relative_path} at #{commit}: #{blob_error}") unless
                blob_status.success?
              blob
            else
              path = root.join(relative_path)
              abort("iOS build input is not a regular file: #{relative_path}") unless path.file?
              path.binread
            end
  digest << [relative_path.bytesize].pack("Q>")
  digest << relative_path.b
  digest << [content.bytesize].pack("Q>")
  digest << content
end

puts digest.hexdigest
