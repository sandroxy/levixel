#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
swift_package_dir="${plugin_dir}/dist/native-ios/swift-package"

if [[ "${LEVIXEL_SKIP_PACKAGE:-0}" != "1" ]]; then
  "${script_dir}/package-native-ios.sh"
fi

if [[ ! -f "${artifact_path}" || ! -f "${swift_package_dir}/Package.swift" ]]; then
  echo "Packaged iOS artifacts are missing." >&2
  exit 1
fi

staging_dir="$(mktemp -d)"
trap 'rm -rf "${staging_dir}"' EXIT
xcframework_path="${staging_dir}/Levixel.xcframework"
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
