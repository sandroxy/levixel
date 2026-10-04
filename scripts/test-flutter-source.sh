#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -gt 1 || ( "${1:-dart}" != dart && "${1:-dart}" != ios ) ]]; then
  echo "Usage: $0 [dart|ios]" >&2
  exit 1
fi
cd "${script_dir}/../adapters/flutter"
if [[ "${1:-dart}" == ios ]]; then
  work_dir="$(mktemp -d)"
  trap 'rm -rf "${work_dir}"' EXIT
  xcrun swiftc -warnings-as-errors \
    ios/sandrox_levixel/Sources/sandrox_levixel/SourceHandoffs.swift \
    test/ios/SourceHandoffsTests.swift -o "${work_dir}/SourceHandoffsTests"
  "${work_dir}/SourceHandoffsTests"
  exit 0
fi
flutter pub get
result=0
dart format --output=none --set-exit-if-changed lib test || result=1
flutter analyze --fatal-infos || result=1
flutter test --timeout 60s || result=1
exit "${result}"
