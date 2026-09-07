require "digest"
require "open3"
require "tmpdir"

# Verify existing signatures; this never imports or exports private keys.
module MavenReuse
  class Error < StandardError; end
  SIGNER = "76C15313941EDE0281DB835E36B1957F0CEFA6B3".freeze

  module_function

  def command(*arguments)
    output, error, status = Open3.capture3(*arguments)
    raise Error, "Maven reuse verification failed: #{error.strip}" unless status.success?
    output
  end

  def verify!(repository:, bundle:, aar:, version:)
    prefix = "io/gitee/sandrox/levixel/#{version}/"
    payloads = [".aar", ".pom", ".module", "-sources.jar", "-javadoc.jar"].map do |suffix|
      "levixel-#{version}#{suffix}"
    end
    expected = payloads.flat_map do |file|
      [file, file + ".asc"].flat_map { |name| [name] + %w[md5 sha1 sha256 sha512].map { |hash| name + "." + hash } }
    end.sort
    [repository, bundle].each do |archive|
      entries = command("unzip", "-Z1", archive.to_s).lines.map(&:chomp)
      raise Error, "Duplicate or unsafe Maven ZIP entry" unless
        entries.uniq == entries && entries.all? do |entry|
          entry.match?(/\A[A-Za-z0-9_.\/-]+\z/) &&
            entry.delete_suffix("/").split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
        end
      version_files = entries.select { |name| name.start_with?(prefix) && !name.end_with?("/") }
      raise Error, "Maven archive has an unexpected version file set" unless
        version_files.map { |name| name.delete_prefix(prefix) }.sort == expected
      if archive == bundle
        raise Error, "Central bundle contains files outside the release version" unless
          entries.reject { |name| name.end_with?("/") }.sort == version_files.sort
      end
    end
    Dir.mktmpdir("levixel-maven-signatures-") do |directory|
      payloads.each do |file|
        [file, file + ".asc"].each do |name|
          content = command("unzip", "-p", repository.to_s, prefix + name)
          raise Error, "Maven repository and Central bundle differ: #{name}" unless
            command("unzip", "-p", bundle.to_s, prefix + name) == content
          File.binwrite(File.join(directory, name), content)
          { "md5" => Digest::MD5, "sha1" => Digest::SHA1, "sha256" => Digest::SHA256, "sha512" => Digest::SHA512 }.each do |hash, type|
            [repository, bundle].each do |archive|
              recorded = command("unzip", "-p", archive.to_s, prefix + name + "." + hash).strip
              raise Error, "Maven #{hash} mismatch: #{name}" unless recorded == type.hexdigest(content)
            end
          end
        end
        payload = File.join(directory, file)
        signature = payload + ".asc"
        output = command("gpg", "--batch", "--no-auto-key-retrieve", "--status-fd", "1", "--verify", signature, payload)
        fingerprints = output.lines.each_with_object([]) do |line, result|
          fields = line.split
          result << fields[2] if fields[0, 2] == ["[GNUPG:]", "VALIDSIG"]
        end
        raise Error, "Maven signature does not match the release key: #{file}" unless fingerprints == [SIGNER]
      end
      raise Error, "Standalone AAR differs from the signed Maven AAR" unless
        File.binread(aar) == File.binread(File.join(directory, "levixel-#{version}.aar"))
    end
  end
end
