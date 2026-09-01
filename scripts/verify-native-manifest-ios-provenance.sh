#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 NATIVE_MANIFEST IOS_XCFRAMEWORK_ZIP VERSION" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest_path="$1"
xcframework_zip="$2"
version="$3"

for required_file in "${manifest_path}" "${xcframework_zip}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "iOS provenance input is missing: ${required_file}" >&2
    exit 1
  fi
done

manifest_schema="$(
  ruby -I "${script_dir}" -rdigest -rjson -r native-release-manifest -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    artifact_path = ARGV.fetch(2)
    NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: version)
    artifact_name = "levixel-#{version}.xcframework.zip"
    artifact = manifest.fetch("artifacts").find { |entry| entry.fetch("file") == artifact_name }
    abort("Native release manifest is missing #{artifact_name}") unless artifact
    abort("iOS XCFramework byte count differs from the native manifest") unless
      File.size(artifact_path) == artifact.fetch("bytes")
    abort("iOS XCFramework checksum differs from the native manifest") unless
      Digest::SHA256.file(artifact_path).hexdigest == artifact.fetch("sha256")
    print manifest.fetch("schemaVersion")
  ' "${manifest_path}" "${version}" "${xcframework_zip}"
)"

if [[ "${manifest_schema}" == "1" ]]; then
  printf 'Verified legacy iOS artifact manifest for %s; embedded source provenance was introduced in 1.3.0.\n' \
    "${version}"
  exit 0
fi

source_digest="$("${script_dir}/compute-ios-source-digest.rb")"
read -r binary_source_commit binary_source_digest < <(
  "${script_dir}/verify-ios-xcframework-provenance.sh" \
    "${xcframework_zip}" "${version}" "${source_digest}"
)
read -r manifest_commit manifest_dirty manifest_source_commit manifest_source_digest < <(
  ruby -I "${script_dir}" -rjson -r native-release-manifest -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: version)
    ios = manifest.dig("buildProvenance", "iosXcframework")
    puts [
      manifest.fetch("commit"),
      manifest.fetch("dirty"),
      ios.fetch("sourceCommit"),
      ios.fetch("sourceDigest")
    ].join(" ")
  ' "${manifest_path}" "${version}"
)

if [[ "${manifest_source_commit}" != "${binary_source_commit}" \
    || "${manifest_source_digest}" != "${binary_source_digest}" ]]; then
  echo "Native manifest iOS provenance differs from the XCFramework." >&2
  exit 1
fi
plugin_dir="$(cd "${script_dir}/.." && pwd)"
if ! git -C "${plugin_dir}" cat-file -e "${binary_source_commit}^{commit}" 2>/dev/null \
    || ! git -C "${plugin_dir}" cat-file -e "${manifest_commit}^{commit}" 2>/dev/null \
    || ! git -C "${plugin_dir}" merge-base --is-ancestor \
      "${binary_source_commit}" "${manifest_commit}"; then
  echo "XCFramework source commit is not an ancestor of the native release commit." >&2
  exit 1
fi
if [[ "${manifest_dirty}" == false ]]; then
  committed_source_digest="$(
    "${script_dir}/compute-ios-source-digest.rb" --commit "${binary_source_commit}"
  )"
  if [[ "${committed_source_digest}" != "${binary_source_digest}" ]]; then
    echo "XCFramework source digest does not belong to its embedded source commit." >&2
    exit 1
  fi
fi

printf 'Verified iOS binary provenance: %s (%s)\n' \
  "${binary_source_commit}" "${binary_source_digest}"
