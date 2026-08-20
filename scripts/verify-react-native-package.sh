#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
adapter_dir="${plugin_dir}/adapters/react-native"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_name="sandrox-levixel-${version}.tgz"
artifact_path="${1:-${plugin_dir}/dist/react-native/${artifact_name}}"
checksum_path="${artifact_path}.sha256"
native_manifest="${plugin_dir}/dist/native-release/levixel-native-${version}.json"
android_artifact="${plugin_dir}/dist/native-android/levixel-${version}.aar"
ios_artifact="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"

for required_file in \
  "${artifact_path}" \
  "${checksum_path}" \
  "${native_manifest}" \
  "${android_artifact}" \
  "${ios_artifact}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Required release input is missing: ${required_file}" >&2
    exit 1
  fi
done

read -r expected_android_sha expected_ios_sha native_commit < <(
  ruby -rjson -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    abort("Unexpected native release schema") unless manifest["schemaVersion"] == 1
    abort("Unexpected native release plugin") unless manifest["plugin"] == "levixel"
    abort("Native release version mismatch") unless manifest["version"] == version
    abort("Dirty native release is not publishable") unless manifest["dirty"] == false
    artifacts = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
    android = artifacts.fetch("levixel-#{version}.aar").fetch("sha256")
    ios = artifacts.fetch("levixel-#{version}.xcframework.zip").fetch("sha256")
    puts [android, ios, manifest.fetch("commit")].join(" ")
  ' "${native_manifest}" "${version}"
)

actual_android_sha="$(shasum -a 256 "${android_artifact}" | awk '{print $1}')"
actual_ios_sha="$(shasum -a 256 "${ios_artifact}" | awk '{print $1}')"
if [[ "${actual_android_sha}" != "${expected_android_sha}" ]]; then
  echo "Android AAR does not match the native ${version} release manifest." >&2
  exit 1
fi
if [[ "${actual_ios_sha}" != "${expected_ios_sha}" ]]; then
  echo "iOS XCFramework does not match the native ${version} release manifest." >&2
  exit 1
fi

actual_package_sha="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
read -r recorded_package_sha recorded_package_name < "${checksum_path}"
if [[ "${recorded_package_sha}" != "${actual_package_sha}" \
  || "${recorded_package_name}" != "${artifact_name}" ]]; then
  echo "React Native package checksum sidecar does not match ${artifact_name}." >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
tar -xzf "${artifact_path}" -C "${temporary_dir}"
package_root="${temporary_dir}/package"

if [[ ! -d "${package_root}" ]]; then
  echo "React Native tarball does not contain an npm package root." >&2
  exit 1
fi

while IFS= read -r entry; do
  case "${entry}" in
    package|package/|package/android|package/android/*|package/ios|package/ios/*|package/src|package/src/*|\
    package/package.json|package/README.md|package/LICENSE|package/CHANGELOG.md|\
    package/PROVENANCE.md|package/THIRD_PARTY_NOTICES.md|\
    package/SandroxLevixel.podspec|package/expo-module.config.json) ;;
    *)
      echo "Unexpected file in React Native package: ${entry}" >&2
      exit 1
      ;;
  esac
done < <(tar -tzf "${artifact_path}")

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "name" => "@sandrox/levixel",
    "version" => ARGV.fetch(1),
    "license" => "MIT",
    "homepage" => "https://gitee.com/sandrox/levixel",
    "main" => "src/index.ts",
    "react-native" => "src/index.ts",
    "types" => "src/index.ts"
  }
  mismatches = expected.reject { |key, value| package[key] == value }
  abort("Unexpected npm package metadata: #{mismatches.inspect}") unless mismatches.empty?
  repository = package.fetch("repository")
  abort("Unexpected npm repository") unless repository == {
    "type" => "git",
    "url" => "https://gitee.com/sandrox/levixel.git"
  }
  abort("Unexpected npm bugs URL") unless package.dig("bugs", "url") == "https://gitee.com/sandrox/levixel/issues"
  abort("Package must publish publicly") unless package.dig("publishConfig", "access") == "public"
  abort("Package must use the public npm registry") unless package.dig("publishConfig", "registry") == "https://registry.npmjs.org/"
  lifecycle = package.fetch("scripts", {}).keys.grep(/^(preinstall|install|postinstall|prepublish|prepare)$/)
  abort("Unexpected lifecycle scripts: #{lifecycle.join(", ")}") unless lifecycle.empty?
' "${package_root}/package.json" "${version}"

for relative_path in \
  package.json \
  expo-module.config.json \
  SandroxLevixel.podspec \
  README.md; do
  cmp "${adapter_dir}/${relative_path}" "${package_root}/${relative_path}"
done
for relative_path in CHANGELOG.md LICENSE PROVENANCE.md THIRD_PARTY_NOTICES.md; do
  cmp "${plugin_dir}/${relative_path}" "${package_root}/${relative_path}"
done

diff -qr "${adapter_dir}/src" "${package_root}/src"
diff -qr -x libs "${adapter_dir}/android" "${package_root}/android"
diff -qr -x Frameworks "${adapter_dir}/ios" "${package_root}/ios"

packaged_aar="${package_root}/android/libs/levixel-core.aar"
packaged_xcframework="${package_root}/ios/Frameworks/Levixel.xcframework"
if [[ ! -f "${packaged_aar}" || ! -d "${packaged_xcframework}" ]]; then
  echo "React Native package is missing a native core artifact." >&2
  exit 1
fi
cmp "${android_artifact}" "${packaged_aar}"

mkdir -p "${temporary_dir}/native-ios"
unzip -q "${ios_artifact}" 'Levixel.xcframework/*' -d "${temporary_dir}/native-ios"
diff -qr "${temporary_dir}/native-ios/Levixel.xcframework" "${packaged_xcframework}"

if tar -tzf "${artifact_path}" | rg -q \
  '(^|/)(native|Viewer|native-harmonyos)(/|$)|LevixelViewer(OverlayView|Controller|PageView)\.(java|kt|swift)$'; then
  echo "Native viewer source was duplicated into the React Native package." >&2
  exit 1
fi

if find "${package_root}" -type f \
  \( -name '.env*' -o -name '.npmrc' -o -name '*.jks' -o -name '*.keystore' \
     -o -name '*.p12' -o -name '*.p8' -o -name '*private*key*' \) \
  -print -quit | grep -q .; then
  echo "Potential secret file found in the React Native package." >&2
  exit 1
fi

printf '%s\n' "Verified ${artifact_name}"
printf '%s\n' "  package sha256: ${actual_package_sha}"
printf '%s\n' "  native release: ${native_commit}"
printf '%s\n' "  Android AAR: ${expected_android_sha}"
printf '%s\n' "  iOS XCFramework: ${expected_ios_sha}"
