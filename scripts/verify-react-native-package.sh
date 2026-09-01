#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
adapter_dir="${plugin_dir}/adapters/react-native"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_name="levixel-react-native-${version}.tgz"
artifact_path="${plugin_dir}/dist/react-native/${artifact_name}"
allow_dirty=0
artifact_path_set=0
for argument in "$@"; do
  case "${argument}" in
    --allow-dirty) allow_dirty=1 ;;
    --*)
      echo "Unknown option: ${argument}" >&2
      echo "Usage: $0 [ARTIFACT_PATH] [--allow-dirty]" >&2
      exit 1
      ;;
    *)
      if [[ ${artifact_path_set} -eq 1 ]]; then
        echo "Usage: $0 [ARTIFACT_PATH] [--allow-dirty]" >&2
        exit 1
      fi
      artifact_path="${argument}"
      artifact_path_set=1
      ;;
  esac
done
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

"${script_dir}/verify-ios-core-adapter-api.sh" "${ios_artifact}"

read -r expected_android_sha expected_ios_sha native_commit < <(
  ruby -I "${script_dir}" -rjson -r native-release-manifest -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: version)
    allow_dirty = ARGV.fetch(2) == "true"
    abort("Dirty native release is not publishable") unless manifest["dirty"] == false || allow_dirty
    artifacts = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
    android = artifacts.fetch("levixel-#{version}.aar").fetch("sha256")
    ios = artifacts.fetch("levixel-#{version}.xcframework.zip").fetch("sha256")
    puts [android, ios, manifest.fetch("commit")].join(" ")
  ' "${native_manifest}" "${version}" "$([[ ${allow_dirty} -eq 1 ]] && printf true || printf false)"
)

source_commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
if [[ "${native_commit}" != "${source_commit}" ]]; then
  echo "Native release commit ${native_commit} does not equal React Native source commit ${source_commit}." >&2
  exit 1
fi

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
"${script_dir}/verify-native-manifest-ios-provenance.sh" \
  "${native_manifest}" "${ios_artifact}" "${version}"

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
    "homepage" => "https://github.com/sandroxy/levixel",
    "main" => "src/index.ts",
    "react-native" => "src/index.ts",
    "types" => "src/index.ts"
  }
  mismatches = expected.reject { |key, value| package[key] == value }
  abort("Unexpected npm package metadata: #{mismatches.inspect}") unless mismatches.empty?
  repository = package.fetch("repository")
  abort("Unexpected npm repository") unless repository == {
    "type" => "git",
    "url" => "git+https://github.com/sandroxy/levixel.git"
  }
  abort("Unexpected npm bugs URL") unless package.dig("bugs", "url") == "https://github.com/sandroxy/levixel/issues"
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
for relative_path in LICENSE PROVENANCE.md THIRD_PARTY_NOTICES.md; do
  cmp "${plugin_dir}/${relative_path}" "${package_root}/${relative_path}"
done

for changelog in "${plugin_dir}/CHANGELOG.md" "${package_root}/CHANGELOG.md"; do
  if ! grep -Eq "^## ${version}( |$)" "${changelog}"; then
    echo "CHANGELOG.md does not contain a ${version} release entry: ${changelog}" >&2
    exit 1
  fi
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

if tar -tzf "${artifact_path}" | grep -E \
  '(^|/)(native|Viewer|native-harmonyos)(/|$)|LevixelViewer(OverlayView|Controller|PageView)\.(java|kt|swift)$' >/dev/null; then
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

"${script_dir}/verify-react-native-contract.sh" "${package_root}/src/contract.ts"
"${script_dir}/verify-react-native-ios-lifecycle.rb" "${package_root}/ios/LevixelView.swift"

printf '%s\n' "Verified ${artifact_name}"
printf '%s\n' "  package sha256: ${actual_package_sha}"
printf '%s\n' "  native release: ${native_commit}"
printf '%s\n' "  Android AAR: ${expected_android_sha}"
printf '%s\n' "  iOS XCFramework: ${expected_ios_sha}"
