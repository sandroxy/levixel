#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
react_native_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "${plugin_dir}/adapters/react-native/package.json")"
harmony_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("version")' "${plugin_dir}/native/harmonyos/levixel/oh-package.json5")"
uniapp_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("version")' "${plugin_dir}/uni_modules/Sandrox-Levixel/package.json")"
harmony_app_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("app").fetch("versionName")' "${plugin_dir}/native/harmonyos/AppScope/app.json5")"

"${script_dir}/sync-uniapp-canonical-js.sh" --check

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid Levixel semantic version: ${version}" >&2
  exit 1
fi

if [[ "${react_native_version}" != "${version}" ]]; then
  echo "React Native version ${react_native_version} does not match ${version}." >&2
  exit 1
fi

if [[ "${harmony_version}" != "${version}" ]]; then
  echo "HarmonyOS version ${harmony_version} does not match ${version}." >&2
  exit 1
fi

if [[ "${uniapp_version}" != "${version}" ]]; then
  echo "UniApp UTS version ${uniapp_version} does not match ${version}." >&2
  exit 1
fi

if [[ "${harmony_app_version}" != "${version}" ]]; then
  echo "HarmonyOS app version ${harmony_app_version} does not match ${version}." >&2
  exit 1
fi

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  version = ARGV.fetch(1)
  android = package.dig("uni_modules", "platforms", "client", "uni-app", "app", "android", "extVersion")
  ios = package.dig("uni_modules", "platforms", "client", "uni-app", "app", "ios", "extVersion")
  abort("UniApp Android extVersion #{android.inspect} does not match #{version}") unless android == version
  abort("UniApp iOS extVersion #{ios.inspect} does not match #{version}") unless ios == version
' "${plugin_dir}/uni_modules/Sandrox-Levixel/package.json" "${version}"

ios_versions="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' \
  "${plugin_dir}/native/ios/Levixel.xcodeproj/project.pbxproj" | sort -u)"
if [[ "${ios_versions}" != "${version}" ]]; then
  echo "iOS marketing version does not match ${version}: ${ios_versions}" >&2
  exit 1
fi

uniapp_ios_versions="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' \
  "${plugin_dir}/adapters/uniapp/ios/LevixelUniApp.xcodeproj/project.pbxproj" | sort -u)"
if [[ "${uniapp_ios_versions}" != "${version}" ]]; then
  echo "UniApp iOS marketing version does not match ${version}: ${uniapp_ios_versions}" >&2
  exit 1
fi

swift_package_url="$(sed -n 's/.*url: "\([^"]*\)".*/\1/p' "${plugin_dir}/Package.swift")"
expected_swift_package_url="https://github.com/sandroxy/levixel/releases/download/${version}/levixel-${version}.xcframework.zip"
if [[ "${swift_package_url}" != "${expected_swift_package_url}" ]]; then
  echo "Root Swift Package URL does not match ${version}: ${swift_package_url}" >&2
  exit 1
fi
swift_package_checksum="$(sed -n 's/.*checksum: "\([0-9a-f]*\)".*/\1/p' "${plugin_dir}/Package.swift")"
if [[ ! "${swift_package_checksum}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Root Swift Package checksum is invalid: ${swift_package_checksum}" >&2
  exit 1
fi
ios_artifact="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
if [[ -f "${ios_artifact}" ]]; then
  actual_ios_checksum="$(swift package compute-checksum "${ios_artifact}")"
  if [[ "${swift_package_checksum}" != "${actual_ios_checksum}" ]]; then
    echo "Root Swift Package checksum does not match ${ios_artifact}." >&2
    exit 1
  fi
fi

if ! ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  version = manifest.fetch("version")
  targets = manifest.fetch("targets")
  outputs = targets.flat_map { |target| target.fetch("artifacts") }.map { |artifact| artifact.fetch("output") }
  missing = outputs.reject { |output| output.include?(version) }
  abort("Artifact paths missing version #{version}: #{missing.join(", ")}") unless missing.empty?
  uniapp = targets.find { |target| target.fetch("id") == "uniapp" }
  abort("UniApp target is missing") unless uniapp
  expected_source_root = "uni_modules/Sandrox-Levixel"
  actual_source_root = uniapp.fetch("sourceRoot")
  abort("UniApp sourceRoot must be #{expected_source_root}, got #{actual_source_root}") unless actual_source_root == expected_source_root
  abort("UniApp sourceRoot does not exist: #{actual_source_root}") unless File.directory?(File.join(ARGV.fetch(1), actual_source_root))
' "${plugin_dir}/plugin.yaml" "${plugin_dir}"; then
  exit 1
fi

cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" \
  "${plugin_dir}/native/harmonyos/levixel/THIRD_PARTY_NOTICES.md"
cmp "${plugin_dir}/LICENSE" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/LICENSE"
cmp "${plugin_dir}/LICENSE" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/license.md"
cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/THIRD_PARTY_NOTICES.md"

expected_harmony_license="$(mktemp)"
trap 'rm -f "${expected_harmony_license}"' EXIT
{
  cat "${plugin_dir}/LICENSE"
  printf '\n'
  cat "${plugin_dir}/THIRD_PARTY_NOTICES.md"
} > "${expected_harmony_license}"
cmp "${expected_harmony_license}" "${plugin_dir}/native/harmonyos/levixel/LICENSE"

for required_notice in \
  'Copyright (c) 2025 Fernando Rojo' \
  'Copyright (c) 2013 Michael Henry Pantaleon'; do
  if ! grep -Fq "${required_notice}" "${plugin_dir}/THIRD_PARTY_NOTICES.md"; then
    echo "Required upstream notice is missing: ${required_notice}" >&2
    exit 1
  fi
done

if rg -n -i 'galeria|nandorojo|com\.chris' \
  "${plugin_dir}/native/android/levixel/src" \
  "${plugin_dir}/native/ios/Levixel/Viewer" \
  "${plugin_dir}/native/harmonyos/levixel/src" \
  "${plugin_dir}/adapters/react-native/src" \
  "${plugin_dir}/adapters/react-native/android/src" \
  "${plugin_dir}/adapters/react-native/ios" \
  "${plugin_dir}/adapters/uniapp/android/levixel-uniapp/src/main" \
  "${plugin_dir}/adapters/uniapp/android/levixel-uniapp-runtime/src/main" \
  "${plugin_dir}/adapters/uniapp/ios/LevixelUniApp" \
  "${plugin_dir}/adapters/uniapp/ios/LevixelUniRuntime" \
  "${plugin_dir}/adapters/uniapp/js_sdk/index.js" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/utssdk" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/js_sdk"; then
  echo "Legacy Galeria identifiers remain in runtime source." >&2
  exit 1
fi

if ! rg -q "from './canonical.js'" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/js_sdk/index.js"; then
  echo "UniApp UTS JavaScript wrapper is not linked to its checked-in canonical module." >&2
  exit 1
fi
node --input-type=module --check < \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/js_sdk/index.js"
node --input-type=module --check < \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/js_sdk/canonical.js"

plutil -lint "${plugin_dir}/native/ios/Levixel/PrivacyInfo.xcprivacy" >/dev/null
printf '%s\n' "Levixel ${version} release metadata is consistent."
