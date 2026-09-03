#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

xcrun swiftc \
  -warnings-as-errors \
  "${script_dir}/LevixelUniRuntime/LevixelUniSourceGeometry.swift" \
  "${script_dir}/Tests/LevixelUniSourceGeometryTests.swift" \
  -o "${work_dir}/LevixelUniSourceGeometryTests"
"${work_dir}/LevixelUniSourceGeometryTests"

printf '%s\n' "Verified the UniApp iOS source/viewport intersection contract."
