#!/usr/bin/env bash
set -euo pipefail

allow_dirty=0
allow_unsigned=0
for argument in "$@"; do
  case "${argument}" in
    --allow-dirty) allow_dirty=1 ;;
    --allow-unsigned) allow_unsigned=1 ;;
    *)
      echo "Usage: $0 [--allow-dirty] [--allow-unsigned]" >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
repository="https://github.com/sandroxy/levixel.git"

for command_name in git ruby shasum tar unzip; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

initial_commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
initial_dirty=false
if [[ -n "$(git -C "${plugin_dir}" status --porcelain)" ]]; then
  initial_dirty=true
fi
if [[ ${allow_dirty} -eq 0 && "${initial_dirty}" == true ]]; then
  echo "Release candidate preparation requires a clean worktree." >&2
  echo "Use --allow-dirty only to create a non-acceptable rehearsal." >&2
  exit 1
fi

"${script_dir}/verify-release-readiness.sh"

native_manifest="${plugin_dir}/dist/native-release/levixel-native-${version}.json"
native_checksums="${plugin_dir}/dist/native-release/levixel-native-${version}-SHA256SUMS"
android_aar="${plugin_dir}/dist/native-android/levixel-${version}.aar"
android_maven="${plugin_dir}/dist/native-android/levixel-${version}-maven.zip"
android_maven_central="${plugin_dir}/dist/native-android/levixel-${version}-maven-central.zip"
ios_xcframework="${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
ios_swift_package="${plugin_dir}/dist/native-ios/levixel-${version}-swift-package.zip"
harmony_har="${plugin_dir}/dist/native-harmonyos/levixel-${version}.har"
react_native_package="${plugin_dir}/dist/react-native/levixel-react-native-${version}.tgz"
uniapp_uts_package="${plugin_dir}/dist/uniapp/levixel-uniapp-${version}.zip"
uniapp_legacy_package="${plugin_dir}/dist/uniapp/levixel-uniapp-legacy-${version}.zip"
uniapp_marketplace="${plugin_dir}/dist/uniapp/levixel-uniapp-${version}-marketplace.md"
web_package="${plugin_dir}/dist/web/levixel-web-${version}.tgz"

artifacts=(
  "${android_aar}"
  "${android_maven}"
  "${ios_xcframework}"
  "${ios_swift_package}"
  "${harmony_har}"
  "${react_native_package}"
  "${uniapp_uts_package}"
  "${uniapp_legacy_package}"
  "${web_package}"
)
for required_path in "${native_manifest}" "${native_checksums}" "${uniapp_marketplace}"; do
  if [[ ! -f "${required_path}" ]]; then
    echo "Required release evidence is missing: ${required_path}" >&2
    exit 1
  fi
done

verify_sidecar() {
  local artifact="$1"
  local sidecar="${artifact}.sha256"
  local expected
  local recorded_name
  local trailing
  local actual
  if [[ ! -f "${artifact}" || ! -f "${sidecar}" ]]; then
    echo "Artifact or checksum sidecar is missing: ${artifact}" >&2
    exit 1
  fi
  read -r expected recorded_name trailing < "${sidecar}"
  actual="$(shasum -a 256 "${artifact}" | awk '{print $1}')"
  if [[ ! "${expected}" =~ ^[0-9a-f]{64}$ ]] \
      || [[ "${recorded_name}" != "$(basename "${artifact}")" ]] \
      || [[ -n "${trailing:-}" ]] \
      || [[ "${actual}" != "${expected}" ]]; then
    echo "Checksum sidecar does not describe ${artifact}." >&2
    exit 1
  fi
}
for artifact in "${artifacts[@]}"; do
  verify_sidecar "${artifact}"
done

