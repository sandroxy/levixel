#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
android_dir="${plugin_dir}/native/android"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_name="levixel-${version}.aar"
repository_name="levixel-${version}-maven.zip"
artifact_dir="${plugin_dir}/dist/native-android"
artifact_path="${artifact_dir}/${artifact_name}"
repository_path="${artifact_dir}/${repository_name}"
repository_dir="${android_dir}/levixel/build/maven-repository"
maven_artifact="${repository_dir}/com/sandrox/levixel/${version}/${artifact_name}"

"${android_dir}/gradlew" -p "${android_dir}" \
  :levixel:clean \
  :levixel:publishReleasePublicationToLocalReleaseRepository

mkdir -p "${artifact_dir}"
if [[ ! -f "${maven_artifact}" ]]; then
  echo "Maven publication did not produce ${maven_artifact}" >&2
  exit 1
fi

cp "${maven_artifact}" "${artifact_path}"
rm -f "${repository_path}"
(
  cd "${repository_dir}"
  zip -qry "${repository_path}" .
)

checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${artifact_path}.sha256"
repository_checksum="$(shasum -a 256 "${repository_path}" | awk '{print $1}')"
printf '%s  %s\n' "${repository_checksum}" "${repository_name}" > "${repository_path}.sha256"
printf '%s\n' "${artifact_path}"
printf '%s\n' "${repository_path}"
