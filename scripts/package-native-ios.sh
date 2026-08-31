#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
ios_dir="${plugin_dir}/native/ios"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
"${script_dir}/assert-release-version-available.sh" "${version}" --check-origin
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
binary_url="${LEVIXEL_IOS_BINARY_URL:-https://github.com/sandroxy/levixel/releases/download/${version}/${artifact_name}}"
accepted_xcframework_zip="${LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_ZIP:-}"
accepted_xcframework_sha256="${LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_SHA256:-}"

mkdir -p "${artifact_dir}"
rm -f \
  "${artifact_path}.sha256" \
  "${swift_package_path}" \
  "${swift_package_path}.sha256"

if [[ -n "${accepted_xcframework_zip}" ]]; then
  if [[ ! -f "${accepted_xcframework_zip}" ]]; then
    echo "Accepted iOS candidate does not exist: ${accepted_xcframework_zip}" >&2
    exit 1
  fi
  if [[ ! "${accepted_xcframework_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_SHA256 must contain the accepted candidate SHA-256." >&2
    exit 1
  fi

  actual_accepted_sha256="$(shasum -a 256 "${accepted_xcframework_zip}" | awk '{print $1}')"
  if [[ "${actual_accepted_sha256}" != "${accepted_xcframework_sha256}" ]]; then
    echo "Accepted iOS candidate SHA-256 mismatch." >&2
    echo "Expected: ${accepted_xcframework_sha256}" >&2
    echo "Actual:   ${actual_accepted_sha256}" >&2
    exit 1
  fi

  inspection_dir="$(mktemp -d)"
  trap 'rm -rf "${inspection_dir}"' EXIT
  ditto -x -k "${accepted_xcframework_zip}" "${inspection_dir}"
  accepted_xcframework="${inspection_dir}/Levixel.xcframework"
  if [[ ! -d "${accepted_xcframework}" ]]; then
    echo "Accepted iOS candidate does not contain Levixel.xcframework." >&2
    exit 1
  fi

  framework_count=0
  while IFS= read -r framework_path; do
    framework_count=$((framework_count + 1))
    framework_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${framework_path}/Info.plist")"
    if [[ "${framework_version}" != "${version}" ]]; then
      echo "Accepted framework version ${framework_version} does not match ${version}: ${framework_path}" >&2
      exit 1
    fi
    for legal_file in LICENSE THIRD_PARTY_NOTICES.md PrivacyInfo.xcprivacy; do
      if [[ ! -f "${framework_path}/${legal_file}" ]]; then
        echo "Accepted framework is missing ${legal_file}: ${framework_path}" >&2
        exit 1
      fi
    done
    cmp "${plugin_dir}/LICENSE" "${framework_path}/LICENSE"
    cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${framework_path}/THIRD_PARTY_NOTICES.md"
    cmp "${ios_dir}/Levixel/PrivacyInfo.xcprivacy" "${framework_path}/PrivacyInfo.xcprivacy"
  done < <(find "${accepted_xcframework}" -type d -name 'Levixel.framework' -print)
  if [[ ${framework_count} -ne 2 ]]; then
    echo "Accepted XCFramework must contain exactly two Levixel.framework slices; found ${framework_count}." >&2
    exit 1
  fi

  accepted_absolute="$(cd "$(dirname "${accepted_xcframework_zip}")" && pwd)/$(basename "${accepted_xcframework_zip}")"
  artifact_absolute="$(cd "${artifact_dir}" && pwd)/${artifact_name}"
  if [[ "${accepted_absolute}" != "${artifact_absolute}" ]]; then
    rm -f "${artifact_path}"
    cp "${accepted_xcframework_zip}" "${artifact_path}"
  fi
  rm -rf "${inspection_dir}"
  trap - EXIT
else
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

  rm -f "${artifact_path}"
  ditto -c -k --sequesterRsrc --keepParent "${xcframework_path}" "${artifact_path}"
fi

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
