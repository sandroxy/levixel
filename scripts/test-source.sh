#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"

node --input-type=module -e '
  import * as module from "node:module";
  for (const name of ["registerHooks", "stripTypeScriptTypes"]) {
    if (typeof module[name] !== "function") {
      throw new Error(`HarmonyOS source tests require node:module.${name}; update Node.js before running source checks.`);
    }
  }
'

"${script_dir}/verify-documentation.sh"
node "${script_dir}/verify-contract-schema.mjs"
"${script_dir}/sync-uniapp-canonical-js.sh" --check
"${script_dir}/verify-react-native-contract.sh"
"${script_dir}/verify-react-native-ios-lifecycle.rb"
node --test "${plugin_dir}/adapters/uniapp/js_sdk/index.test.mjs"
node --test "${script_dir}/test-harmonyos-viewer-context.mjs"
npm --prefix "${plugin_dir}/adapters/web" run verify
"${plugin_dir}/native/android/gradlew" -p "${plugin_dir}/native/android" \
  :levixel:testDebugUnitTest :levixel:assembleDebug :levixel:lintDebug --console=plain
"${plugin_dir}/native/android/gradlew" -p "${plugin_dir}/adapters/uniapp/android" \
  :levixel-uniapp-runtime:testDebugUnitTest :levixel-uniapp-runtime:assembleDebug \
  "-PlevixelCoreAar=${plugin_dir}/native/android/levixel/build/outputs/aar/levixel-debug.aar" --console=plain

printf '%s\n' 'Levixel source checks passed. Device and release-artifact acceptance are separate.'
