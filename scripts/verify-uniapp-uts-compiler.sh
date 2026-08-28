#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
read -r version _ _ _ _ < <(
  bash "${script_dir}/resolve-uniapp-product.sh" "${plugin_dir}/plugin.yaml"
)
archive_path="${1:-${plugin_dir}/dist/uniapp/levixel-uniapp-${version}.zip}"
hbuilder_contents="${HBUILDERX_CONTENTS:-/Applications/HBuilderX.app/Contents/HBuilderX}"
hbuilder_node="${HBUILDERX_NODE:-${hbuilder_contents}/plugins/node/node}"
uts_compiler="${hbuilder_contents}/plugins/uniapp-uts-v1/node_modules/@dcloudio/uni-uts-v1"
runextension_dir="${hbuilder_contents}/plugins/uniapp-runextension"
classic_android_libs="${runextension_dir}/lib"
kotlinc="${runextension_dir}/kotlinc/bin/kotlinc"
kotlin_plugin="${uts_compiler}/lib/kotlin/lib/uts-kotlin-compiler-plugin.jar"
dcloud_ios_frameworks="${hbuilder_contents}/plugins/launcher/base/Pandora_simulator.app/Frameworks"
x_android_sdk_root="${DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT:-}"
x_ios_sdk_root="${DCLOUD_UNIAPP_X_IOS_SDK_ROOT:-}"
x_android_libs="${x_android_sdk_root}/SDK/libs"
x_ios_libs="${x_ios_sdk_root}/SDK/Libs"
work_dir="$(mktemp -d)"

cleanup() {
  rm -rf "${work_dir}"
}
trap cleanup EXIT

if [[ -z "${x_android_sdk_root}" || -z "${x_ios_sdk_root}" ]]; then
  echo "Set DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT and DCLOUD_UNIAPP_X_IOS_SDK_ROOT to the extracted official SDK roots." >&2
  exit 1
fi

for required_path in \
  "${archive_path}" \
  "${hbuilder_node}" \
  "${uts_compiler}/dist/index.js" \
  "${kotlinc}" \
  "${kotlin_plugin}" \
  "${classic_android_libs}/android_36.jar" \
  "${classic_android_libs}/kotlin-stdlib-2.2.0.jar" \
  "${classic_android_libs}/kotlinx-coroutines-core-jvm-1.6.4.jar" \
  "${classic_android_libs}/utsplugin-release.jar" \
  "${dcloud_ios_frameworks}/DCloudUTSFoundation.framework" \
  "${x_android_libs}/app-common-release.aar" \
  "${x_android_libs}/app-runtime-release.aar" \
  "${x_android_libs}/framework-release.aar" \
  "${x_android_libs}/uts-runtime-release.aar" \
  "${x_ios_libs}/DCloudUTSFoundation.xcframework/ios-arm64/DCloudUTSFoundation.framework" \
  "${x_ios_libs}/DCloudUniappRuntime.xcframework/ios-arm64/DCloudUniappRuntime.framework"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "UTS compiler verification dependency is missing: ${required_path}" >&2
    exit 1
  fi
done

package_root="${work_dir}/input/uni_modules/Sandrox-Levixel"
mkdir -p "${package_root}"
unzip -q "${archive_path}" -d "${package_root}"
if [[ ! -f "${package_root}/package.json" ]]; then
  echo "package.json is missing from the Marketplace ZIP root: ${archive_path}" >&2
  exit 1
fi

