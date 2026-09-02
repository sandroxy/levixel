#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
allow_dirty=0
replace=0

for argument in "$@"; do
  case "${argument}" in
    --allow-dirty) allow_dirty=1 ;;
    --replace) replace=1 ;;
    *)
      echo "Unknown option: ${argument}" >&2
      echo "Usage: $0 [--allow-dirty] [--replace]" >&2
      exit 1
      ;;
  esac
done

read -r version native_version source_root_relative _ _ < <(
  bash "${script_dir}/resolve-uniapp-product.sh" "${plugin_dir}/plugin.yaml"
)
"${script_dir}/verify-product-release-readiness.sh" \
  "${version}" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/changelog.md"
"${script_dir}/verify-release-metadata.sh"
if [[ "${source_root_relative}" != "uni_modules/Sandrox-Levixel" ]]; then
  echo "UniApp sourceRoot must be uni_modules/Sandrox-Levixel, got ${source_root_relative}" >&2
  exit 1
fi
android_adapter_dir="${plugin_dir}/adapters/uniapp/android"
ios_adapter_dir="${plugin_dir}/adapters/uniapp/ios"
source_root="${plugin_dir}/${source_root_relative}"
artifact_dir="${plugin_dir}/dist/uniapp"
staging_dir="$(mktemp -d)"
package_root="${staging_dir}/package"
archive_name="levixel-uniapp-${version}.zip"
archive_path="${artifact_dir}/${archive_name}"
marketplace_template="${plugin_dir}/adapters/uniapp/MARKETPLACE.md"
marketplace_path="${artifact_dir}/levixel-uniapp-${version}-marketplace.md"
core_android_aar="${plugin_dir}/dist/native-android/levixel-${native_version}.aar"
core_ios_zip="${plugin_dir}/dist/native-ios/levixel-${native_version}.xcframework.zip"
candidate_archive_path="${staging_dir}/${archive_name}"
candidate_checksum_path="${candidate_archive_path}.sha256"
candidate_marketplace_path="${staging_dir}/levixel-uniapp-${version}-marketplace.md"

cleanup() {
  rm -rf "${staging_dir}"
  rm -f \
    "${archive_path}.tmp.$$" \
    "${archive_path}.sha256.tmp.$$" \
    "${marketplace_path}.tmp.$$"
}
trap cleanup EXIT

if [[ ${allow_dirty} -ne 1 && -n "$(git -C "${plugin_dir}" status --porcelain --untracked-files=all)" ]]; then
  echo "Formal UniApp candidates require a clean worktree." >&2
  echo "Commit the reviewed release changes first, or use --allow-dirty for a local rehearsal." >&2
  exit 1
fi

"${script_dir}/sync-uniapp-canonical-js.sh" --check
bash "${script_dir}/verify-documentation.sh"
if [[ ${allow_dirty} -eq 1 ]]; then
  bash "${script_dir}/verify-uniapp-native-provenance.sh" --allow-dirty
else
  bash "${script_dir}/verify-uniapp-native-provenance.sh"
fi

if [[ ! -f "${core_android_aar}" || ! -f "${core_ios_zip}" ]]; then
  echo "Canonical native artifacts for Levixel ${native_version} are missing" >&2
  exit 1
fi

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  abort "UTS package version does not match #{ARGV.fetch(1)}" unless package.fetch("version") == ARGV.fetch(1)
' "${source_root}/package.json" "${version}"

"${plugin_dir}/native/android/gradlew" \
  --quiet \
  -p "${android_adapter_dir}" \
  :levixel-uniapp-runtime:clean \
  :levixel-uniapp-runtime:testReleaseUnitTest \
  :levixel-uniapp-runtime:assembleRelease \
  :levixel-uniapp-runtime:copyUniappBundledAars \
  -PlevixelCoreAar="${core_android_aar}"

LEVIXEL_IOS_XCFRAMEWORK_ZIP="${core_ios_zip}" \
  bash "${ios_adapter_dir}/build-runtime-framework.sh" >/dev/null

mkdir -p "${package_root}"
ditto "${source_root}" "${package_root}"
mkdir -p \
  "${package_root}/utssdk/app-android/libs" \
  "${package_root}/utssdk/app-ios/Frameworks"

