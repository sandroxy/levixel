#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
archive_path="${1:-${plugin_dir}/dist/uniapp/levixel-uniapp-${version}.zip}"
hbuilder_contents="${HBUILDERX_CONTENTS:-/Applications/HBuilderX.app/Contents/HBuilderX}"
hbuilder_node="${HBUILDERX_NODE:-${hbuilder_contents}/plugins/node/node}"
uts_compiler="${hbuilder_contents}/plugins/uniapp-uts-v1/node_modules/@dcloudio/uni-uts-v1"
runextension_dir="${hbuilder_contents}/plugins/uniapp-runextension"
classic_android_libs="${runextension_dir}/lib"
kotlinc="${runextension_dir}/kotlinc/bin/kotlinc"
kotlin_plugin="${uts_compiler}/lib/kotlin/lib/uts-kotlin-compiler-plugin.jar"
dcloud_ios_frameworks="${hbuilder_contents}/plugins/launcher/base/Pandora_simulator.app/Frameworks"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

for required_path in \
  "${archive_path}" \
  "${hbuilder_node}" \
  "${uts_compiler}/dist/index.js" \
  "${kotlinc}" \
  "${kotlin_plugin}" \
  "${classic_android_libs}/utsplugin-release.jar" \
  "${dcloud_ios_frameworks}/DCloudUTSFoundation.framework"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "UTS compiler verification dependency is missing: ${required_path}" >&2
    exit 1
  fi
done

mkdir -p "${work_dir}/input/uni_modules"
unzip -q "${archive_path}" -d "${work_dir}/input/uni_modules"
package_root="${work_dir}/input/uni_modules/Sandrox-Levixel"
if [[ ! -f "${package_root}/package.json" ]]; then
  echo "Sandrox-Levixel/package.json is missing from ${archive_path}" >&2
  exit 1
fi

compile_uts() {
  local platform="$1"
  local output_dir="${work_dir}/output-${platform}"
  mkdir -p "${output_dir}"
  UNI_INPUT_DIR="${work_dir}/input" \
  UNI_OUTPUT_DIR="${output_dir}" \
  UNI_UTS_PLATFORM="${platform}" \
  NODE_ENV=production \
    "${hbuilder_node}" - "${uts_compiler}" "${package_root}" <<'NODE'
const compiler = require(process.argv[2])
const pluginDir = process.argv[3]

compiler.compile(pluginDir, {
  isX: false,
  isPlugin: true,
  isSingleThread: true,
  sourceMap: true,
}).then((result) => {
  if (!result)
    throw new Error('HBuilderX did not return a UTS compile result')
  if (result.errMsg)
    throw new Error(result.errMsg)
}).catch((error) => {
  console.error(error && error.stack ? error.stack : error)
  process.exit(1)
})
NODE
}

compile_uts app-android
compile_uts app-ios

android_output="${work_dir}/output-app-android/uni_modules/Sandrox-Levixel/utssdk/app-android"
kotlin_source="${android_output}/src/index.kt"
if [[ ! -f "${kotlin_source}" ]]; then
  echo "HBuilderX did not generate the Android UTS bridge" >&2
  exit 1
fi

mkdir -p "${work_dir}/android-libs"
for aar in "${android_output}"/libs/*.aar; do
  aar_name="$(basename "${aar}" .aar)"
  aar_dir="${work_dir}/android-libs/${aar_name}"
  mkdir -p "${aar_dir}"
  unzip -q "${aar}" classes.jar -d "${aar_dir}"
done

kotlin_classpath="$(find "${classic_android_libs}" "${work_dir}/android-libs" \
  -type f -name '*.jar' -print | sort | paste -sd: -)"
"${kotlinc}" \
  -classpath "${kotlin_classpath}" \
  -d "${work_dir}/android-classes" \
  -Xplugin="${kotlin_plugin}" \
  -P plugin:io.dcloud.uts.kotlin:tag=UTS \
  -P plugin:io.dcloud.uts.kotlin:console=true \
  "${kotlin_source}"

if [[ ! -f "${work_dir}/android-classes/uts/sdk/modules/SandroxLevixel/IndexKt.class" ]]; then
  echo "Kotlin compilation did not produce the UTS entry class" >&2
  exit 1
fi

ios_output="${work_dir}/output-app-ios/uni_modules/Sandrox-Levixel/utssdk/app-ios"
swift_source="${ios_output}/src/index.swift"
if [[ ! -f "${swift_source}" ]]; then
  echo "HBuilderX did not generate the iOS UTS bridge" >&2
  exit 1
fi
if rg -q 'getCurrentViewController' "${swift_source}"; then
  echo "The generated iOS UTS bridge must use the shared runtime context fallback" >&2
  exit 1
fi
if ! rg -q 'openJSON\(optionsJson, rootView: nil, viewController: nil' "${swift_source}"; then
  echo "The generated iOS UTS bridge is not using the shared runtime context fallback" >&2
  exit 1
fi
if rg -q 'retainedEventCallback' "${swift_source}"; then
  echo "The generated iOS UTS bridge must not retain a second event callback slot" >&2
  exit 1
fi
if [[ "$(rg -c 'LevixelUniPresenter\.shared\.setJSONEventHandler' "${swift_source}")" != "1" ]]; then
  echo "The generated iOS UTS bridge must install exactly one replaceable native event handler" >&2
  exit 1
fi

ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun swiftc -typecheck \
  -suppress-warnings \
  -sdk "${ios_sdk}" \
  -target arm64-apple-ios13.0 \
  -F "${ios_output}/Frameworks" \
  -F "${dcloud_ios_frameworks}" \
  "${swift_source}"

printf 'Verified HBuilderX UTS compilation for %s\n' "${archive_path}"
