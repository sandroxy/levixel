#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
repository_path="${plugin_dir}/dist/native-android/levixel-${version}-maven.zip"
artifact_dir="${plugin_dir}/dist/native-android"
bundle_name="levixel-${version}-maven-central.zip"
bundle_path="${artifact_dir}/${bundle_name}"

if [[ ! -f "${repository_path}" ]]; then
  echo "Build and verify the native release candidate before preparing Maven Central." >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
unzip -q "${repository_path}" -d "${temporary_dir}/repository"

version_dir="${temporary_dir}/repository/com/sandrox/levixel/${version}"
if [[ ! -d "${version_dir}" ]]; then
  echo "Maven repository does not contain Levixel ${version}." >&2
  exit 1
fi

artifacts=(
  "${version_dir}/levixel-${version}.aar"
  "${version_dir}/levixel-${version}.pom"
  "${version_dir}/levixel-${version}.module"
  "${version_dir}/levixel-${version}-sources.jar"
  "${version_dir}/levixel-${version}-javadoc.jar"
)
for artifact in "${artifacts[@]}"; do
  if [[ ! -f "${artifact}" ]]; then
    echo "Maven Central artifact is missing: ${artifact}" >&2
    exit 1
  fi
  if [[ ! -f "${artifact}.asc" ]]; then
    echo "Maven signature is missing for $(basename "${artifact}")." >&2
    echo "Rebuild the release candidate with LEVIXEL_SIGNING_KEY and LEVIXEL_SIGNING_PASSWORD." >&2
    exit 1
  fi
done

bundle_root="${temporary_dir}/bundle/com/sandrox/levixel"
mkdir -p "${bundle_root}"
cp -R "${version_dir}" "${bundle_root}/${version}"

rm -f "${bundle_path}" "${bundle_path}.sha256"
(
  cd "${temporary_dir}/bundle"
  zip -qry "${bundle_path}" .
)
checksum="$(shasum -a 256 "${bundle_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${bundle_name}" > "${bundle_path}.sha256"
printf '%s\n' "${bundle_path}"
