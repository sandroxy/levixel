#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-harmonyos/levixel-${version}.har"
host_dir="${repo_root}/harmonyos-plugins-test"
staging_dir="${host_dir}/.artifacts"
staged_har="${staging_dir}/levixel.har"

deveco_contents="${DEVECO_STUDIO_CONTENTS:-/Applications/DevEco-Studio.app/Contents}"

hvigorw="${HVIGORW:-}"
if [[ -z "${hvigorw}" ]]; then
  hvigorw="$(command -v hvigorw || true)"
fi
if [[ -z "${hvigorw}" && -x "${deveco_contents}/tools/hvigor/bin/hvigorw" ]]; then
  hvigorw="${deveco_contents}/tools/hvigor/bin/hvigorw"
fi
if [[ -z "${hvigorw}" || ! -x "${hvigorw}" ]]; then
  echo "hvigorw was not found. Set HVIGORW or add it to PATH." >&2
  exit 1
fi

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

deveco_sdk_home="${DEVECO_SDK_HOME:-}"
if [[ -z "${deveco_sdk_home}" && -d "${deveco_contents}/sdk" ]]; then
  deveco_sdk_home="${deveco_contents}/sdk"
fi
if [[ ! -d "${deveco_sdk_home}" ]]; then
  echo "DevEco SDK was not found. Set DEVECO_SDK_HOME." >&2
  exit 1
fi

if [[ "${LEVIXEL_SKIP_PACKAGE:-0}" != "1" ]]; then
  "${script_dir}/package-native-harmonyos.sh"
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
if ! rg -q '"name":"@sandrox/levixel"' "${package_dir}/oh-package.json5"; then
  echo "Packaged HAR has unexpected package metadata." >&2
  exit 1
fi
ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "name" => "@sandrox/levixel",
    "version" => ARGV.fetch(1),
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
if ! rg -q 'Copyright \(c\) 2025 Fernando Rojo' "${package_dir}/LICENSE" ||
   ! rg -q 'Copyright \(c\) 2013 Michael Henry Pantaleon' "${package_dir}/LICENSE"; then
  echo "Packaged HarmonyOS LICENSE is missing required third-party notices." >&2
  exit 1
fi

while IFS= read -r -d '' packaged_file; do
  if rg -a -n 'Galeria|galeria|com\.chris' "${packaged_file}"; then
    echo "Legacy Galeria identifiers found in packaged HarmonyOS runtime content." >&2
    exit 1
  fi
done < <(find "${package_dir}" -type f \
  ! -name 'LICENSE' \
  ! -name 'THIRD_PARTY_NOTICES.md' \
  -print0)

"${ohpm}" prepublish "${artifact_path}"

rm -rf "${staging_dir}" "${host_dir}/oh_modules" "${host_dir}/entry/oh_modules" "${host_dir}/entry/build"
mkdir -p "${staging_dir}"
cp "${artifact_path}" "${staged_har}"

(
  cd "${host_dir}"
  "${ohpm}" install --all
  DEVECO_SDK_HOME="${deveco_sdk_home}" "${hvigorw}" assembleHap \
    --mode module \
    -p module=entry@default \
    -p product=default \
    -p buildMode=debug
)

host_hap="${host_dir}/entry/build/default/outputs/default/entry-default-unsigned.hap"
if [[ ! -f "${host_hap}" ]]; then
  echo "HarmonyOS test host HAP was not produced: ${host_hap}" >&2
  exit 1
fi

printf '%s\n' "Verified ${artifact_path}"
