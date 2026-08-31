#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/../../.." && pwd)"
dcloud_sdk_root="${DCLOUD_IOS_SDK_ROOT:-}"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
core_artifact="${LEVIXEL_IOS_XCFRAMEWORK_ZIP:-${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip}"
build_root="${script_dir}/build"
bridge_derived_data="${build_root}/BridgeDerivedData"
core_artifact_dir="${build_root}/CoreArtifact"
core_framework_dir="${core_artifact_dir}/Levixel.xcframework/ios-arm64"
bridge_framework="${bridge_derived_data}/Build/Products/Release-iphoneos/LevixelUniApp.framework"
runtime_framework="${bridge_derived_data}/Build/Products/Release-iphoneos/LevixelUniRuntime.framework"
output_dir="${build_root}/Products"

if [[ -z "${dcloud_sdk_root}" || ! -f "${dcloud_sdk_root}/SDK/inc/DCUni/DCUniModule.h" ]]; then
  echo "Set DCLOUD_IOS_SDK_ROOT to the DCloud iOS offline SDK root" >&2
  exit 1
fi
if [[ ! -f "${core_artifact}" ]]; then
  echo "Levixel iOS artifact not found: ${core_artifact}" >&2
  exit 1
fi

bash "${plugin_dir}/scripts/verify-ios-core-adapter-api.sh" "${core_artifact}"

rm -rf "${build_root}"
mkdir -p "${core_artifact_dir}"
ditto -x -k "${core_artifact}" "${core_artifact_dir}"

if [[ ! -d "${core_framework_dir}/Levixel.framework" ]]; then
  echo "The iOS device framework is missing from ${core_artifact}" >&2
  exit 1
fi

xcodebuild \
  -quiet \
  -project "${script_dir}/LevixelUniApp.xcodeproj" \
  -scheme LevixelUniApp \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${bridge_derived_data}" \
  DCLOUD_IOS_SDK_ROOT="${dcloud_sdk_root}" \
  LEVIXEL_FRAMEWORKS_DIR="${core_framework_dir}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  clean build

if [[ ! -d "${bridge_framework}" ]]; then
  echo "Framework was not produced: ${bridge_framework}" >&2
  exit 1
fi
if [[ ! -d "${runtime_framework}" ]]; then
  echo "Framework was not produced: ${runtime_framework}" >&2
  exit 1
fi

mkdir -p "${output_dir}"
rm -rf \
  "${output_dir}/LevixelUniApp.framework" \
  "${output_dir}/LevixelUniRuntime.framework" \
  "${output_dir}/Levixel.framework"
ditto "${bridge_framework}" "${output_dir}/LevixelUniApp.framework"
ditto "${runtime_framework}" "${output_dir}/LevixelUniRuntime.framework"
ditto "${core_framework_dir}/Levixel.framework" "${output_dir}/Levixel.framework"

printf '%s\n' "${output_dir}"
