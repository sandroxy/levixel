#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${script_dir}/verify-release-metadata.sh"
LEVIXEL_SKIP_PACKAGE=1 "${script_dir}/verify-native-android.sh"
LEVIXEL_SKIP_PACKAGE=1 "${script_dir}/verify-native-ios.sh"
LEVIXEL_SKIP_PACKAGE=1 "${script_dir}/verify-native-harmonyos.sh"
