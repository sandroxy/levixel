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
swift_package_name="levixel-${version}-swift-package.zip"
swift_package_path="${artifact_dir}/${swift_package_name}"
swift_package_dir="${artifact_dir}/swift-package"
swift_package_template="${plugin_dir}/packaging/swift-package/Package.swift.template"
binary_url="${LEVIXEL_IOS_BINARY_URL:-https://gitee.com/chrisJxc/integrated-plugins/releases/download/levixel-v${version}/${artifact_name}}"

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

while IFS= read -r framework_path; do
  cp "${plugin_dir}/LICENSE" "${framework_path}/LICENSE"
  cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${framework_path}/THIRD_PARTY_NOTICES.md"
  cp "${ios_dir}/Levixel/PrivacyInfo.xcprivacy" "${framework_path}/PrivacyInfo.xcprivacy"
done < <(find "${xcframework_path}" -type d -name 'Levixel.framework' -print)

mkdir -p "${artifact_dir}"
rm -f \
  "${artifact_path}" \
  "${artifact_path}.sha256" \
  "${swift_package_path}" \
  "${swift_package_path}.sha256"
ditto -c -k --sequesterRsrc --keepParent "${xcframework_path}" "${artifact_path}"

checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${artifact_path}.sha256"
swift_checksum="$(swift package compute-checksum "${artifact_path}")"

rm -rf "${swift_package_dir}"
mkdir -p "${swift_package_dir}"
sed \
  -e "s|@BINARY_URL@|${binary_url}|g" \
  -e "s|@CHECKSUM@|${swift_checksum}|g" \
  "${swift_package_template}" > "${swift_package_dir}/Package.swift"
cp "${plugin_dir}/packaging/swift-package/README.md" "${swift_package_dir}/README.md"
cp "${plugin_dir}/LICENSE" "${swift_package_dir}/LICENSE"
cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${swift_package_dir}/THIRD_PARTY_NOTICES.md"
(
  cd "${swift_package_dir}"
  zip -qry "${swift_package_path}" .
)
swift_package_checksum="$(shasum -a 256 "${swift_package_path}" | awk '{print $1}')"
printf '%s  %s\n' \
  "${swift_package_checksum}" \
  "${swift_package_name}" > "${swift_package_path}.sha256"
printf '%s\n' "${artifact_path}"
printf '%s\n' "${swift_package_path}"
