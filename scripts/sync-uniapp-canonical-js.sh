#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
canonical_source="${plugin_dir}/adapters/uniapp/js_sdk/index.js"
generated_target="${plugin_dir}/uni_modules/Sandrox-Levixel/js_sdk/canonical.js"
mode="${1:---write}"

case "${mode}" in
  --write)
    cp "${canonical_source}" "${generated_target}"
    printf 'Synchronized %s from %s\n' "${generated_target}" "${canonical_source}"
    ;;
  --check)
    if [[ ! -f "${generated_target}" ]]; then
      echo "Generated UniApp canonical SDK is missing: ${generated_target}" >&2
      echo "Run ./scripts/sync-uniapp-canonical-js.sh after updating the canonical SDK." >&2
      exit 1
    fi
    if ! cmp -s "${canonical_source}" "${generated_target}"; then
      echo "Generated UniApp canonical SDK has drifted from ${canonical_source}" >&2
      echo "Run ./scripts/sync-uniapp-canonical-js.sh and review the generated diff." >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [--write|--check]" >&2
    exit 2
    ;;
esac
