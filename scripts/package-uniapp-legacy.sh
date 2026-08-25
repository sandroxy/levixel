#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
dcloud_android_aar="${DCLOUD_ANDROID_UNIAPP_AAR:-}"
dcloud_ios_sdk_root="${DCLOUD_IOS_SDK_ROOT:-}"
android_adapter_dir="${plugin_dir}/adapters/uniapp/android"
ios_adapter_dir="${plugin_dir}/adapters/uniapp/ios"
artifact_dir="${plugin_dir}/dist/uniapp"
package_id="Sandrox-Levixel"
package_root="${artifact_dir}/package/${package_id}"
archive_name="levixel-uniapp-legacy-${version}.zip"
archive_path="${artifact_dir}/${archive_name}"
core_android_aar="${plugin_dir}/dist/native-android/levixel-${version}.aar"
core_ios_zip="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"

if [[ -z "${dcloud_android_aar}" || ! -f "${dcloud_android_aar}" ]]; then
  echo "Set DCLOUD_ANDROID_UNIAPP_AAR to uniapp-v8-release.aar" >&2
  exit 1
fi
if [[ -z "${dcloud_ios_sdk_root}" || ! -f "${dcloud_ios_sdk_root}/SDK/inc/DCUni/DCUniModule.h" ]]; then
  echo "Set DCLOUD_IOS_SDK_ROOT to the DCloud iOS offline SDK root" >&2
  exit 1
fi

if [[ "${LEVIXEL_SKIP_NATIVE_PACKAGE:-0}" != "1" ]]; then
  "${script_dir}/package-native-android.sh"
  "${script_dir}/package-native-ios.sh"
fi

if [[ ! -f "${core_android_aar}" || ! -f "${core_ios_zip}" ]]; then
  echo "Canonical native artifacts for Levixel ${version} are missing" >&2
  exit 1
fi

"${plugin_dir}/native/android/gradlew" \
  --quiet \
  -p "${android_adapter_dir}" \
  :levixel-uniapp-runtime:clean \
  :levixel-uniapp-runtime:testReleaseUnitTest \
  :levixel-uniapp-runtime:assembleRelease \
  :levixel-uniapp-runtime:copyUniappBundledAars \
  :levixel-uniapp:clean \
  :levixel-uniapp:assembleRelease \
  -PlevixelCoreAar="${core_android_aar}" \
  -PdcloudUniappAar="${dcloud_android_aar}"

DCLOUD_IOS_SDK_ROOT="${dcloud_ios_sdk_root}" \
LEVIXEL_IOS_XCFRAMEWORK_ZIP="${core_ios_zip}" \
  "${ios_adapter_dir}/build-framework.sh" >/dev/null

rm -rf "${artifact_dir}/package"
mkdir -p "${package_root}/android" "${package_root}/ios" "${package_root}/js_sdk"

cp \
  "${android_adapter_dir}/levixel-uniapp/build/outputs/aar/levixel-uniapp-release.aar" \
  "${package_root}/android/LevixelUniApp-release.aar"
cp \
  "${android_adapter_dir}/levixel-uniapp-runtime/build/outputs/aar/levixel-uniapp-runtime-release.aar" \
  "${package_root}/android/LevixelUniRuntime-${version}.aar"
cp "${core_android_aar}" "${package_root}/android/Levixel-${version}.aar"

photoview_aar="$(find "${android_adapter_dir}/levixel-uniapp-runtime/build/uniapp-bundled-aars" -maxdepth 1 -type f -name '*.aar' -print -quit)"
if [[ -z "${photoview_aar}" ]]; then
  echo "PhotoView AAR was not resolved" >&2
  exit 1
fi
cp "${photoview_aar}" "${package_root}/android/PhotoView-2.3.0.aar"

ditto \
  "${ios_adapter_dir}/build/Products/LevixelUniApp.framework" \
  "${package_root}/ios/LevixelUniApp.framework"
ditto \
  "${ios_adapter_dir}/build/Products/LevixelUniRuntime.framework" \
  "${package_root}/ios/LevixelUniRuntime.framework"
ditto \
  "${ios_adapter_dir}/build/Products/Levixel.framework" \
  "${package_root}/ios/Levixel.framework"

cp "${plugin_dir}/adapters/uniapp/js_sdk/index.js" "${package_root}/js_sdk/index.js"
cp "${plugin_dir}/adapters/uniapp/js_sdk/index.d.ts" "${package_root}/js_sdk/index.d.ts"
sed "s|@VERSION@|${version}|g" \
  "${plugin_dir}/adapters/uniapp/package.json.template" > "${package_root}/package.json"
cp "${plugin_dir}/LICENSE" "${package_root}/LICENSE"
cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"

rm -f "${archive_path}" "${archive_path}.sha256"
(
  cd "${artifact_dir}/package"
  zip -qry "${archive_path}" "${package_id}"
)
checksum="$(shasum -a 256 "${archive_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${archive_name}" > "${archive_path}.sha256"
printf '%s\n' "${archive_path}"
