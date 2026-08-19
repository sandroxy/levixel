#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
android_dir="${plugin_dir}/native/android"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_name="levixel-${version}.aar"
artifact_dir="${plugin_dir}/dist/native-android"
artifact_path="${artifact_dir}/${artifact_name}"

"${android_dir}/gradlew" -p "${android_dir}" :levixel:clean :levixel:assembleRelease

mkdir -p "${artifact_dir}"
cp "${android_dir}/levixel/build/outputs/aar/levixel-release.aar" "${artifact_path}"

checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${artifact_path}.sha256"
printf '%s\n' "${artifact_path}"
