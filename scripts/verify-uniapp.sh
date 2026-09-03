#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
read -r version native_version source_root_relative _ _ < <(
  bash "${script_dir}/resolve-uniapp-product.sh" "${plugin_dir}/plugin.yaml"
)
if [[ "${source_root_relative}" != "uni_modules/Sandrox-Levixel" ]]; then
  echo "UniApp sourceRoot must be uni_modules/Sandrox-Levixel, got ${source_root_relative}" >&2
  exit 1
fi
source_root="${plugin_dir}/${source_root_relative}"
package_id="Sandrox-Levixel"
archive_path="${1:-${plugin_dir}/dist/uniapp/levixel-uniapp-${version}.zip}"
checksum_path="${archive_path}.sha256"
marketplace_path="${archive_path%.zip}-marketplace.md"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

"${script_dir}/sync-uniapp-canonical-js.sh" --check
bash "${script_dir}/verify-uniapp-native-provenance.sh"

if [[ ! -f "${archive_path}" || ! -f "${checksum_path}" || ! -f "${marketplace_path}" ]]; then
  echo "UniApp UTS artifact or checksum is missing: ${archive_path}" >&2
  exit 1
fi

expected_checksum="$(awk 'NR == 1 { print $1 }' "${checksum_path}")"
actual_checksum="$(shasum -a 256 "${archive_path}" | awk '{ print $1 }')"
if [[ "${actual_checksum}" != "${expected_checksum}" ]]; then
  echo "UniApp UTS artifact checksum mismatch" >&2
  exit 1
fi

if grep -Eq '@VERSION@|@NATIVE_VERSION@|@CHECKSUM@' "${marketplace_path}" || \
   ! grep -Fq "${actual_checksum}" "${marketplace_path}" || \
   ! grep -Fq -- "- 原生核心版本：\`${native_version}\`" "${marketplace_path}"; then
  echo "UniApp marketplace material does not match the candidate" >&2
  exit 1
fi

if unzip -Z1 "${archive_path}" | grep -E '(^|/)(__MACOSX|\.DS_Store)(/|$)' >/dev/null; then
  echo "UniApp UTS artifact contains macOS metadata" >&2
  exit 1
fi
if unzip -Z1 "${archive_path}" | grep -E "^${package_id}/" >/dev/null; then
  echo "UniApp Marketplace ZIP must expose package.json and utssdk at the archive root, not under ${package_id}/" >&2
  exit 1
fi

unzip -q "${archive_path}" -d "${work_dir}/package"
package_root="${work_dir}/package"

for required_path in \
  package.json \
  readme.md \
  changelog.md \
  license.md \
  LICENSE \
  THIRD_PARTY_NOTICES.md \
  js_sdk/index.js \
  js_sdk/canonical.js \
  js_sdk/index.d.ts \
  utssdk/interface.uts \
  utssdk/app-android/index.uts \
  utssdk/app-android/config.json \
  "utssdk/app-android/libs/LevixelUniRuntime-${native_version}.aar" \
  "utssdk/app-android/libs/Levixel-${native_version}.aar" \
  utssdk/app-android/libs/PhotoView-2.3.0.aar \
  utssdk/app-ios/index.uts \
  utssdk/app-ios/config.json \
  utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/LevixelUniRuntime \
  utssdk/app-ios/Frameworks/Levixel.framework/Levixel; do
  if [[ ! -e "${package_root}/${required_path}" ]]; then
    echo "UniApp UTS package is missing ${required_path}" >&2
    exit 1
  fi
