#!/usr/bin/env bash
set -euo pipefail

target="${1:-all}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
host_dir="${repo_root}/react-native-plugins-test"

case "${target}" in
  android|ios|all) ;;
  *)
    echo "Usage: $0 [android|ios|all]" >&2
    exit 1
    ;;
esac

"${script_dir}/package-react-native.sh"

corepack pnpm@9.12.3 --dir "${host_dir}" install --force
corepack pnpm@9.12.3 --dir "${host_dir}" typecheck

if [[ "${target}" == "android" || "${target}" == "all" ]]; then
  corepack pnpm@9.12.3 --dir "${host_dir}" exec expo prebuild --clean --platform android
  "${host_dir}/android/gradlew" -p "${host_dir}/android" :app:assembleDebug
fi

if [[ "${target}" == "ios" || "${target}" == "all" ]]; then
  corepack pnpm@9.12.3 --dir "${host_dir}" exec expo prebuild --clean --platform ios
  xcodebuild \
    -workspace "${host_dir}/ios/IntegratedPlugins.xcworkspace" \
    -scheme IntegratedPlugins \
    -configuration Debug \
    -destination "generic/platform=iOS Simulator" \
    -derivedDataPath "${host_dir}/.expo/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

printf '%s\n' "Verified React Native ${target} artifact"
