#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
read -r uniapp_target_version uniapp_native_version _ uniapp_legacy_version resolved_root_version < <(
  bash "${script_dir}/resolve-uniapp-product.sh" "${plugin_dir}/plugin.yaml"
)
web_version="$(ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  target = manifest.fetch("targets").find { |entry| entry.fetch("id") == "web" }
  abort("Web target is missing from plugin.yaml") unless target
  print target.fetch("version", manifest.fetch("version"))
' "${plugin_dir}/plugin.yaml")"
react_native_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "${plugin_dir}/adapters/react-native/package.json")"
harmony_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("version")' "${plugin_dir}/native/harmonyos/levixel/oh-package.json5")"
uniapp_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("version")' "${plugin_dir}/uni_modules/Sandrox-Levixel/package.json")"
harmony_app_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("app").fetch("versionName")' "${plugin_dir}/native/harmonyos/AppScope/app.json5")"

node -e '
  const packageJson = require(process.argv[1])
  const expectedVersion = process.argv[2]
  if (packageJson.name !== "@sandrox/levixel-web")
    throw new Error(`Unexpected Web package name: ${packageJson.name}`)
  if (packageJson.version !== expectedVersion)
    throw new Error(`Web package version ${packageJson.version} does not match ${expectedVersion}`)
  if (packageJson.private === true)
    throw new Error("The accepted Web package must not remain private")
  if (packageJson.publishConfig?.access !== "public")
    throw new Error("The Web package must publish publicly")
  if (packageJson.publishConfig?.registry !== "https://registry.npmjs.org/")
    throw new Error("The Web package must use the public npm registry")
  if (Object.keys(packageJson.dependencies ?? {}).length !== 0)
    throw new Error("The Web package must not add runtime dependencies")
  const lifecycle = Object.keys(packageJson.scripts ?? {}).filter(name =>
    /^(preinstall|install|postinstall|prepublish|prepare)$/.test(name))
  if (lifecycle.length !== 0)
    throw new Error(`Unexpected Web lifecycle scripts: ${lifecycle.join(", ")}`)
' "${plugin_dir}/adapters/web/package.json" "${web_version}"

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

if [[ "${resolved_root_version}" != "${version}" ]]; then
  echo "Resolved root version ${resolved_root_version} does not match ${version}." >&2
  exit 1
fi

if [[ "${uniapp_version}" != "${uniapp_target_version}" ]]; then
  echo "UniApp UTS version ${uniapp_version} does not match target ${uniapp_target_version}." >&2
  exit 1
fi

if [[ "${uniapp_native_version}" != "${version}" || "${uniapp_legacy_version}" != "${version}" ]]; then
  echo "UniApp native provenance and legacy product must remain at root version ${version}." >&2
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
  x_android = package.dig("uni_modules", "platforms", "client", "uni-app-x", "app", "android", "extVersion")
  x_ios = package.dig("uni_modules", "platforms", "client", "uni-app-x", "app", "ios", "extVersion")
  abort("DCloud permits at most five keywords") unless package.fetch("keywords").length <= 5
  abort("UniApp Android extVersion #{android.inspect} does not match #{version}") unless android == version
  abort("UniApp iOS extVersion #{ios.inspect} does not match #{version}") unless ios == version
  abort("UniApp x Android extVersion #{x_android.inspect} does not match #{version}") unless x_android == version
  abort("UniApp x iOS extVersion #{x_ios.inspect} does not match #{version}") unless x_ios == version
  abort("UniApp x Android minimum must be API 23") unless package.dig("uni_modules", "platforms", "client", "uni-app-x", "app", "android", "minVersion") == "23"
  abort("UniApp x iOS minimum must be 15.0") unless package.dig("uni_modules", "platforms", "client", "uni-app-x", "app", "ios", "minVersion") == "15.0"
' "${plugin_dir}/uni_modules/Sandrox-Levixel/package.json" "${uniapp_target_version}"

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
  default_version = manifest.fetch("version")
  targets = manifest.fetch("targets")
  missing = targets.flat_map do |target|
    target_version = target.fetch("version", default_version)
    target.fetch("artifacts").map do |artifact|
      output = artifact.fetch("output")
      "#{target.fetch("id")}:#{output}" unless output.include?(target_version)
    end.compact
  end
  abort("Artifact paths missing their target version: #{missing.join(", ")}") unless missing.empty?
  uniapp = targets.find { |target| target.fetch("id") == "uniapp" }
  abort("UniApp target is missing") unless uniapp
  abort("UniApp target must explicitly declare its independent version") unless uniapp.key?("version")
  provenance = uniapp.fetch("constraints", []).select { |constraint| constraint.fetch("name") == "native-release-version" }
  abort("UniApp must declare exactly one native-release-version") unless provenance.length == 1
  abort("UniApp native release must remain at the root version") unless provenance.fetch(0).fetch("value") == default_version
  expected_source_root = "uni_modules/Sandrox-Levixel"
  actual_source_root = uniapp.fetch("sourceRoot")
  abort("UniApp sourceRoot must be #{expected_source_root}, got #{actual_source_root}") unless actual_source_root == expected_source_root
  abort("UniApp sourceRoot does not exist: #{actual_source_root}") unless File.directory?(File.join(ARGV.fetch(1), actual_source_root))
  web = targets.find { |target| target.fetch("id") == "web" }
  abort("Web target is missing") unless web
  abort("Web target must explicitly declare its independently staged version") unless web.key?("version")
  expected_web_source_root = "adapters/web"
  actual_web_source_root = web.fetch("sourceRoot")
  abort("Web sourceRoot must be #{expected_web_source_root}, got #{actual_web_source_root}") unless actual_web_source_root == expected_web_source_root
  abort("Web sourceRoot does not exist: #{actual_web_source_root}") unless File.directory?(File.join(ARGV.fetch(1), actual_web_source_root))
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
cmp "${plugin_dir}/LICENSE" \
  "${plugin_dir}/adapters/web/LICENSE"
cmp "${plugin_dir}/PROVENANCE.md" \
  "${plugin_dir}/adapters/web/PROVENANCE.md"
cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" \
  "${plugin_dir}/adapters/web/THIRD_PARTY_NOTICES.md"

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
  "${plugin_dir}/adapters/web/src" \
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
printf '%s\n' "Levixel root ${version} metadata is consistent (Web ${web_version}; UniApp UTS ${uniapp_target_version} uses native ${uniapp_native_version} and remains an unreleased candidate)."
