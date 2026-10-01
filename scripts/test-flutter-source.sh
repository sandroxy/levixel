#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -gt 1 || "${1:-dart}" != dart ]]; then
  echo "Usage: $0 [dart]" >&2
  exit 1
fi
cd "${script_dir}/../adapters/flutter"
flutter pub get
result=0
dart format --output=none --set-exit-if-changed lib test || result=1
flutter analyze --fatal-infos || result=1
flutter test --timeout 60s || result=1
exit "${result}"
