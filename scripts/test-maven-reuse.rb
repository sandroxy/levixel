#!/usr/bin/env ruby

require "minitest/autorun"
require "fileutils"
require_relative "verify-maven-reuse"

class MavenReuseTest < Minitest::Test
  def setup
    @temporary = Dir.mktmpdir("maven-reuse-test-")
    @aar = File.join(@temporary, "artifact.aar")
    @prefix = "io/gitee/sandrox/levixel/1.0.0/"
    @files = {}
    @payloads = [".aar", ".pom", ".module", "-sources.jar", "-javadoc.jar"].map { |suffix| "levixel-1.0.0#{suffix}" }
    @payloads.each do |file|
      [file, file + ".asc"].each do |name|
        content = name + " fixture content\n"
        @files[@prefix + name] = content
        {"md5" => Digest::MD5, "sha1" => Digest::SHA1, "sha256" => Digest::SHA256, "sha512" => Digest::SHA512}.each do |hash, type|
          @files[@prefix + name + "." + hash] = type.hexdigest(content)
        end
      end
    end
    @archives = {"repository" => @files.dup, "bundle" => @files.dup}
    @signer = MavenReuse::SIGNER
    @signature_failure = false
    @extra_entries = []
    @verified_signatures = []
    File.binwrite(@aar, @files.fetch(@prefix + "levixel-1.0.0.aar"))
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def verify
    inspection = lambda do |*arguments|
      if arguments[0, 2] == ["unzip", "-Z1"]
        (@archives.fetch(arguments.fetch(2)).keys + @extra_entries).join("\n") + "\n"
      elsif arguments[0, 2] == ["unzip", "-p"]
        @archives.fetch(arguments.fetch(2)).fetch(arguments.fetch(3))
      elsif arguments.first == "gpg"
        assert_includes arguments, "--no-auto-key-retrieve"
        assert_includes arguments, "--verify"
        assert File.file?(arguments[-1]) && File.file?(arguments[-2])
        raise MavenReuse::Error, "GPG rejected signature" if @signature_failure
        @verified_signatures << File.basename(arguments.last)
        "[GNUPG:] VALIDSIG #{@signer} 2020-01-01 0 0 0 0 0 0 0\n"
      else
        flunk "Unexpected verification command: #{arguments.inspect}"
      end
    end
    MavenReuse.stub(:command, inspection) do
      MavenReuse.verify!(repository: "repository", bundle: "bundle", aar: @aar, version: "1.0.0")
    end
  end

  def test_every_maven_payload_and_signature_is_checked
    verify
    assert_equal @payloads, @verified_signatures
  end

  def test_wrong_signer_is_rejected
    @signer = "A" * 40
    assert_raises(MavenReuse::Error) { verify }
  end

  def test_gpg_failure_is_not_ignored
    @signature_failure = true
    assert_raises(MavenReuse::Error) { verify }
  end

  def test_missing_signature_or_checksum_is_rejected
    @archives.fetch("repository").delete(@prefix + "levixel-1.0.0.aar.asc")
    assert_raises(MavenReuse::Error) { verify }
  end

  def test_wrong_internal_checksum_is_rejected
    @archives.fetch("bundle")[@prefix + "levixel-1.0.0.aar.sha256"] = "a" * 64
    assert_raises(MavenReuse::Error) { verify }
  end

  def test_repository_and_bundle_must_agree
    @archives.fetch("bundle")[@prefix + "levixel-1.0.0.aar"] = "different payload"
    assert_raises(MavenReuse::Error) { verify }
  end

  def test_standalone_aar_must_be_the_signed_payload
    File.binwrite(@aar, "different AAR")
    assert_raises(MavenReuse::Error) { verify }
  end

  def test_zip_entry_ambiguity_is_rejected
    [@files.keys.first, "../escape", "/absolute", "unexpected.txt"].each do |entry|
      @extra_entries = [entry]
      assert_raises(MavenReuse::Error) { verify }
    end
  end
end