compile_uts() {
  local platform="$1"
  local runtime="$2"
  local is_x="false"
  if [[ "${runtime}" == "x" ]]; then
    is_x="true"
  fi
  local output_dir="${work_dir}/output-${runtime}-${platform}"
  mkdir -p "${output_dir}"
  UNI_INPUT_DIR="${work_dir}/input" \
  UNI_OUTPUT_DIR="${output_dir}" \
  UNI_UTS_PLATFORM="${platform}" \
  UNI_APP_X="${is_x}" \
  NODE_ENV=production \
    "${hbuilder_node}" - "${uts_compiler}" "${package_root}" "${is_x}" <<'NODE'
const compiler = require(process.argv[2])
const pluginDir = process.argv[3]
const isX = process.argv[4] === 'true'

compiler.compile(pluginDir, {
  isX,
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

compile_uts app-android classic
compile_uts app-ios classic
compile_uts app-android x
compile_uts app-ios x

extract_aar_classes() {
  local output_dir="$1"
  shift
  mkdir -p "${output_dir}"
  local aar
  for aar in "$@"; do
    local aar_name
    aar_name="$(basename "${aar}" .aar)"
    local aar_dir="${output_dir}/${aar_name}"
    mkdir -p "${aar_dir}"
    unzip -qo "${aar}" classes.jar -d "${aar_dir}"
  done
}

verify_android_output() {
  local runtime="$1"
  local android_output="${work_dir}/output-${runtime}-app-android/uni_modules/Sandrox-Levixel/utssdk/app-android"
  local kotlin_source="${android_output}/src/index.kt"
  if [[ ! -f "${kotlin_source}" ]]; then
    echo "HBuilderX did not generate the ${runtime} Android UTS bridge" >&2
    exit 1
  fi
  if ! grep -Eq 'UTSAndroid\.getResourcePath' "${kotlin_source}" || \
    ! grep -Eq 'UTSAndroid\.convert2AbsFullPath' "${kotlin_source}" || \
    ! grep -Eq 'uni_modules/' "${kotlin_source}" || \
    ! grep -Eq 'resolveLevixelNativePaths' "${kotlin_source}"; then
    echo "The generated ${runtime} Android bridge is missing local path conversion" >&2
    exit 1
  fi

  local extracted_libs="${work_dir}/android-libs-${runtime}"
  local plugin_aars=("${android_output}"/libs/*.aar)
  extract_aar_classes "${extracted_libs}" "${plugin_aars[@]}"
  if [[ "${runtime}" == "x" ]]; then
    extract_aar_classes "${extracted_libs}" \
      "${x_android_libs}/app-common-release.aar" \
      "${x_android_libs}/app-runtime-release.aar" \
      "${x_android_libs}/framework-release.aar" \
      "${x_android_libs}/uts-runtime-release.aar"
  fi

  local classpath_inputs=("${classic_android_libs}" "${extracted_libs}")
  if [[ "${runtime}" == "x" ]]; then
    classpath_inputs=(
      "${classic_android_libs}/android_36.jar"
      "${classic_android_libs}/kotlin-stdlib-2.2.0.jar"
      "${classic_android_libs}/kotlinx-coroutines-core-jvm-1.6.4.jar"
      "${extracted_libs}"
    )
  fi

  local kotlin_classpath
  kotlin_classpath="$(find "${classpath_inputs[@]}" \
    -type f -name '*.jar' -print | sort | paste -sd: -)"
  if [[ "${runtime}" == "x" ]]; then
    if [[ ":${kotlin_classpath}:" == *":${classic_android_libs}/utsplugin-release.jar:"* ]]; then
      echo "The uni-app x classpath must not include the classic UTS API provider" >&2
      exit 1
    fi
    local uts_android_providers=0
    local classpath_entry
    while IFS= read -r classpath_entry; do
      if jar tf "${classpath_entry}" 2>/dev/null | grep -Fx 'io/dcloud/uts/UTSAndroid.class' >/dev/null; then
        uts_android_providers=$((uts_android_providers + 1))
      fi
    done < <(tr ':' '\n' <<< "${kotlin_classpath}")
    if [[ "${uts_android_providers}" != "1" ]]; then
      echo "The uni-app x classpath must expose exactly one UTSAndroid provider; found ${uts_android_providers}" >&2
      exit 1
    fi
  fi
  local classes_dir="${work_dir}/android-classes-${runtime}"
  "${kotlinc}" \
    -classpath "${kotlin_classpath}" \
    -d "${classes_dir}" \
    -Xplugin="${kotlin_plugin}" \
    -P plugin:io.dcloud.uts.kotlin:tag=UTS \
    -P plugin:io.dcloud.uts.kotlin:console=true \
    "${kotlin_source}"

  if [[ ! -f "${classes_dir}/uts/sdk/modules/SandroxLevixel/IndexKt.class" ]]; then
    echo "Kotlin compilation did not produce the ${runtime} UTS entry class" >&2
    exit 1
  fi
}

verify_ios_source_contract() {
  local runtime="$1"
  local swift_source="$2"
  if grep -Eq 'getCurrentViewController' "${swift_source}"; then
    echo "The generated ${runtime} iOS UTS bridge must use the shared runtime context fallback" >&2
    exit 1
  fi
  if ! grep -Eq 'openJSON\(optionsJson, rootView: nil, viewController: nil' "${swift_source}"; then
    echo "The generated ${runtime} iOS bridge is not using the shared runtime context fallback" >&2
    exit 1
  fi
  if grep -Eq 'retainedEventCallback' "${swift_source}"; then
    echo "The generated ${runtime} iOS bridge must not retain a second event callback slot" >&2
    exit 1
  fi
  if [[ "$(awk '/LevixelUniPresenter\.shared\.setJSONEventHandler/ { count++ } END { print count + 0 }' "${swift_source}")" != "1" ]]; then
    echo "The generated ${runtime} iOS bridge must install exactly one replaceable native event handler" >&2
    exit 1
  fi
  if ! grep -Eq 'UTSiOS\.convert2AbsFullPath' "${swift_source}"; then
    echo "The generated ${runtime} iOS bridge is missing local path conversion" >&2
    exit 1
  fi
  if ! grep -Eq 'resolveLevixelNativePaths' "${swift_source}"; then
    echo "The generated ${runtime} iOS bridge is missing batch local path conversion" >&2
    exit 1
  fi
}

verify_android_output classic
verify_android_output x

classic_ios_output="${work_dir}/output-classic-app-ios/uni_modules/Sandrox-Levixel/utssdk/app-ios"
x_ios_output="${work_dir}/output-x-app-ios/uni_modules/Sandrox-Levixel/utssdk/app-ios"
classic_swift_source="${classic_ios_output}/src/index.swift"
x_swift_source="${x_ios_output}/src/index.swift"
for swift_source in "${classic_swift_source}" "${x_swift_source}"; do
  if [[ ! -f "${swift_source}" ]]; then
    echo "HBuilderX did not generate an iOS UTS bridge: ${swift_source}" >&2
    exit 1
  fi
done
verify_ios_source_contract classic "${classic_swift_source}"
verify_ios_source_contract x "${x_swift_source}"

ios_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun swiftc -typecheck \
  -suppress-warnings \
  -sdk "${ios_sdk}" \
  -target arm64-apple-ios13.0 \
  -F "${classic_ios_output}/Frameworks" \
  -F "${dcloud_ios_frameworks}" \
  "${classic_swift_source}"
xcrun swiftc -typecheck \
  -suppress-warnings \
  -sdk "${ios_sdk}" \
  -target arm64-apple-ios15.0 \
  -F "${x_ios_output}/Frameworks" \
  -F "${x_ios_libs}/DCloudUTSFoundation.xcframework/ios-arm64" \
  -F "${x_ios_libs}/DCloudUniappRuntime.xcframework/ios-arm64" \
  "${x_swift_source}"

printf 'Verified HBuilderX classic and uni-app x UTS compilation for %s\n' "${archive_path}"
