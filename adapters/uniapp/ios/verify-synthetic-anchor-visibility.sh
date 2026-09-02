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
  "${script_dir}/LevixelUniRuntime/LevixelUniSyntheticAnchorVisibility.swift" \
  "${script_dir}/Tests/LevixelUniSyntheticAnchorVisibilityTests.swift" \
  -o "${work_dir}/LevixelUniSyntheticAnchorVisibilityTests"
"${work_dir}/LevixelUniSyntheticAnchorVisibilityTests"

printf '%s\n' "Verified the UniApp iOS synthetic source anchor visibility contract."
