#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
adapter_dir="${plugin_dir}/adapters/react-native"
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

version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "${adapter_dir}/package.json")"
dist_dir="${plugin_dir}/dist/react-native"
artifact_name="levixel-react-native-${version}.tgz"
artifact_path="${dist_dir}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
work_dir="$(mktemp -d)"
staging_dir="${work_dir}/package"
candidate_dir="${work_dir}/candidate"
candidate_install_path="${artifact_path}.tmp.$$"
checksum_install_path="${checksum_path}.tmp.$$"
cleanup() {
  rm -rf "${work_dir}"
  rm -f "${candidate_install_path}" "${checksum_install_path}"
}
trap cleanup EXIT

"${script_dir}/verify-release-readiness.sh"

if [[ ${allow_dirty} -ne 1 && -n "$(git -C "${plugin_dir}" status --porcelain --untracked-files=all)" ]]; then
  echo "Formal React Native candidates require a clean worktree." >&2
  echo "Commit the reviewed release changes first, or use --allow-dirty for a local rehearsal." >&2
  exit 1
fi

if [[ "${package_version}" != "${version}" ]]; then
  echo "React Native package version ${package_version} does not match plugin version ${version}" >&2
  exit 1
fi

"${script_dir}/verify-react-native-contract.sh"
"${script_dir}/verify-react-native-ios-lifecycle.rb"

android_artifact="${plugin_dir}/dist/native-android/levixel-${version}.aar"
ios_artifact="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
for native_artifact in "${android_artifact}" "${ios_artifact}"; do
  if [[ ! -f "${native_artifact}" ]]; then
    echo "Native artifact is missing: ${native_artifact}" >&2
    echo "Package and verify the native cores before packaging React Native." >&2
    exit 1
  fi
done

"${script_dir}/verify-ios-core-adapter-api.sh" "${ios_artifact}"

mkdir -p "${staging_dir}" "${candidate_dir}" "${dist_dir}"

cp "${adapter_dir}/package.json" "${staging_dir}/package.json"
cp "${adapter_dir}/expo-module.config.json" "${staging_dir}/expo-module.config.json"
cp "${adapter_dir}/SandroxLevixel.podspec" "${staging_dir}/SandroxLevixel.podspec"
cp "${adapter_dir}/README.md" "${staging_dir}/README.md"
cp "${plugin_dir}/CHANGELOG.md" "${staging_dir}/CHANGELOG.md"
cp "${plugin_dir}/LICENSE" "${staging_dir}/LICENSE"
cp "${plugin_dir}/PROVENANCE.md" "${staging_dir}/PROVENANCE.md"
cp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${staging_dir}/THIRD_PARTY_NOTICES.md"
cp -R "${adapter_dir}/src" "${staging_dir}/src"
cp -R "${adapter_dir}/android" "${staging_dir}/android"
cp -R "${adapter_dir}/ios" "${staging_dir}/ios"
mkdir -p \
  "${staging_dir}/android/libs" \
  "${staging_dir}/ios/Frameworks"

cp "${android_artifact}" "${staging_dir}/android/libs/levixel-core.aar"

unzip -q "${ios_artifact}" 'Levixel.xcframework/*' -d "${staging_dir}/ios/Frameworks"

packed_name="$(cd "${staging_dir}" && npm pack --silent --pack-destination "${candidate_dir}")"
packed_path="${candidate_dir}/${packed_name}"
candidate_path="${candidate_dir}/${artifact_name}"
if [[ "${packed_path}" != "${candidate_path}" ]]; then
  mv "${packed_path}" "${candidate_path}"
fi

if ! tar -tzf "${candidate_path}" | grep -E 'package/android/libs/levixel-core\.aar$' >/dev/null; then
  echo "React Native package is missing the Android AAR" >&2
  exit 1
fi
if ! tar -tzf "${candidate_path}" | grep -E 'package/ios/Frameworks/Levixel\.xcframework/Info\.plist$' >/dev/null; then
  echo "React Native package is missing the iOS XCFramework" >&2
  exit 1
fi

checksum="$(shasum -a 256 "${candidate_path}" | awk '{print $1}')"
expected_sidecar="${candidate_path}.sha256"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${expected_sidecar}"
verification_arguments=("${candidate_path}")
if [[ ${allow_dirty} -eq 1 ]]; then
  verification_arguments+=(--allow-dirty)
fi
"${script_dir}/verify-react-native-package.sh" "${verification_arguments[@]}"

install_candidate=1
if [[ -f "${artifact_path}" ]]; then
  if cmp -s "${candidate_path}" "${artifact_path}"; then
    install_candidate=0
    if [[ ! -f "${checksum_path}" ]] || ! cmp -s "${expected_sidecar}" "${checksum_path}"; then
      if [[ ${replace} -eq 1 ]]; then
        install_candidate=1
      else
        echo "The existing React Native checksum sidecar does not match ${artifact_name}." >&2
        echo "Review the candidate, then rerun with --replace." >&2
        exit 1
      fi
    fi
  elif [[ ${replace} -ne 1 ]]; then
    echo "A different React Native ${version} candidate already exists: ${artifact_path}" >&2
    echo "Do not overwrite accepted bytes silently. Review the change, then rerun with --replace." >&2
    exit 1
  fi
fi

if [[ ${install_candidate} -eq 1 ]]; then
  cp "${candidate_path}" "${candidate_install_path}"
  cp "${expected_sidecar}" "${checksum_install_path}"
  mv "${candidate_install_path}" "${artifact_path}"
  mv "${checksum_install_path}" "${checksum_path}"
fi

if [[ ${allow_dirty} -eq 1 ]]; then
  printf '%s\n' "Local dirty-worktree rehearsal completed; do not publish it before clean-commit verification."
fi
printf '%s\n' "${artifact_path}"
