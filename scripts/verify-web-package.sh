#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  target = manifest.fetch("targets").find { |entry| entry.fetch("id") == "web" }
  abort("Web target is missing from plugin.yaml") unless target
  print target.fetch("version", manifest.fetch("version"))
' "${plugin_dir}/plugin.yaml")"
artifact_path="${1:-${plugin_dir}/dist/web/levixel-web-${version}.tgz}"
checksum_path="${artifact_path}.sha256"

if [[ ! -f "${artifact_path}" ]]; then
  echo "Web release artifact is missing: ${artifact_path}" >&2
  echo "Run ./scripts/package-web.sh first." >&2
  exit 1
fi
if command -v shasum >/dev/null 2>&1; then
  actual_sha256="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
else
  actual_sha256="$(sha256sum "${artifact_path}" | awk '{print $1}')"
fi
accepted_sha256="${2:-${actual_sha256}}"

"${plugin_dir}/.github/scripts/verify-web-package.sh" \
  "${version}" \
  "${plugin_dir}" \
  "${artifact_path}" \
  "${checksum_path}" \
  "${accepted_sha256}"
