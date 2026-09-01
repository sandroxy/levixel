#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <version> <ohpm-metadata> <native-manifest> <har>" >&2
  exit 1
fi

version="$1"
metadata_path="$2"
manifest_path="$3"
har_path="$4"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for required_file in "${metadata_path}" "${manifest_path}" "${har_path}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Required release input is missing: ${required_file}" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
archive_listing="${work_dir}/archive-listing.txt"
package_metadata="${work_dir}/oh-package.json5"

tar -tzf "${har_path}" > "${archive_listing}"
tar -xOzf "${har_path}" package/oh-package.json5 > "${package_metadata}"

source_entries="$(awk '/\.ets$/ && $0 !~ /\.d\.ets$/ { print }' "${archive_listing}")"
if [[ -n "${source_entries}" ]]; then
  echo "OHPM HAR unexpectedly contains implementation source:" >&2
  printf '%s\n' "${source_entries}" >&2
  exit 1
fi

ruby -I "${script_dir}/../../scripts" -rbase64 -rdigest -rjson -r native-release-manifest -e '
  version, metadata_path, manifest_path, har_path, package_metadata = ARGV
  artifact_name = "levixel-#{version}.har"

  metadata = JSON.parse(File.read(metadata_path))
  abort("Unexpected OHPM package") unless metadata["name"] == "@sandrox/levixel"
  published = metadata.fetch("versions").fetch(version)
  abort("OHPM version mismatch") unless published["version"] == version

  dist = published.fetch("dist")
  expected_tarball = "https://ohpm.openharmony.cn/ohpm/@sandrox/levixel/-/#{artifact_name}"
  abort("Unexpected OHPM tarball URL") unless dist["tarball"] == expected_tarball

  algorithm, encoded_digest = dist.fetch("integrity").split("-", 2)
  abort("Unexpected OHPM integrity algorithm") unless algorithm == "sha512"
  actual_integrity = Base64.strict_encode64(Digest::SHA512.file(har_path).digest)
  abort("OHPM HAR integrity mismatch") unless actual_integrity == encoded_digest

  package = JSON.parse(File.read(package_metadata))
  expected_package = {
    "name" => "@sandrox/levixel",
    "version" => version,
    "author" => {
      "name" => "SandroX",
      "email" => "wangyifengjxc@gmail.com",
      "url" => "https://github.com/sandroxy"
    },
    "license" => "MIT",
    "homepage" => "https://github.com/sandroxy/levixel",
    "repository" => "https://github.com/sandroxy/levixel",
    "types" => "Index.d.ets"
  }
  mismatches = expected_package.reject { |key, value| package[key] == value }
  abort("Unexpected HarmonyOS release metadata: #{mismatches.inspect}") unless mismatches.empty?
  abort("HarmonyOS release is not a bytecode HAR") unless package.dig("metadata", "byteCodeHar") == true

  manifest = JSON.parse(File.read(manifest_path))
  NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: version)
  abort("Dirty native release is not publishable") unless manifest["dirty"] == false

  artifact = manifest.fetch("artifacts").find { |entry| entry["file"] == artifact_name }
  abort("Native release does not declare #{artifact_name}") unless artifact
  artifact["bytes"] = File.size(har_path)
  artifact["sha256"] = Digest::SHA256.file(har_path).hexdigest
  File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
' "${version}" "${metadata_path}" "${manifest_path}" "${har_path}" "${package_metadata}"

printf '%s\n' "Prepared HarmonyOS release mirror: $(basename "${har_path}")"
