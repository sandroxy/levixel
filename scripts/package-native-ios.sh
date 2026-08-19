#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
ios_dir="${plugin_dir}/native/ios"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
build_dir="${ios_dir}/build"
device_archive="${build_dir}/Levixel-iOS.xcarchive"
simulator_archive="${build_dir}/Levixel-Simulator.xcarchive"
xcframework_path="${build_dir}/Levixel.xcframework"
artifact_name="levixel-${version}.xcframework.zip"
artifact_dir="${plugin_dir}/dist/native-ios"
artifact_path="${artifact_dir}/${artifact_name}"

rm -rf "${build_dir}"
mkdir -p "${build_dir}"

xcodebuild archive \
  -project "${ios_dir}/Levixel.xcodeproj" \
  -scheme Levixel \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "${device_archive}" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  MARKETING_VERSION="${version}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

xcodebuild archive \
  -project "${ios_dir}/Levixel.xcodeproj" \
  -scheme Levixel \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -archivePath "${simulator_archive}" \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  MARKETING_VERSION="${version}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

xcodebuild -create-xcframework \
  -framework "${device_archive}/Products/Library/Frameworks/Levixel.framework" \
  -framework "${simulator_archive}/Products/Library/Frameworks/Levixel.framework" \
  -output "${xcframework_path}"

mkdir -p "${artifact_dir}"
rm -f "${artifact_path}" "${artifact_path}.sha256"
ditto -c -k --sequesterRsrc --keepParent "${xcframework_path}" "${artifact_path}"

checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${artifact_path}.sha256"
printf '%s\n' "${artifact_path}"
