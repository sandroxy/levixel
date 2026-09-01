#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
artifact_only=0
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [--artifact-only]" >&2
  exit 1
fi
if [[ $# -eq 1 ]]; then
  if [[ "$1" != "--artifact-only" ]]; then
    echo "Usage: $0 [--artifact-only]" >&2
    exit 1
  fi
  artifact_only=1
fi

version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
artifact_checksum_path="${artifact_path}.sha256"
swift_package_path="${plugin_dir}/dist/native-ios/levixel-${version}-swift-package.zip"
swift_package_checksum_path="${swift_package_path}.sha256"

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

if [[ ${artifact_only} -eq 0 ]]; then
  "${script_dir}/test-native-ios-source.sh"
fi

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

source_digest="$("${script_dir}/compute-ios-source-digest.rb")"
source_commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
read -r artifact_source_commit artifact_source_digest < <(
  "${script_dir}/verify-ios-xcframework-provenance.sh" \
    "${artifact_path}" "${version}" "${source_digest}"
)
if ! git -C "${plugin_dir}" cat-file -e "${artifact_source_commit}^{commit}" 2>/dev/null \
    || ! git -C "${plugin_dir}" merge-base --is-ancestor "${artifact_source_commit}" "${source_commit}"; then
  echo "XCFramework source commit ${artifact_source_commit} is not an ancestor of ${source_commit}." >&2
  exit 1
fi
if [[ -z "$(git -C "${plugin_dir}" status --porcelain)" ]]; then
  committed_source_digest="$(
    "${script_dir}/compute-ios-source-digest.rb" --commit "${artifact_source_commit}"
  )"
  if [[ "${committed_source_digest}" != "${artifact_source_digest}" ]]; then
    echo "XCFramework source digest does not belong to its embedded source commit." >&2
    exit 1
  fi
fi

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
  if grep -a -n -E 'Galeria|galeria|com\.chris' "${packaged_file}"; then
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

if [[ ${artifact_only} -eq 0 ]]; then
  "${script_dir}/verify-ios-readme-api.sh" "${artifact_path}"
  "${script_dir}/verify-ios-core-adapter-api.sh" "${artifact_path}"
fi

printf '%s\n' "Verified ${artifact_path}"
printf '%s\n' "  source commit: ${artifact_source_commit}"
printf '%s\n' "  source digest: ${artifact_source_digest}"
