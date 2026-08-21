#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_id="Sandrox-Levixel"
archive_path="${1:-${plugin_dir}/dist/uniapp/sandrox-levixel-uniapp-${version}.zip}"
checksum_path="${archive_path}.sha256"
host_plugin_root="${repo_root}/uniapp-plugins-test/nativeplugins/${package_id}"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

if [[ ! -f "${archive_path}" || ! -f "${checksum_path}" ]]; then
  echo "UniApp artifact or checksum is missing: ${archive_path}" >&2
  exit 1
fi

expected_checksum="$(awk 'NR == 1 { print $1 }' "${checksum_path}")"
actual_checksum="$(shasum -a 256 "${archive_path}" | awk '{ print $1 }')"
if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
  echo "UniApp artifact checksum mismatch" >&2
  exit 1
fi

unzip -q "${archive_path}" -d "${work_dir}/package"
package_root="${work_dir}/package/${package_id}"

for required_path in \
  package.json \
  LICENSE \
  THIRD_PARTY_NOTICES.md \
  js_sdk/index.js \
  js_sdk/index.d.ts \
  android/LevixelUniApp-release.aar \
  "android/Levixel-${version}.aar" \
  android/PhotoView-2.3.0.aar \
  ios/LevixelUniApp.framework/LevixelUniApp \
  ios/Levixel.framework/Levixel; do
  if [[ ! -e "${package_root}/${required_path}" ]]; then
    echo "UniApp package is missing ${required_path}" >&2
    exit 1
  fi
done

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  version = ARGV.fetch(1)
  abort "unexpected package id" unless package.fetch("id") == "Sandrox-Levixel"
  abort "unexpected package version" unless package.fetch("version") == version
  native = package.fetch("_dp_nativeplugin")
  android = native.fetch("android")
  ios = native.fetch("ios")
  abort "unexpected Android module" unless android.fetch("plugins") == [{"type" => "module", "name" => "Sandrox-Levixel", "class" => "com.sandrox.levixel.uniapp.LevixelUniModule"}]
  abort "unexpected iOS module" unless ios.fetch("plugins") == [{"type" => "module", "name" => "Sandrox-Levixel", "class" => "LevixelUniModule"}]
  abort "Levixel.framework must be embedded" unless ios.fetch("embedFrameworks") == ["Levixel.framework"]
' "${package_root}/package.json" "${version}"

if rg -n "Galeria|ChrisUniPlugin|com\.chris|galleryId|sourceRectScale" \
  "${package_root}/package.json" "${package_root}/js_sdk"; then
  echo "UniApp artifact contains a superseded contract or package identity" >&2
  exit 1
fi

unzip -p "${package_root}/android/LevixelUniApp-release.aar" classes.jar > "${work_dir}/bridge-classes.jar"
jar tf "${work_dir}/bridge-classes.jar" > "${work_dir}/bridge-classes.txt"
if rg '^com/sandrox/levixel/(?!uniapp/).+\.class$' "${work_dir}/bridge-classes.txt" --pcre2; then
  echo "UniApp Android bridge copied native core classes" >&2
  exit 1
fi
if ! rg -q '^com/sandrox/levixel/uniapp/LevixelUniModule.class$' "${work_dir}/bridge-classes.txt"; then
  echo "UniApp Android module class is missing" >&2
  exit 1
fi

bridge_binary="${package_root}/ios/LevixelUniApp.framework/LevixelUniApp"
core_binary="${package_root}/ios/Levixel.framework/Levixel"
if ! file "${bridge_binary}" | rg -q 'current ar archive'; then
  echo "LevixelUniApp.framework must be a static bridge framework" >&2
  exit 1
fi
if ! file "${core_binary}" | rg -q 'Mach-O 64-bit dynamically linked shared library arm64'; then
  echo "Levixel.framework must be an arm64 dynamic framework" >&2
  exit 1
fi

LEVIXEL_UNIAPP_SDK_PATH="${package_root}/js_sdk/index.js" \
  node "${plugin_dir}/adapters/uniapp/js_sdk/index.test.mjs"

rm -rf "${host_plugin_root}"
mkdir -p "$(dirname "${host_plugin_root}")"
cp -R "${package_root}" "${host_plugin_root}"

printf 'Verified and staged %s\n' "${archive_path}"