read -r native_commit native_dirty native_signed < <(ruby -rjson -rdigest -e '
  path, version, *files = ARGV
  manifest = JSON.parse(File.read(path))
  abort("Unexpected native manifest schema") unless manifest.fetch("schemaVersion") == 1
  abort("Unexpected native manifest plugin") unless manifest.fetch("plugin") == "levixel"
  abort("Unexpected native manifest version") unless manifest.fetch("version") == version
  abort("Native manifest has no signing qualification") unless [true, false].include?(manifest["androidMavenSigned"])
  indexed = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
  files.each do |file|
    entry = indexed.fetch(File.basename(file)) { abort("Native manifest is missing #{File.basename(file)}") }
    abort("Native manifest byte count differs for #{file}") unless entry.fetch("bytes") == File.size(file)
    abort("Native manifest checksum differs for #{file}") unless
      entry.fetch("sha256") == Digest::SHA256.file(file).hexdigest
  end
  puts [manifest.fetch("commit"), manifest.fetch("dirty"), manifest.fetch("androidMavenSigned")].join(" ")
' "${native_manifest}" "${version}" \
  "${android_aar}" "${android_maven}" "${ios_xcframework}" "${ios_swift_package}" "${harmony_har}")

if [[ "${native_commit}" != "${initial_commit}" ]]; then
  echo "Native artifacts came from ${native_commit}, not current commit ${initial_commit}." >&2
  exit 1
fi
if [[ ${allow_unsigned} -eq 0 && "${native_signed}" != true ]]; then
  echo "A formal candidate requires signed Android Maven artifacts." >&2
  echo "Use --allow-unsigned only to create a non-acceptable rehearsal." >&2
  exit 1
fi
if [[ "${native_signed}" == true ]]; then
  verify_sidecar "${android_maven_central}"
  ruby -rjson -rdigest -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    file = ARGV.fetch(1)
    entry = manifest.fetch("artifacts").find { |artifact| artifact.fetch("file") == File.basename(file) }
    abort("Native manifest is missing the Maven Central bundle") unless entry
    abort("Maven Central bundle byte count differs") unless entry.fetch("bytes") == File.size(file)
    abort("Maven Central bundle checksum differs") unless
      entry.fetch("sha256") == Digest::SHA256.file(file).hexdigest
  ' "${native_manifest}" "${android_maven_central}"
  artifacts+=("${android_maven_central}")
fi

react_native_metadata="$(tar -xOf "${react_native_package}" package/package.json)"
web_metadata="$(tar -xOf "${web_package}" package/package.json)"
uniapp_metadata="$(unzip -p "${uniapp_uts_package}" package.json)"
uniapp_legacy_metadata="$(unzip -p "${uniapp_legacy_package}" Sandrox-Levixel/package.json)"
harmony_metadata="$(unzip -p "${harmony_har}" oh-package.json5 2>/dev/null || unzip -p "${harmony_har}" package/oh-package.json5)"
ruby -rjson -e '
  version, rn_raw, web_raw, uni_raw, legacy_raw, harmony_raw = ARGV
  rn = JSON.parse(rn_raw)
  abort("Unexpected React Native package identity") unless
    rn.fetch("name") == "@sandrox/levixel" && rn.fetch("version") == version
  web = JSON.parse(web_raw)
  abort("Unexpected Web package identity") unless
    web.fetch("name") == "@sandrox/levixel-web" && web.fetch("version") == version
  uni = JSON.parse(uni_raw)
  abort("Unexpected UniApp UTS package identity") unless
    uni.fetch("id") == "Sandrox-Levixel" && uni.fetch("version") == version &&
      uni.dig("dcloudext", "type") == "uts"
  legacy = JSON.parse(legacy_raw)
  abort("Unexpected UniApp compatibility package identity") unless
    legacy.fetch("id") == "Sandrox-Levixel" && legacy.fetch("version") == version
  harmony = JSON.parse(harmony_raw)
  abort("Unexpected HarmonyOS package identity") unless
    harmony.fetch("name") == "@sandrox/levixel" && harmony.fetch("version") == version
' "${version}" "${react_native_metadata}" "${web_metadata}" "${uniapp_metadata}" \
  "${uniapp_legacy_metadata}" "${harmony_metadata}"

commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
dirty=false
if [[ -n "$(git -C "${plugin_dir}" status --porcelain)" ]]; then
  dirty=true
fi
if [[ ${allow_dirty} -eq 0 ]] \
    && { [[ "${dirty}" == true ]] || [[ "${commit}" != "${initial_commit}" ]]; }; then
  echo "The source revision changed while preparing the release candidate." >&2
  exit 1
fi

state=candidate
output_root="${plugin_dir}/dist/candidates"
if [[ "${dirty}" == true || "${native_dirty}" == true || "${native_signed}" != true ]]; then
  state=rehearsal
  output_root="${plugin_dir}/dist/rehearsals"
fi

snapshot_arguments=(
  --plugin levixel
  --version "${version}"
  --repository "${repository}"
  --commit "${commit}"
  --dirty "${dirty}"
  --root "${plugin_dir}"
  --output-root "${output_root}"
  --state "${state}"
  --qualification "androidMavenSigned=${native_signed}"
  --qualification nativeManifestVerified=true
  --qualification packageIdentitiesVerified=true
  --qualification versionUnpublished=true
  --artifact "native-android-aar=${android_aar}"
  --artifact "native-android-maven-repository=${android_maven}"
  --artifact "native-ios-xcframework=${ios_xcframework}"
  --artifact "native-ios-swift-package=${ios_swift_package}"
  --artifact "native-harmonyos-har=${harmony_har}"
  --artifact "react-native-package=${react_native_package}"
  --artifact "uniapp-uts-package=${uniapp_uts_package}"
  --artifact "uniapp-legacy-package=${uniapp_legacy_package}"
  --artifact "uniapp-marketplace-material=${uniapp_marketplace}"
  --artifact "web-package=${web_package}"
  --artifact "native-build-manifest=${native_manifest}"
  --artifact "native-build-checksums=${native_checksums}"
)
if [[ "${native_signed}" == true ]]; then
  snapshot_arguments+=(--artifact "native-android-maven-central-bundle=${android_maven_central}")
fi
for artifact in "${artifacts[@]}"; do
  role="$(basename "${artifact}" | tr '[:upper:]_.' '[:lower:]--')"
  snapshot_arguments+=(--artifact "checksum-${role}=${artifact}.sha256")
done

"${script_dir}/snapshot-release-candidate.rb" "${snapshot_arguments[@]}"
if [[ "${state}" == rehearsal ]]; then
  echo "Created a rehearsal. It is intentionally ineligible for release acceptance." >&2
fi
