#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
react_native_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "${plugin_dir}/adapters/react-native/package.json")"
harmony_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("version")' "${plugin_dir}/native/harmonyos/levixel/oh-package.json5")"
android_host_version="$(ruby -e '
  source = File.read(ARGV.fetch(0))
  match = source.match(/def levixelVersion = .*getOrElse\("([^"]+)"\)/)
  abort("Android test host does not declare a default Levixel version.") unless match
  print match[1]
' "${repo_root}/android-plugins-test/app/build.gradle")"
harmony_host_version="$(ruby -rjson -e '
  packages = JSON.parse(File.read(ARGV.fetch(0))).fetch("packages").values
  package = packages.find { |entry| entry["name"] == "@sandrox/levixel" }
  abort("HarmonyOS test host does not lock @sandrox/levixel.") unless package
  print package.fetch("version")
' "${repo_root}/harmonyos-plugins-test/entry/oh-package-lock.json5")"

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

if [[ "${android_host_version}" != "${version}" ]]; then
  echo "Android test host version ${android_host_version} does not match ${version}." >&2
  exit 1
fi

if [[ "${harmony_host_version}" != "${version}" ]]; then
  echo "HarmonyOS test host version ${harmony_host_version} does not match ${version}." >&2
  exit 1
fi

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

if ! ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  version = manifest.fetch("version")
  outputs = manifest.fetch("targets").flat_map { |target| target.fetch("artifacts") }.map { |artifact| artifact.fetch("output") }
  missing = outputs.reject { |output| output.include?(version) }
  abort("Artifact paths missing version #{version}: #{missing.join(", ")}") unless missing.empty?
' "${plugin_dir}/plugin.yaml"; then
  exit 1
fi

cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" \
  "${plugin_dir}/native/harmonyos/levixel/THIRD_PARTY_NOTICES.md"

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
  "${plugin_dir}/adapters/uniapp/ios/LevixelUniApp" \
  "${plugin_dir}/adapters/uniapp/js_sdk/index.js"; then
  echo "Legacy Galeria identifiers remain in runtime source." >&2
  exit 1
fi

plutil -lint "${plugin_dir}/native/ios/Levixel/PrivacyInfo.xcprivacy" >/dev/null
printf '%s\n' "Levixel ${version} release metadata is consistent."