done

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  version = ARGV.fetch(1)
  abort "unexpected package id" unless package.fetch("id") == "Sandrox-Levixel"
  abort "unexpected package version" unless package.fetch("version") == version
  abort "package must be a UTS plugin" unless package.dig("dcloudext", "type") == "uts"
  abort "legacy native-plugin metadata must not exist" if package.key?("_dp_nativeplugin")
  abort "DCloud permits at most five keywords" unless package.fetch("keywords").length <= 5
  abort "unexpected HBuilderX minimum" unless package.dig("engines", "HBuilderX") == "^5.24"
  abort "uni-app x engine declaration missing" unless package.dig("engines", "uni-app-x") == "^5.24"

  client = package.dig("uni_modules", "platforms", "client")
  classic = client.fetch("uni-app")
  abort "classic Vue 2 support missing" unless classic.dig("vue", "vue2") == "√"
  abort "classic Vue 3 support missing" unless classic.dig("vue", "vue3") == "√"
  abort "nvue must be explicitly unsupported" unless classic.dig("app", "nvue") == "x"
  abort "unexpected Android minimum" unless classic.dig("app", "android", "minVersion") == "21"
  abort "unexpected iOS minimum" unless classic.dig("app", "ios", "minVersion") == "13.0"

  x = client.fetch("uni-app-x")
  abort "uni-app x Android support missing" unless x.dig("app", "android", "extVersion") == version
  abort "unexpected uni-app x Android minimum" unless x.dig("app", "android", "minVersion") == "23"
  abort "uni-app x iOS support missing" unless x.dig("app", "ios", "extVersion") == version
  abort "unexpected uni-app x iOS minimum" unless x.dig("app", "ios", "minVersion") == "15.0"
  abort "uni-app x HarmonyOS must be unsupported" unless x.dig("app", "harmony") == "x"
  abort "uni-app x Web must be unsupported" unless x.fetch("web").values.all? { |entry| entry == "x" }
  abort "uni-app x mini app must be unsupported" unless x.fetch("mp").values.all? { |entry| entry == "x" }
' "${package_root}/package.json" "${version}"

ruby -rjson -e '
  android = JSON.parse(File.read(ARGV.fetch(0)))
  abort "unexpected Android minimum" unless android.fetch("minSdkVersion") == 21
  required = [
    "androidx.appcompat:appcompat:1.7.1",
    "androidx.recyclerview:recyclerview:1.4.0",
    "androidx.viewpager2:viewpager2:1.1.0",
    "androidx.core:core:1.15.0",
    "com.github.bumptech.glide:glide:4.16.0",
    "androidx.media3:media3-exoplayer:1.5.1",
    "androidx.media3:media3-ui:1.5.1",
  ]
  abort "Android dependencies drifted" unless android.fetch("dependencies") == required

  ios = JSON.parse(File.read(ARGV.fetch(1)))
  abort "unexpected iOS minimum" unless ios.fetch("deploymentTarget") == "13.0"
  abort "unexpected iOS architectures" unless ios.fetch("validArchitectures") == ["arm64"]
' "${package_root}/utssdk/app-android/config.json" "${package_root}/utssdk/app-ios/config.json"

cmp "${plugin_dir}/LICENSE" "${package_root}/LICENSE"
cmp "${plugin_dir}/LICENSE" "${package_root}/license.md"
cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"
cmp "${plugin_dir}/adapters/uniapp/js_sdk/index.js" "${source_root}/js_sdk/canonical.js"
cmp "${source_root}/js_sdk/canonical.js" "${package_root}/js_sdk/canonical.js"
cmp "${plugin_dir}/adapters/uniapp/js_sdk/index.d.ts" "${package_root}/js_sdk/index.d.ts"
cmp \
  "${plugin_dir}/dist/native-android/levixel-${native_version}.aar" \
  "${package_root}/utssdk/app-android/libs/Levixel-${native_version}.aar"
if [[ "${version}" != "${native_version}" \
  && ( -e "${package_root}/utssdk/app-android/libs/Levixel-${version}.aar" \
    || -e "${package_root}/utssdk/app-android/libs/LevixelUniRuntime-${version}.aar" ) ]]; then
  echo "UniApp ${version} must not relabel its ${native_version} Android dependencies" >&2
  exit 1
fi
mkdir -p "${work_dir}/accepted-native-ios"
unzip -q \
  "${plugin_dir}/dist/native-ios/levixel-${native_version}.xcframework.zip" \
  'Levixel.xcframework/ios-arm64/*' \
  -d "${work_dir}/accepted-native-ios"
diff -qr \
  "${work_dir}/accepted-native-ios/Levixel.xcframework/ios-arm64/Levixel.framework" \
  "${package_root}/utssdk/app-ios/Frameworks/Levixel.framework"

runtime_aar="${package_root}/utssdk/app-android/libs/LevixelUniRuntime-${native_version}.aar"
unzip -p "${runtime_aar}" classes.jar > "${work_dir}/runtime-classes.jar"
jar tf "${work_dir}/runtime-classes.jar" > "${work_dir}/runtime-classes.txt"
if ! grep -Eq '^com/sandrox/levixel/uniapp/runtime/LevixelUniRuntime.class$' "${work_dir}/runtime-classes.txt"; then
  echo "Android shared runtime facade is missing" >&2
  exit 1
