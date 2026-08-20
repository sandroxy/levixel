#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
repository_path="${plugin_dir}/dist/native-android/levixel-${version}-maven.zip"
artifact_dir="${plugin_dir}/dist/native-android"
bundle_name="levixel-${version}-maven-central.zip"
bundle_path="${artifact_dir}/${bundle_name}"
expected_signing_fingerprint="B7D159C354B9EF7318D3544200BE5C219A0DD690"

if [[ ! -f "${repository_path}" ]]; then
  echo "Build and verify the native release candidate before preparing Maven Central." >&2
  exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "GnuPG is required to verify the Maven Central signatures." >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
unzip -q "${repository_path}" -d "${temporary_dir}/repository"

version_dir="${temporary_dir}/repository/io/gitee/sandrox/levixel/${version}"
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

  signature_status="$(gpg --batch --status-fd 1 --verify "${artifact}.asc" "${artifact}" 2>/dev/null || true)"
  signature_fingerprint="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $3; exit }' <<<"${signature_status}")"
  if [[ "${signature_fingerprint}" != "${expected_signing_fingerprint}" ]]; then
    echo "Unexpected Maven signature for $(basename "${artifact}"): ${signature_fingerprint:-invalid}" >&2
    exit 1
  fi

  for checksum in md5 sha1 sha256 sha512; do
    if [[ ! -f "${artifact}.${checksum}" || ! -f "${artifact}.asc.${checksum}" ]]; then
      echo "Maven checksum is missing for $(basename "${artifact}") (${checksum})." >&2
      exit 1
    fi
  done
done

bundle_root="${temporary_dir}/bundle/io/gitee/sandrox/levixel"
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
