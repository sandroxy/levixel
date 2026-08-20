#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_dir="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
artifact_path="${plugin_dir}/dist/native-android/levixel-${version}.aar"
repository_path="${plugin_dir}/dist/native-android/levixel-${version}-maven.zip"
artifact_stage="${repo_dir}/android-plugins-test/.artifacts"

if [[ "${LEVIXEL_SKIP_PACKAGE:-0}" != "1" ]]; then
    "${script_dir}/package-native-android.sh"
fi

if [[ ! -f "${artifact_path}" || ! -f "${repository_path}" ]]; then
    printf '%s\n' "Packaged Android artifacts are missing." >&2
    exit 1
fi

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
if ! grep -q '^META-INF/LEVIXEL_LICENSE$' <<<"${class_listing}" \
    || ! grep -q '^META-INF/THIRD_PARTY_NOTICES.md$' <<<"${class_listing}"; then
    printf '%s\n' "Levixel legal notices are missing from ${artifact_path}" >&2
    exit 1
fi

rm -rf "${artifact_stage}"
mkdir -p "${artifact_stage}/maven"
unzip -q "${repository_path}" -d "${artifact_stage}/maven"

version_dir="${artifact_stage}/maven/io/gitee/sandrox/levixel/${version}"
pom_path="${version_dir}/levixel-${version}.pom"
if [[ ! -f "${pom_path}" ]]; then
    printf '%s\n' "Levixel Maven POM is missing from ${repository_path}" >&2
    exit 1
fi
if ! rg -q '<groupId>io\.gitee\.sandrox</groupId>' "${pom_path}" \
    || ! rg -q '<artifactId>levixel</artifactId>' "${pom_path}"; then
    printf '%s\n' "Levixel Maven POM has unexpected coordinates" >&2
    exit 1
fi
if ! rg -q '<artifactId>PhotoView</artifactId>' "${pom_path}"; then
    printf '%s\n' "Levixel Maven POM is missing runtime dependency metadata" >&2
    exit 1
fi

for classifier in sources javadoc; do
    classified_jar="${version_dir}/levixel-${version}-${classifier}.jar"
    if [[ ! -f "${classified_jar}" ]] \
        || ! jar tf "${classified_jar}" | grep -q '^META-INF/LEVIXEL_LICENSE$' \
        || ! jar tf "${classified_jar}" | grep -q '^META-INF/THIRD_PARTY_NOTICES.md$'; then
        printf '%s\n' "Levixel ${classifier} JAR is missing legal notices" >&2
        exit 1
    fi
done

"${repo_dir}/android-plugins-test/gradlew" \
    -p "${repo_dir}/android-plugins-test" \
    -PlevixelVersion="${version}" \
    :app:assembleDebug
