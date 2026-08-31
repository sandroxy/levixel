#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"

bash "${plugin_dir}/native/ios/verify-viewport-layout.sh"

test_derived_data="$(mktemp -d)"
trap 'rm -rf "${test_derived_data}"' EXIT

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

xcodebuild \
  -quiet \
  test \
  -project "${plugin_dir}/native/ios/Levixel.xcodeproj" \
  -scheme Levixel \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=${test_destination_id},arch=${test_destination_arch}" \
  -derivedDataPath "${test_derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

printf '%s\n' "Verified current iOS source tests."
