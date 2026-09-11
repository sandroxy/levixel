#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"

bash "${plugin_dir}/native/ios/verify-viewport-layout.sh"

test_destination_id="$(
  xcrun simctl list devices available --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    device = devices.find do |entry|
      entry.fetch("isAvailable", true) && entry.fetch("name", "").start_with?("iPhone")
    end
    abort("No available iPhone simulator was found for Levixel tests.") unless device
    print device.fetch("udid")
  '
)"
test_destination_arch="$(uname -m)"
if [[ "${test_destination_arch}" != "arm64" && "${test_destination_arch}" != "x86_64" ]]; then
  echo "Unsupported simulator host architecture: ${test_destination_arch}" >&2
  exit 1
fi

test_root="${plugin_dir}/dist/development/ios-source-tests"
test_derived_data="${test_root}/DerivedData"
test_results="${test_root}/latest.xcresult"
for output_path in "${plugin_dir}/dist" "${plugin_dir}/dist/development" \
  "${test_root}" "${test_derived_data}" "${test_results}"; do
  if [[ -L "${output_path}" ]]; then
    echo "iOS source test output must not use a symbolic link: ${output_path}" >&2
    exit 1
  fi
done
mkdir -p "${test_root}"
# Preserve incremental build state, but keep only the latest test result.
if [[ -e "${test_results}" ]]; then
  rm -r "${test_results}"
fi
printf '%s\n' "iOS source test results: ${test_results}"

xcodebuild \
  -quiet \
  test \
  -project "${plugin_dir}/native/ios/Levixel.xcodeproj" \
  -scheme Levixel \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${test_destination_id},arch=${test_destination_arch}" \
  -derivedDataPath "${test_derived_data}" \
  -resultBundlePath "${test_results}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

printf '%s\n' "Verified current iOS source tests."
