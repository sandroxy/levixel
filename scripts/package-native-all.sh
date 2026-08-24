#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${script_dir}/verify-release-metadata.sh"
"${script_dir}/package-native-android.sh"
"${script_dir}/package-native-ios.sh"
"${script_dir}/package-native-harmonyos.sh"