fi
if awk '
  /^io\/dcloud\/.+\.class$/ { found = 1 }
  /^com\/sandrox\/levixel\/.+\.class$/ && $0 !~ /^com\/sandrox\/levixel\/uniapp\/runtime\// { found = 1 }
  END { exit(found ? 0 : 1) }
' "${work_dir}/runtime-classes.txt"; then
  echo "Android shared runtime contains DCloud or copied core classes" >&2
  exit 1
fi

runtime_binary="${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/LevixelUniRuntime"
core_binary="${package_root}/utssdk/app-ios/Frameworks/Levixel.framework/Levixel"
if ! file "${runtime_binary}" | grep -E 'current ar archive' >/dev/null; then
  echo "LevixelUniRuntime.framework must be a static runtime framework" >&2
  exit 1
fi
if ! file "${core_binary}" | grep -E 'Mach-O 64-bit dynamically linked shared library arm64' >/dev/null; then
  echo "Levixel.framework must be an arm64 dynamic framework" >&2
  exit 1
fi
if ! grep -Eq 'openWithJSON:.*rootView:.*viewController:.*completion:' \
  "${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/Headers/LevixelUniRuntime-Swift.h"; then
  echo "iOS shared runtime JSON entry point is missing" >&2
  exit 1
fi
if ! grep -Eq 'setJSONEventHandler:' \
  "${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/Headers/LevixelUniRuntime-Swift.h"; then
  echo "iOS shared runtime event replacement entry point is missing" >&2
  exit 1
fi

if ! grep -Eq '__setLevixelNativeTransport' "${package_root}/js_sdk/canonical.js"; then
  echo "Canonical JS transport injection point is missing" >&2
  exit 1
fi
if ! grep -Fq "from '@/uni_modules/Sandrox-Levixel'" "${package_root}/js_sdk/index.js"; then
  echo "UTS JS transport wrapper is not wired to the plugin root" >&2
  exit 1
fi
if ! grep -Eq 'getFileSystemManager' "${package_root}/js_sdk/canonical.js"; then
  echo "Canonical JS does not contain the uni-app x FileSystemManager path" >&2
  exit 1
fi
if ! grep -Eq 'resolveLevixelNativePaths' "${package_root}/js_sdk/index.js" \
  || ! grep -Eq 'resolvePaths\(paths\)' "${package_root}/js_sdk/index.js" \
  || ! grep -Eq 'ResolveLevixelNativePaths' "${package_root}/utssdk/interface.uts"; then
  echo "UTS JS transport batch path resolver is incomplete" >&2
  exit 1
fi
if ! grep -Eq 'UTSAndroid\.getResourcePath' "${package_root}/utssdk/app-android/index.uts" \
  || ! grep -Eq 'UTSAndroid\.convert2AbsFullPath' "${package_root}/utssdk/app-android/index.uts" \
  || ! grep -Fq "'uni_modules/'" "${package_root}/utssdk/app-android/index.uts" \
  || ! grep -Fq "'/static/'" "${package_root}/utssdk/app-android/index.uts"; then
  echo "Android UTS local path conversion is missing" >&2
  exit 1
fi
if ! grep -Eq 'UTSiOS\.convert2AbsFullPath' "${package_root}/utssdk/app-ios/index.uts"; then
  echo "iOS UTS local path conversion is missing" >&2
  exit 1
fi

node --input-type=module --check < "${package_root}/js_sdk/index.js"
node --input-type=module --check < "${source_root}/js_sdk/canonical.js"
LEVIXEL_UNIAPP_SDK_PATH="${package_root}/js_sdk/canonical.js" \
  node "${plugin_dir}/adapters/uniapp/js_sdk/index.test.mjs"
bash "${plugin_dir}/adapters/uniapp/ios/verify-event-relay.sh"
bash "${plugin_dir}/adapters/uniapp/ios/verify-synthetic-anchor-visibility.sh"
bash "${plugin_dir}/adapters/uniapp/ios/verify-source-geometry.sh"

printf 'Verified %s\n' "${archive_path}"
