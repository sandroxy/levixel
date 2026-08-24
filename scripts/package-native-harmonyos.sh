#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
harmony_dir="${plugin_dir}/native/harmonyos"
module_dir="${harmony_dir}/levixel"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_name="levixel-${version}.har"
artifact_dir="${plugin_dir}/dist/native-harmonyos"
artifact_path="${artifact_dir}/${artifact_name}"
built_har="${module_dir}/build/default/outputs/default/levixel.har"

module_version="$(ruby -rjson -e 'print JSON.parse(File.read(ARGV.fetch(0))).fetch("version")' "${module_dir}/oh-package.json5")"
if [[ "${module_version}" != "${version}" ]]; then
  echo "HarmonyOS package version ${module_version} does not match plugin version ${version}." >&2
  exit 1
fi

for required_file in README.md CHANGELOG.md LICENSE THIRD_PARTY_NOTICES.md; do
  if [[ ! -f "${module_dir}/${required_file}" ]]; then
    echo "HarmonyOS release metadata is missing ${required_file}." >&2
    exit 1
  fi
done

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

deveco_sdk_home="${DEVECO_SDK_HOME:-}"
if [[ -z "${deveco_sdk_home}" && -d "${deveco_contents}/sdk" ]]; then
  deveco_sdk_home="${deveco_contents}/sdk"
fi
if [[ ! -d "${deveco_sdk_home}" ]]; then
  echo "DevEco SDK was not found. Set DEVECO_SDK_HOME." >&2
  exit 1
fi

rm -rf "${module_dir}/build"
(
  cd "${harmony_dir}"
  DEVECO_SDK_HOME="${deveco_sdk_home}" "${hvigorw}" assembleHar \
    --mode module \
    -p module=levixel@default \
    -p product=default \
    -p buildMode=release
)

if [[ ! -f "${built_har}" ]]; then
  echo "HarmonyOS HAR was not produced: ${built_har}" >&2
  exit 1
fi

mkdir -p "${artifact_dir}"
rm -f "${artifact_path}" "${artifact_path}.sha256"
cp "${built_har}" "${artifact_path}"

checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${artifact_path}.sha256"
printf '%s\n' "${artifact_path}"
