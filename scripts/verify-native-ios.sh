#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
host_dir="${repo_root}/ios-plugins-test"
staging_dir="${host_dir}/.artifacts"
xcframework_path="${staging_dir}/Levixel.xcframework"
derived_data="${host_dir}/DerivedData"
swift_package_dir="${plugin_dir}/dist/native-ios/swift-package"

if [[ "${LEVIXEL_SKIP_PACKAGE:-0}" != "1" ]]; then
  "${script_dir}/package-native-ios.sh"
fi

if [[ ! -f "${artifact_path}" || ! -f "${swift_package_dir}/Package.swift" ]]; then
  echo "Packaged iOS artifacts are missing." >&2
  exit 1
fi

rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"
ditto -x -k "${artifact_path}" "${staging_dir}"

if [[ ! -d "${xcframework_path}" ]]; then
  echo "XCFramework was not extracted: ${xcframework_path}" >&2
  exit 1
fi

plutil -lint "${xcframework_path}/Info.plist"

while IFS= read -r framework_path; do
  for legal_file in LICENSE THIRD_PARTY_NOTICES.md PrivacyInfo.xcprivacy; do
    if [[ ! -f "${framework_path}/${legal_file}" ]]; then
      echo "${legal_file} is missing from ${framework_path}" >&2
      exit 1
    fi
  done
  plutil -lint "${framework_path}/PrivacyInfo.xcprivacy"
done < <(find "${xcframework_path}" -type d -name 'Levixel.framework' -print)

while IFS= read -r -d '' packaged_file; do
  if rg -a -n 'Galeria|galeria|com\.chris' "${packaged_file}"; then
    echo "Legacy Galeria identifiers found in packaged iOS runtime content" >&2
    exit 1
  fi
done < <(find "${xcframework_path}" -type f \
  ! -name 'LICENSE' \
  ! -name 'THIRD_PARTY_NOTICES.md' \
  -print0)

swift package dump-package --package-path "${swift_package_dir}" >/dev/null
declared_checksum="$(sed -n 's/.*checksum: "\([0-9a-f]*\)".*/\1/p' "${swift_package_dir}/Package.swift")"
actual_checksum="$(swift package compute-checksum "${artifact_path}")"
if [[ "${declared_checksum}" != "${actual_checksum}" ]]; then
  echo "Swift package checksum does not match ${artifact_path}" >&2
  exit 1
fi

xcodebuild \
  -project "${host_dir}/IosPluginsTest.xcodeproj" \
  -scheme IosPluginsTest \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "${derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  build

embedded_framework="${derived_data}/Build/Products/Debug-iphonesimulator/IosPluginsTest.app/Frameworks/Levixel.framework"
if [[ ! -d "${embedded_framework}" ]]; then
  echo "Levixel.framework was not embedded in the test host" >&2
  exit 1
fi

printf '%s\n' "Verified ${artifact_path}"
