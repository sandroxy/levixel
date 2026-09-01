#!/usr/bin/env ruby

require "digest"
require "open3"
require "pathname"

root = Pathname.new(__dir__).parent.realpath
digest_script = root.join("scripts/compute-ios-source-digest.rb")
inputs = [
  "native/ios/Levixel",
  "native/ios/Levixel.xcodeproj",
]
required_project_inputs = %w[
  native/ios/Levixel.xcodeproj/project.pbxproj
  native/ios/Levixel.xcodeproj/project.xcworkspace/contents.xcworkspacedata
  native/ios/Levixel.xcodeproj/xcshareddata/xcschemes/Levixel.xcscheme
]

run_git = lambda do |*arguments|
  output, error, status = Open3.capture3("git", "-C", root.to_s, *arguments)
  abort("Git command failed: #{error}") unless status.success?
  output
end

enumerate = lambda do |commit|
  output = if commit
             run_git.call("ls-tree", "-r", "-z", "--name-only", commit, "--", *inputs)
           else
             run_git.call(
               "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *inputs
             )
           end
  output.split("\0").reject(&:empty?).sort
end

expected_digest = lambda do |commit|
  paths = enumerate.call(commit)
  missing = required_project_inputs - paths
  abort("iOS source digest omits project inputs: #{missing.join(", ")}") unless missing.empty?

  digest = Digest::SHA256.new
  digest << "levixel-ios-source-digest-v1\0"
  paths.each do |relative_path|
    content = if commit
                run_git.call("cat-file", "blob", "#{commit}:#{relative_path}")
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
  digest.hexdigest
end

run_digest = lambda do |*arguments|
  output, error, status = Open3.capture3(digest_script.to_s, *arguments)
  abort("iOS source digest command failed: #{error}") unless status.success?
  value = output.strip
  abort("iOS source digest command returned an invalid digest") unless value.match?(/\A[0-9a-f]{64}\z/)
  value
end

worktree_digest = run_digest.call
abort("Worktree iOS source digest omits a build input") unless
  worktree_digest == expected_digest.call(nil)

head = run_git.call("rev-parse", "HEAD").strip
commit_digest = run_digest.call("--commit", head)
abort("Committed iOS source digest omits a build input") unless
  commit_digest == expected_digest.call(head)

puts "Verified complete iOS source-digest coverage for source and shared project inputs."
