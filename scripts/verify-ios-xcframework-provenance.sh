#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 4 ]]; then
  echo "Usage: $0 XCFRAMEWORK_OR_ZIP VERSION [EXPECTED_SOURCE_DIGEST] [EXPECTED_SOURCE_COMMIT]" >&2
  exit 1
fi

input="$1"
version="$2"
expected_source_digest="${3:-}"
expected_source_commit="${4:-}"
temporary_dir=""
cleanup() {
  if [[ -n "${temporary_dir}" ]]; then
    rm -rf "${temporary_dir}"
  fi
}
trap cleanup EXIT

if [[ -d "${input}" ]]; then
  xcframework_path="${input}"
elif [[ -f "${input}" ]]; then
  temporary_dir="$(mktemp -d)"
  ditto -x -k "${input}" "${temporary_dir}"
  xcframework_path="${temporary_dir}/Levixel.xcframework"
else
  echo "XCFramework input does not exist: ${input}" >&2
  exit 1
fi

if [[ ! -d "${xcframework_path}" ]]; then
  echo "Levixel.xcframework was not found in ${input}." >&2
  exit 1
fi

framework_count=0
source_commit=""
source_digest=""
while IFS= read -r framework_path; do
  framework_count=$((framework_count + 1))
  info_plist="${framework_path}/Info.plist"
  framework_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}" 2>/dev/null || true)"
  framework_commit="$(/usr/libexec/PlistBuddy -c 'Print :LevixelSourceCommit' "${info_plist}" 2>/dev/null || true)"
  framework_digest="$(/usr/libexec/PlistBuddy -c 'Print :LevixelSourceDigest' "${info_plist}" 2>/dev/null || true)"

  if [[ "${framework_version}" != "${version}" ]]; then
    echo "XCFramework slice version ${framework_version:-<missing>} does not match ${version}: ${framework_path}" >&2
    exit 1
  fi
  if [[ ! "${framework_commit}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "XCFramework slice has no valid LevixelSourceCommit: ${framework_path}" >&2
    exit 1
  fi
  if [[ ! "${framework_digest}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "XCFramework slice has no valid LevixelSourceDigest: ${framework_path}" >&2
    exit 1
  fi

  if [[ -z "${source_commit}" ]]; then
    source_commit="${framework_commit}"
    source_digest="${framework_digest}"
  elif [[ "${framework_commit}" != "${source_commit}" || "${framework_digest}" != "${source_digest}" ]]; then
    echo "XCFramework slices do not share one source provenance." >&2
    exit 1
  fi
done < <(find "${xcframework_path}" -type d -name 'Levixel.framework' -print | LC_ALL=C sort)

if [[ ${framework_count} -ne 2 ]]; then
  echo "XCFramework must contain exactly two Levixel.framework slices; found ${framework_count}." >&2
  exit 1
fi
if [[ -n "${expected_source_digest}" && "${source_digest}" != "${expected_source_digest}" ]]; then
  echo "XCFramework source digest does not match the current iOS build inputs." >&2
  echo "Expected: ${expected_source_digest}" >&2
  echo "Actual:   ${source_digest}" >&2
  exit 1
fi
if [[ -n "${expected_source_commit}" && "${source_commit}" != "${expected_source_commit}" ]]; then
  echo "XCFramework source commit does not match the current release source." >&2
  echo "Expected: ${expected_source_commit}" >&2
  echo "Actual:   ${source_commit}" >&2
  exit 1
fi

printf '%s %s\n' "${source_commit}" "${source_digest}"
