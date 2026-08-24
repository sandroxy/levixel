#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
adapter_dir="${plugin_dir}/adapters/react-native"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "${adapter_dir}/package.json")"
dist_dir="${plugin_dir}/dist/react-native"
staging_dir="${dist_dir}/package"
artifact_name="levixel-react-native-${version}.tgz"
artifact_path="${dist_dir}/${artifact_name}"

if [[ "${package_version}" != "${version}" ]]; then
  echo "React Native package version ${package_version} does not match plugin version ${version}" >&2
  exit 1
fi

"${script_dir}/verify-release-metadata.sh"

android_artifact="${plugin_dir}/dist/native-android/levixel-${version}.aar"
ios_artifact="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
for native_artifact in "${android_artifact}" "${ios_artifact}"; do
  if [[ ! -f "${native_artifact}" ]]; then
    echo "Native artifact is missing: ${native_artifact}" >&2
    echo "Package and verify the native cores before packaging React Native." >&2
    exit 1
  fi
done

rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"

cp "${adapter_dir}/package.json" "${staging_dir}/package.json"
cp "${adapter_dir}/expo-module.config.json" "${staging_dir}/expo-module.config.json"
cp "${adapter_dir}/SandroxLevixel.podspec" "${staging_dir}/SandroxLevixel.podspec"
cp "${adapter_dir}/README.md" "${staging_dir}/README.md"
cp "${plugin_dir}/CHANGELOG.md" "${staging_dir}/CHANGELOG.md"
cp "${plugin_dir}/LICENSE" "${staging_dir}/LICENSE"
cp "${plugin_dir}/PROVENANCE.md" "${staging_dir}/PROVENANCE.md"
cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${staging_dir}/THIRD_PARTY_NOTICES.md"
cp -R "${adapter_dir}/src" "${staging_dir}/src"
cp -R "${adapter_dir}/android" "${staging_dir}/android"
cp -R "${adapter_dir}/ios" "${staging_dir}/ios"
mkdir -p \
  "${staging_dir}/android/libs" \
  "${staging_dir}/ios/Frameworks"

cp "${android_artifact}" "${staging_dir}/android/libs/levixel-core.aar"

unzip -q "${ios_artifact}" 'Levixel.xcframework/*' -d "${staging_dir}/ios/Frameworks"

rm -f "${artifact_path}" "${artifact_path}.sha256"
packed_name="$(cd "${staging_dir}" && npm pack --silent --pack-destination "${dist_dir}")"
packed_path="${dist_dir}/${packed_name}"
if [[ "${packed_path}" != "${artifact_path}" ]]; then
  mv "${packed_path}" "${artifact_path}"
fi

if ! tar -tzf "${artifact_path}" | rg -q 'package/android/libs/levixel-core\.aar$'; then
  echo "React Native package is missing the Android AAR" >&2
  exit 1
fi
if ! tar -tzf "${artifact_path}" | rg -q 'package/ios/Frameworks/Levixel\.xcframework/Info\.plist$'; then
  echo "React Native package is missing the iOS XCFramework" >&2
  exit 1
fi

checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${artifact_path}.sha256"
rm -rf "${staging_dir}"
"${script_dir}/verify-react-native-package.sh" "${artifact_path}"
printf '%s\n' "${artifact_path}"
