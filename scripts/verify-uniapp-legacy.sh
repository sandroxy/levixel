#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_id="Sandrox-Levixel"
archive_path="${1:-${plugin_dir}/dist/uniapp/levixel-uniapp-legacy-${version}.zip}"
checksum_path="${archive_path}.sha256"
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
  "android/LevixelUniRuntime-${version}.aar" \
  "android/Levixel-${version}.aar" \
  android/PhotoView-2.3.0.aar \
  ios/LevixelUniApp.framework/LevixelUniApp \
  ios/LevixelUniRuntime.framework/LevixelUniRuntime \
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
  expected_frameworks = ["LevixelUniApp.framework", "LevixelUniRuntime.framework", "Levixel.framework", "AVFoundation.framework", "AVKit.framework"]
  abort "unexpected iOS frameworks" unless ios.fetch("frameworks") == expected_frameworks
  abort "Levixel.framework must be embedded" unless ios.fetch("embedFrameworks") == ["Levixel.framework"]
' "${package_root}/package.json" "${version}"

if grep -R -n -E "Galeria|ChrisUniPlugin|com\.chris|sourceRectScale" \
  "${package_root}/package.json" "${package_root}/js_sdk"; then
  echo "UniApp artifact contains a superseded contract or package identity" >&2
  exit 1
fi

unzip -p "${package_root}/android/LevixelUniApp-release.aar" classes.jar > "${work_dir}/bridge-classes.jar"
jar tf "${work_dir}/bridge-classes.jar" > "${work_dir}/bridge-classes.txt"
if awk '
  /^com\/sandrox\/levixel\/.+\.class$/ && $0 !~ /^com\/sandrox\/levixel\/uniapp\// { found = 1 }
  END { exit(found ? 0 : 1) }
' "${work_dir}/bridge-classes.txt"; then
  echo "UniApp Android bridge copied native core classes" >&2
  exit 1
fi
if ! grep -Eq '^com/sandrox/levixel/uniapp/LevixelUniModule.class$' "${work_dir}/bridge-classes.txt"; then
  echo "UniApp Android module class is missing" >&2
  exit 1
fi
if grep -Eq '^com/sandrox/levixel/uniapp/runtime/.+\.class$' "${work_dir}/bridge-classes.txt"; then
  echo "UniApp Android bridge copied shared runtime classes" >&2
  exit 1
fi

unzip -p "${package_root}/android/LevixelUniRuntime-${version}.aar" classes.jar > "${work_dir}/runtime-classes.jar"
jar tf "${work_dir}/runtime-classes.jar" > "${work_dir}/runtime-classes.txt"
if ! grep -Eq '^com/sandrox/levixel/uniapp/runtime/LevixelUniRuntime.class$' "${work_dir}/runtime-classes.txt"; then
  echo "UniApp Android shared runtime facade is missing" >&2
  exit 1
fi
if awk '
  /^io\/dcloud\/.+\.class$/ { found = 1 }
  /^com\/sandrox\/levixel\/.+\.class$/ && $0 !~ /^com\/sandrox\/levixel\/uniapp\/runtime\// { found = 1 }
  END { exit(found ? 0 : 1) }
' "${work_dir}/runtime-classes.txt"; then
  echo "UniApp Android shared runtime contains DCloud or copied core classes" >&2
  exit 1
fi

bridge_binary="${package_root}/ios/LevixelUniApp.framework/LevixelUniApp"
runtime_binary="${package_root}/ios/LevixelUniRuntime.framework/LevixelUniRuntime"
core_binary="${package_root}/ios/Levixel.framework/Levixel"
if ! file "${bridge_binary}" | grep -E 'current ar archive' >/dev/null; then
  echo "LevixelUniApp.framework must be a static bridge framework" >&2
  exit 1
fi
if ! file "${runtime_binary}" | grep -E 'current ar archive' >/dev/null; then
  echo "LevixelUniRuntime.framework must be a static runtime framework" >&2
  exit 1
fi
if ! file "${core_binary}" | grep -E 'Mach-O 64-bit dynamically linked shared library arm64' >/dev/null; then
  echo "Levixel.framework must be an arm64 dynamic framework" >&2
  exit 1
fi

LEVIXEL_UNIAPP_SDK_PATH="${package_root}/js_sdk/index.js" \
  node "${plugin_dir}/adapters/uniapp/js_sdk/index.test.mjs"
bash "${plugin_dir}/adapters/uniapp/ios/verify-event-relay.sh"
bash "${plugin_dir}/adapters/uniapp/ios/verify-synthetic-anchor-visibility.sh"

printf 'Verified %s\n' "${archive_path}"
