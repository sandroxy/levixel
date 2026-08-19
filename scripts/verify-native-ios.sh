#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
host_dir="${repo_root}/ios-plugins-test"
staging_dir="${host_dir}/.artifacts"
xcframework_path="${staging_dir}/Levixel.xcframework"
derived_data="${host_dir}/DerivedData"

"${script_dir}/package-native-ios.sh"

rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"
ditto -x -k "${artifact_path}" "${staging_dir}"

if [[ ! -d "${xcframework_path}" ]]; then
  echo "XCFramework was not extracted: ${xcframework_path}" >&2
  exit 1
fi

plutil -lint "${xcframework_path}/Info.plist"

if rg -n 'Galeria|galeria|com\.chris' "${xcframework_path}"; then
  echo "Legacy Galeria identifiers found in packaged iOS artifact" >&2
  exit 1
fi

xcodebuild \
  -project "${host_dir}/IosPluginsTest.xcodeproj" \
  -scheme IosPluginsTest \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "${derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  build

embedded_framework="${derived_data}/Build/Products/Debug-iphonesimulator/IosPluginsTest.app/Frameworks/Levixel.framework"
if [[ ! -d "${embedded_framework}" ]]; then
  echo "Levixel.framework was not embedded in the test host" >&2
  exit 1
fi

printf '%s\n' "Verified ${artifact_path}"
