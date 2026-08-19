#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-android/levixel-${version}.aar"
artifact_stage="${repo_dir}/android-plugins-test/.artifacts"

"${script_dir}/package-native-android.sh"

inspection_dir="$(mktemp -d)"
trap 'rm -rf "${inspection_dir}"' EXIT
unzip -q "${artifact_path}" classes.jar -d "${inspection_dir}"
class_listing="$(jar tf "${inspection_dir}/classes.jar")"
if grep -Eq '(^|/)(nandorojo/modules/galeria|com/chris/galeria)(/|$)' <<<"${class_listing}"; then
    printf '%s\n' "Legacy Galeria package found in ${artifact_path}" >&2
    exit 1
fi
if ! grep -q '^com/sandrox/levixel/LevixelViewerOverlayView.class$' <<<"${class_listing}"; then
    printf '%s\n' "Levixel viewer classes are missing from ${artifact_path}" >&2
    exit 1
fi

mkdir -p "${artifact_stage}"
cp "${artifact_path}" "${artifact_stage}/levixel.aar"
"${repo_dir}/android-plugins-test/gradlew" -p "${repo_dir}/android-plugins-test" :app:assembleDebug
