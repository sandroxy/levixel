#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
web_dir="${plugin_dir}/adapters/web"

cmp "${plugin_dir}/LICENSE" "${web_dir}/LICENSE"
cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${web_dir}/THIRD_PARTY_NOTICES.md"

node -e '
  const packageJson = require(process.argv[1])
  if (packageJson.name !== "@sandrox/levixel-web")
    throw new Error(`Unexpected Web package name: ${packageJson.name}`)
  if (packageJson.version !== "0.0.0-development" || packageJson.private !== true)
    throw new Error("Unaccepted Web source must remain private at 0.0.0-development")
' "${web_dir}/package.json"

npm --prefix "${web_dir}" run verify
(
  cd "${web_dir}"
  npm pack --dry-run --json >/dev/null
)

printf '%s\n' "Levixel Web source candidate is consistent."
