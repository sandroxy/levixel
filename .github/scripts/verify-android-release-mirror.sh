#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <version> <native-manifest> <aar>" >&2
  exit 1
fi

version="$1"
manifest_path="$2"
aar_path="$3"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for required_file in "${manifest_path}" "${aar_path}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Required release input is missing: ${required_file}" >&2
    exit 1
  fi
done

ruby -I "${script_dir}/../../scripts" -rjson -rdigest -r native-release-manifest -e '
  version, manifest_path, artifact_path = ARGV
  manifest = JSON.parse(File.read(manifest_path))
  NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: version)
  abort("Dirty native release is not publishable") unless manifest["dirty"] == false

  artifact_name = "levixel-#{version}.aar"
  artifact = manifest.fetch("artifacts").find { |entry| entry["file"] == artifact_name }
  abort("Native release does not declare #{artifact_name}") unless artifact
  abort("Android AAR size mismatch") unless File.size(artifact_path) == artifact.fetch("bytes")
  abort("Android AAR checksum mismatch") unless Digest::SHA256.file(artifact_path).hexdigest == artifact.fetch("sha256")
' "${version}" "${manifest_path}" "${aar_path}"

printf '%s\n' "Verified Android release mirror: $(basename "${aar_path}")"
