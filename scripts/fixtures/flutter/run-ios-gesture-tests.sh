#!/usr/bin/env bash
set -euo pipefail

host_dir="${1:?Provide the generated Flutter source-test host}"
work_dir="${2:?Provide the source-test output directory}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${host_dir}"
arguments=(-quiet -workspace ios/Runner.xcworkspace -scheme NativeGestures -configuration Debug
  -destination "platform=iOS Simulator,id=${LEVIXEL_FLUTTER_DEVICE},arch=$(uname -m)"
  -derivedDataPath "${work_dir}/DerivedData" -parallel-testing-enabled NO
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120
  -maximum-test-execution-time-allowance 180 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
xcodebuild build-for-testing "${arguments[@]}"
bash "${script_dir}/record-gestures.sh" ios "${work_dir}/native-gestures.mp4" \
  xcodebuild test-without-building "${arguments[@]}" -resultBundlePath "${work_dir}/gestures.xcresult"
