#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
contract_path="${1:-${plugin_dir}/adapters/react-native/src/contract.ts}"

if [[ ! -f "${contract_path}" ]]; then
  echo "React Native contract source does not exist: ${contract_path}" >&2
  exit 1
fi

read -r node_major node_minor < <(
  node -p 'process.versions.node.split(".").slice(0, 2).join(" ")'
)
if (( node_major < 22 || (node_major == 22 && node_minor < 6) )); then
  echo "React Native contract verification requires Node.js 22.6 or newer." >&2
  exit 1
fi

LEVIXEL_RN_CONTRACT_PATH="${contract_path}" node --experimental-strip-types \
  --disable-warning=MODULE_TYPELESS_PACKAGE_JSON \
  --test \
  "${plugin_dir}/adapters/react-native/tests/contract.test.mjs"
