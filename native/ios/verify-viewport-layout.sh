#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

xcrun swiftc \
  -warnings-as-errors \
  "${script_dir}/Levixel/Viewer/LevixelImageViewportLayout.swift" \
  "${script_dir}/Tests/LevixelImageViewportLayoutTests.swift" \
  -o "${work_dir}/LevixelImageViewportLayoutTests"
"${work_dir}/LevixelImageViewportLayoutTests"

printf '%s\n' "Verified the iOS image viewport layout contract."
