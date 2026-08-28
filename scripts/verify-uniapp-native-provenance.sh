#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
read -r uts_version native_version _ legacy_version root_version < <(
  bash "${script_dir}/resolve-uniapp-product.sh" "${plugin_dir}/plugin.yaml"
)

if [[ "${native_version}" != "${root_version}" || "${legacy_version}" != "${root_version}" ]]; then
  echo "UniApp native provenance and legacy product must remain at root version ${root_version}." >&2
  exit 1
fi

manifest_path="${plugin_dir}/dist/native-release/levixel-native-${native_version}.json"
android_artifact="${plugin_dir}/dist/native-android/levixel-${native_version}.aar"
ios_artifact="${plugin_dir}/dist/native-ios/levixel-${native_version}.xcframework.zip"
for required_path in "${manifest_path}" "${android_artifact}" "${ios_artifact}"; do
  if [[ ! -f "${required_path}" ]]; then
    echo "UniApp ${uts_version} native provenance input is missing: ${required_path}" >&2
    exit 1
  fi
done

native_commit="$(ruby -rjson -rdigest -e '
  manifest_path, android_path, ios_path, native_version = ARGV
  manifest = JSON.parse(File.read(manifest_path))
  abort("Unexpected native release schema") unless manifest.fetch("schemaVersion") == 1
  abort("Unexpected native release plugin") unless manifest.fetch("plugin") == "levixel"
  abort("Native release version mismatch") unless manifest.fetch("version") == native_version
  abort("Dirty native release is not reusable") unless manifest.fetch("dirty") == false
  commit = manifest.fetch("commit")
  abort("Invalid native release commit") unless commit.match?(/\A[0-9a-f]{40}\z/)
  artifacts = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
  {
    "levixel-#{native_version}.aar" => android_path,
    "levixel-#{native_version}.xcframework.zip" => ios_path,
  }.each do |name, path|
    record = artifacts.fetch(name)
    abort("Native byte size drifted for #{name}") unless File.size(path) == record.fetch("bytes")
    abort("Native SHA-256 drifted for #{name}") unless Digest::SHA256.file(path).hexdigest == record.fetch("sha256")
  end
  print commit
' "${manifest_path}" "${android_artifact}" "${ios_artifact}" "${native_version}")"

if ! git -C "${plugin_dir}" cat-file -e "${native_commit}^{commit}" 2>/dev/null \
  || ! git -C "${plugin_dir}" merge-base --is-ancestor "${native_commit}" HEAD; then
  echo "Native release commit ${native_commit} is not an ancestor of the current release source." >&2
  exit 1
fi

printf 'Verified UniApp %s native provenance: %s (%s)\n' \
  "${uts_version}" "${native_version}" "${native_commit}"
