#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
artifact_checksum_path="${artifact_path}.sha256"
swift_package_path="${plugin_dir}/dist/native-ios/levixel-${version}-swift-package.zip"
swift_package_checksum_path="${swift_package_path}.sha256"

bash "${plugin_dir}/native/ios/verify-viewport-layout.sh"

test_derived_data="$(mktemp -d)"
trap 'rm -rf "${test_derived_data}"' EXIT
xcodebuild \
  -quiet \
  build-for-testing \
  -project "${plugin_dir}/native/ios/Levixel.xcodeproj" \
  -scheme Levixel \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "${test_derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
rm -rf "${test_derived_data}"
trap - EXIT

if [[ "${LEVIXEL_SKIP_PACKAGE:-0}" != "1" ]]; then
  "${script_dir}/package-native-ios.sh"
fi

for packaged_file in \
  "${artifact_path}" \
  "${artifact_checksum_path}" \
  "${swift_package_path}" \
  "${swift_package_checksum_path}"; do
  if [[ ! -f "${packaged_file}" ]]; then
    echo "Packaged iOS artifact is missing: ${packaged_file}" >&2
    exit 1
  fi
done

verify_checksum() {
  local packaged_file="$1"
  local checksum_file="$2"
  local expected_checksum
  local actual_checksum
  expected_checksum="$(awk 'NR == 1 { print $1 }' "${checksum_file}")"
  actual_checksum="$(shasum -a 256 "${packaged_file}" | awk '{ print $1 }')"
  if [[ -z "${expected_checksum}" || "${actual_checksum}" != "${expected_checksum}" ]]; then
    echo "Checksum mismatch for ${packaged_file}" >&2
    exit 1
  fi
}

verify_checksum "${artifact_path}" "${artifact_checksum_path}"
verify_checksum "${swift_package_path}" "${swift_package_checksum_path}"

staging_dir="$(mktemp -d)"
trap 'rm -rf "${staging_dir}"' EXIT
xcframework_path="${staging_dir}/Levixel.xcframework"
swift_package_dir="${staging_dir}/swift-package"
mkdir -p "${swift_package_dir}"
ditto -x -k "${artifact_path}" "${staging_dir}"
ditto -x -k "${swift_package_path}" "${swift_package_dir}"

if [[ ! -f "${swift_package_dir}/Package.swift" ]]; then
  echo "Swift Package archive is missing Package.swift." >&2
  exit 1
fi

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

for legal_file in LICENSE THIRD_PARTY_NOTICES.md README.md; do
  if [[ ! -f "${swift_package_dir}/${legal_file}" ]]; then
    echo "Swift Package archive is missing ${legal_file}." >&2
    exit 1
  fi
done

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
declared_url="$(sed -n 's/.*url: "\([^"]*\)".*/\1/p' "${swift_package_dir}/Package.swift")"
expected_url="https://github.com/sandroxy/levixel/releases/download/${version}/levixel-${version}.xcframework.zip"
if [[ "${declared_url}" != "${expected_url}" ]]; then
  echo "Swift package binary URL is not canonical: ${declared_url}" >&2
  exit 1
fi
declared_checksum="$(sed -n 's/.*checksum: "\([0-9a-f]*\)".*/\1/p' "${swift_package_dir}/Package.swift")"
actual_checksum="$(swift package compute-checksum "${artifact_path}")"
if [[ "${declared_checksum}" != "${actual_checksum}" ]]; then
  echo "Swift package checksum does not match ${artifact_path}" >&2
  exit 1
fi

printf '%s\n' "Verified ${artifact_path}"
