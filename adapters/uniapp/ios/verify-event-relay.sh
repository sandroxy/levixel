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
  "${script_dir}/LevixelUniRuntime/LevixelUniJSONEventRelay.swift" \
  "${script_dir}/Tests/LevixelUniJSONEventRelayTests.swift" \
  -o "${work_dir}/LevixelUniJSONEventRelayTests"
"${work_dir}/LevixelUniJSONEventRelayTests"

printf '%s\n' "Verified the UniApp iOS JSON event relay replacement contract."
