#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
source_root_relative="$(ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  target = manifest.fetch("targets").find { |entry| entry.fetch("id") == "uniapp" }
  abort "UniApp target is missing from plugin.yaml" unless target
  print target.fetch("sourceRoot")
' "${plugin_dir}/plugin.yaml")"
if [[ "${source_root_relative}" != "uni_modules/Sandrox-Levixel" ]]; then
  echo "UniApp sourceRoot must be uni_modules/Sandrox-Levixel, got ${source_root_relative}" >&2
  exit 1
fi
android_adapter_dir="${plugin_dir}/adapters/uniapp/android"
ios_adapter_dir="${plugin_dir}/adapters/uniapp/ios"
source_root="${plugin_dir}/${source_root_relative}"
artifact_dir="${plugin_dir}/dist/uniapp"
staging_dir="$(mktemp -d)"
package_root="${staging_dir}/package"
archive_name="levixel-uniapp-${version}.zip"
archive_path="${artifact_dir}/${archive_name}"
marketplace_template="${plugin_dir}/adapters/uniapp/MARKETPLACE.md"
marketplace_path="${artifact_dir}/levixel-uniapp-${version}-marketplace.md"
core_android_aar="${plugin_dir}/dist/native-android/levixel-${version}.aar"
core_ios_zip="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"

cleanup() {
  rm -rf "${staging_dir}"
}
trap cleanup EXIT

"${script_dir}/sync-uniapp-canonical-js.sh" --check

if [[ "${LEVIXEL_SKIP_NATIVE_PACKAGE:-0}" != "1" ]]; then
  "${script_dir}/package-native-android.sh"
  "${script_dir}/package-native-ios.sh"
fi

if [[ ! -f "${core_android_aar}" || ! -f "${core_ios_zip}" ]]; then
  echo "Canonical native artifacts for Levixel ${version} are missing" >&2
  exit 1
fi

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  abort "UTS package version does not match #{ARGV.fetch(1)}" unless package.fetch("version") == ARGV.fetch(1)
' "${source_root}/package.json" "${version}"

"${plugin_dir}/native/android/gradlew" \
  --quiet \
  -p "${android_adapter_dir}" \
  :levixel-uniapp-runtime:clean \
  :levixel-uniapp-runtime:testReleaseUnitTest \
  :levixel-uniapp-runtime:assembleRelease \
  :levixel-uniapp-runtime:copyUniappBundledAars \
  -PlevixelCoreAar="${core_android_aar}"

LEVIXEL_IOS_XCFRAMEWORK_ZIP="${core_ios_zip}" \
  bash "${ios_adapter_dir}/build-runtime-framework.sh" >/dev/null

mkdir -p "${package_root}"
ditto "${source_root}" "${package_root}"
mkdir -p \
  "${package_root}/utssdk/app-android/libs" \
  "${package_root}/utssdk/app-ios/Frameworks"

cp \
  "${android_adapter_dir}/levixel-uniapp-runtime/build/outputs/aar/levixel-uniapp-runtime-release.aar" \
  "${package_root}/utssdk/app-android/libs/LevixelUniRuntime-${version}.aar"
cp \
  "${core_android_aar}" \
  "${package_root}/utssdk/app-android/libs/Levixel-${version}.aar"

photoview_aar="$(find "${android_adapter_dir}/levixel-uniapp-runtime/build/uniapp-bundled-aars" -maxdepth 1 -type f -name '*.aar' -print -quit)"
if [[ -z "${photoview_aar}" ]]; then
  echo "PhotoView AAR was not resolved" >&2
  exit 1
fi
cp "${photoview_aar}" "${package_root}/utssdk/app-android/libs/PhotoView-2.3.0.aar"

ditto \
  "${ios_adapter_dir}/build-runtime/Products/LevixelUniRuntime.framework" \
  "${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework"
ditto \
  "${ios_adapter_dir}/build-runtime/Products/Levixel.framework" \
  "${package_root}/utssdk/app-ios/Frameworks/Levixel.framework"

cp "${plugin_dir}/adapters/uniapp/js_sdk/index.d.ts" "${package_root}/js_sdk/index.d.ts"
cp "${plugin_dir}/LICENSE" "${package_root}/LICENSE"
cp "${plugin_dir}/LICENSE" "${package_root}/license.md"
cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"

cmp "${plugin_dir}/adapters/uniapp/js_sdk/index.js" \
  "${source_root}/js_sdk/canonical.js"
cmp "${source_root}/js_sdk/canonical.js" \
  "${package_root}/js_sdk/canonical.js"

rm -f "${archive_path}" "${archive_path}.sha256" "${marketplace_path}"
(
  cd "${package_root}"
  zip -qry "${archive_path}" .
)
checksum="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${archive_name}" > "${archive_path}.sha256"
sed \
  -e "s/@VERSION@/${version}/g" \
  -e "s/@CHECKSUM@/${checksum}/g" \
  "${marketplace_template}" > "${marketplace_path}"
printf '%s\n' "${archive_path}"
