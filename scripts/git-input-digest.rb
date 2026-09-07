require "digest"
require "open3"

# Hash repository-controlled inputs, including file names and executable modes.
# Toolchains and runtime environments are not inferred from a Git revision.
module GitInputDigest
  class Error < StandardError; end

  module_function

  def git(root, *arguments, input: "")
    output, error, status = Open3.capture3("git", "-C", root.to_s, *arguments, stdin_data: input)
    raise Error, "Git input inspection failed (#{arguments.first}): #{error.strip}" unless status.success?
    output
  end

  def commit!(root, commit)
    raise Error, "Expected a full Git commit" unless
      commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
    git(root, "cat-file", "-e", "#{commit}^{commit}")
  end

  def ancestor!(root, source, destination)
    commit!(root, source)
    commit!(root, destination)
    git(root, "merge-base", "--is-ancestor", source, destination)
  end

  def clean_head!(root, expected = nil)
    head = git(root, "rev-parse", "HEAD").strip
    commit!(root, head)
    raise Error, "Repository commit changed during verification" if expected && expected != head
    raise Error, "A clean worktree is required" unless
      git(root, "status", "--porcelain", "--untracked-files=all").empty?
    head
  end

  def digest(root, commit, paths)
    commit!(root, commit)
    raise Error, "Input scopes must be a non-empty, sorted, unique array" unless
      paths.is_a?(Array) && !paths.empty? && paths.all? { |path| path.is_a?(String) } &&
        paths == paths.sort.uniq
    paths.each do |path|
      raise Error, "Unsafe input scope: #{path.inspect}" unless
        path.match?(/\A[A-Za-z0-9_.\/-]+\z/) &&
        path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
    end
    records = git(root, "ls-tree", "-r", "-z", "--full-tree", commit).split("\0")
    selected = records.select do |record|
      _metadata, path = record.split("\t", 2)
      paths.any? { |scope| path == scope || path.start_with?(scope + "/") }
    end
    paths.each do |scope|
      raise Error, "Missing tracked input scope at #{commit}: #{scope}" unless
        selected.any? do |record|
          path = record.split("\t", 2).last
          path == scope || path.start_with?(scope + "/")
        end
    end
    files = selected.sort.map do |record|
      metadata, path = record.split("\t", 2)
      mode, type, object = metadata.split(" ")
      raise Error, "Input must be a tracked regular file: #{path}" unless
        %w[100644 100755].include?(mode) && type == "blob" && object.match?(/\A[0-9a-f]{40}\z/)
      [mode, object, path]
    end
    # Hash the actual blob contents, not a SHA-256 wrapper around Git's SHA-1 ids.
    blobs = git(root, "cat-file", "--batch", input: files.map { |file| file[1] }.join("\n") + "\n").b
    digest = Digest::SHA256.new
    digest << "repository-inputs\0" << paths.join("\0") << "\0\0"
    offset = 0
    files.each do |mode, object, path|
      newline = blobs.index("\n", offset)
      raise Error, "Incomplete Git blob response: #{path}" unless newline
      header = blobs.byteslice(offset, newline - offset)
      match = header.match(/\A#{object} blob (\d+)\z/)
      raise Error, "Unexpected Git blob response: #{path}" unless match
      size = Integer(match[1], 10)
      offset = newline + 1
      content = blobs.byteslice(offset, size)
      raise Error, "Incomplete Git blob content: #{path}" unless
        content && content.bytesize == size && blobs.getbyte(offset + size) == 10
      digest << mode << "\0" << path << "\0" << [size].pack("Q>") << content
      offset += size + 1
    end
    raise Error, "Unexpected trailing Git blob data" unless offset == blobs.bytesize
    digest.hexdigest
  end
end
