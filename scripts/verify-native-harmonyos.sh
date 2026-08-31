#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-harmonyos/levixel-${version}.har"

deveco_contents="${DEVECO_STUDIO_CONTENTS:-/Applications/DevEco-Studio.app/Contents}"

ohpm="${OHPM:-}"
if [[ -z "${ohpm}" ]]; then
  ohpm="$(command -v ohpm || true)"
fi
if [[ -z "${ohpm}" && -x "${deveco_contents}/tools/ohpm/bin/ohpm" ]]; then
  ohpm="${deveco_contents}/tools/ohpm/bin/ohpm"
fi
if [[ -z "${ohpm}" || ! -x "${ohpm}" ]]; then
  echo "ohpm was not found. Set OHPM or add it to PATH." >&2
  exit 1
fi

if [[ ! -f "${artifact_path}" ]]; then
  echo "Packaged HarmonyOS artifact is missing: ${artifact_path}" >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
tar -xzf "${artifact_path}" -C "${temporary_dir}"

package_dir="${temporary_dir}/package"
if [[ ! -f "${package_dir}/Index.d.ets" || ! -f "${package_dir}/ets/modules.abc" ]]; then
  echo "Packaged HAR does not contain the Levixel public API and bytecode." >&2
  exit 1
fi
if ! grep -Eq '"name":"@sandrox/levixel"' "${package_dir}/oh-package.json5"; then
  echo "Packaged HAR has unexpected package metadata." >&2
  exit 1
fi
ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "name" => "@sandrox/levixel",
    "version" => ARGV.fetch(1),
    "author" => {
      "name" => "SandroX",
      "email" => "wangyifengjxc@gmail.com",
      "url" => "https://github.com/sandroxy"
    },
    "homepage" => "https://github.com/sandroxy/levixel",
    "repository" => "https://github.com/sandroxy/levixel",
    "types" => "Index.d.ets",
    "artifactType" => "obfuscation",
    "compatibleSdkVersion" => 23,
    "compatibleSdkType" => "HarmonyOS",
    "obfuscated" => false
  }
  mismatches = expected.reject { |key, value| package[key] == value }
  abort("Unexpected HarmonyOS release metadata: #{mismatches.inspect}") unless mismatches.empty?
' "${package_dir}/oh-package.json5" "${version}"
for required_file in README.md CHANGELOG.md LICENSE; do
  if [[ ! -f "${package_dir}/${required_file}" ]]; then
    echo "Packaged HarmonyOS artifact is missing ${required_file}." >&2
    exit 1
  fi
done
if ! grep -Eq 'Copyright \(c\) 2025 Fernando Rojo' "${package_dir}/LICENSE" ||
   ! grep -Eq 'Copyright \(c\) 2013 Michael Henry Pantaleon' "${package_dir}/LICENSE"; then
  echo "Packaged HarmonyOS LICENSE is missing required third-party notices." >&2
  exit 1
fi

while IFS= read -r -d '' packaged_file; do
  if grep -a -n -E 'Galeria|galeria|com\.chris' "${packaged_file}"; then
    echo "Legacy Galeria identifiers found in packaged HarmonyOS runtime content." >&2
    exit 1
  fi
done < <(find "${package_dir}" -type f \
  ! -name 'LICENSE' \
  ! -name 'THIRD_PARTY_NOTICES.md' \
  -print0)

"${ohpm}" prepublish "${artifact_path}"

printf '%s\n' "Verified ${artifact_path}"
