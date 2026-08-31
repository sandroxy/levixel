#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${script_dir}/verify-release-readiness.sh"
"${script_dir}/verify-native-android.sh"
"${script_dir}/verify-native-ios.sh"
"${script_dir}/verify-native-harmonyos.sh"