cp \
  "${android_adapter_dir}/levixel-uniapp-runtime/build/outputs/aar/levixel-uniapp-runtime-release.aar" \
  "${package_root}/utssdk/app-android/libs/LevixelUniRuntime-${native_version}.aar"
cp \
  "${core_android_aar}" \
  "${package_root}/utssdk/app-android/libs/Levixel-${native_version}.aar"

photoview_aar="$(find "${android_adapter_dir}/levixel-uniapp-runtime/build/uniapp-bundled-aars" -maxdepth 1 -type f -name '*.aar' -print -quit)"
if [[ -z "${photoview_aar}" ]]; then
  echo "PhotoView AAR was not resolved" >&2
  exit 1
fi
cp "${photoview_aar}" "${package_root}/utssdk/app-android/libs/PhotoView-2.3.0.aar"

ditto \
  "${ios_adapter_dir}/build-runtime/Products/LevixelUniRuntime.framework" \
  "${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework"
ditto \
  "${ios_adapter_dir}/build-runtime/Products/Levixel.framework" \
  "${package_root}/utssdk/app-ios/Frameworks/Levixel.framework"

cp "${plugin_dir}/adapters/uniapp/js_sdk/index.d.ts" "${package_root}/js_sdk/index.d.ts"
cp "${plugin_dir}/LICENSE" "${package_root}/LICENSE"
cp "${plugin_dir}/LICENSE" "${package_root}/license.md"
cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"

cmp "${plugin_dir}/adapters/uniapp/js_sdk/index.js" \
  "${source_root}/js_sdk/canonical.js"
cmp "${source_root}/js_sdk/canonical.js" \
  "${package_root}/js_sdk/canonical.js"

(
  cd "${package_root}"
  zip -qry "${candidate_archive_path}" .
)
if command -v shasum >/dev/null 2>&1; then
  checksum="$(shasum -a 256 "${candidate_archive_path}" | awk '{print $1}')"
else
  checksum="$(sha256sum "${candidate_archive_path}" | awk '{print $1}')"
fi
printf '%s  %s\n' "${checksum}" "${archive_name}" > "${candidate_checksum_path}"
ruby "${script_dir}/render-uniapp-marketplace.rb" \
  "${marketplace_template}" \
  "${source_root}/package.json" \
  "${source_root}/changelog.md" \
  "${version}" \
  "${native_version}" \
  "${checksum}" > "${candidate_marketplace_path}"

candidate_files=(
  "${candidate_archive_path}"
  "${candidate_checksum_path}"
  "${candidate_marketplace_path}"
)
published_files=(
  "${archive_path}"
  "${archive_path}.sha256"
  "${marketplace_path}"
)
for index in "${!candidate_files[@]}"; do
  candidate_file="${candidate_files[${index}]}"
  published_file="${published_files[${index}]}"
  if [[ -e "${published_file}" && ! -f "${published_file}" ]]; then
    echo "UniApp candidate target is not a regular file: ${published_file}" >&2
    exit 1
  fi
  if [[ -f "${published_file}" ]] && ! cmp -s "${candidate_file}" "${published_file}"; then
    if [[ ${replace} -ne 1 ]]; then
      echo "A different UniApp ${version} candidate set already exists: ${published_file}" >&2
      echo "Do not overwrite accepted bytes or release material silently. Review the change, then rerun with --replace." >&2
      exit 1
    fi
  fi
done

mkdir -p "${artifact_dir}"
pending_temp_files=()
pending_published_files=()
for index in "${!candidate_files[@]}"; do
  candidate_file="${candidate_files[${index}]}"
  published_file="${published_files[${index}]}"
  if [[ -f "${published_file}" ]] && cmp -s "${candidate_file}" "${published_file}"; then
    continue
  fi
  install_temp="${published_file}.tmp.$$"
  cp "${candidate_file}" "${install_temp}"
  pending_temp_files+=("${install_temp}")
  pending_published_files+=("${published_file}")
done
for index in "${!pending_temp_files[@]}"; do
  mv "${pending_temp_files[${index}]}" "${pending_published_files[${index}]}"
done

if [[ ${allow_dirty} -eq 1 ]]; then
  printf '%s\n' "Local dirty-worktree rehearsal completed; do not publish it before clean-commit verification."
fi
printf '%s\n' "${archive_path}"
printf '%s\n' "SHA-256: ${checksum}"
