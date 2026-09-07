#!/usr/bin/env bash
set -euo pipefail

allow_dirty=0
allow_unsigned=0
reuse_candidate=""
reuse_groups=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --allow-dirty) allow_dirty=1; shift ;;
    --allow-unsigned) allow_unsigned=1; shift ;;
    --reuse-candidate) reuse_candidate="${2:?Missing candidate path}"; shift 2 ;;
    --reuse) reuse_groups+=("${2:?Missing reuse group}"); shift 2 ;;
    *)
      echo "Usage: $0 [--allow-dirty] [--allow-unsigned] [--reuse-candidate FILE --reuse GROUP ...]" >&2
      exit 1
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
initial_commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
reuse_proof=""
reuses_maven=0
if [[ -n "${reuse_candidate}" || ${#reuse_groups[@]} -gt 0 ]]; then
  if [[ -z "${reuse_candidate}" || ${#reuse_groups[@]} -eq 0 || ${allow_dirty} -ne 0 || ${allow_unsigned} -ne 0 ]]; then
    echo "Reuse requires an explicit candidate and groups, with no rehearsal flags." >&2
    exit 1
  fi
  if [[ -n "${LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_ZIP:-}" || -n "${LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_SHA256:-}" || -n "${LEVIXEL_IOS_BINARY_URL:-}" ]]; then
    echo "Candidate reuse cannot be mixed with iOS artifact or binary URL overrides." >&2
    exit 1
  fi
  reuses_maven="$(ruby -I "${script_dir}" -r native-artifact-reuse -e '
    groups = NativeArtifactReuse.groups
    abort("Unknown or duplicate reuse groups") unless ARGV.uniq == ARGV && (ARGV - groups.keys).empty?
    puts ARGV.any? { |name| groups.fetch(name).fetch("roles").include?("native-android-maven-central-bundle") } ? 1 : 0
  ' "${reuse_groups[@]}")"
fi

if [[ ${allow_dirty} -eq 0 ]] && [[ -n "$(git -C "${plugin_dir}" status --porcelain)" ]]; then
  echo "Release preparation requires a clean worktree. Use --allow-dirty only for local validation." >&2
  exit 1
fi

if [[ ${allow_unsigned} -eq 0 && ${reuses_maven} -eq 0 ]] \
    && { [[ -z "${LEVIXEL_SIGNING_KEY:-}" ]] || [[ -z "${LEVIXEL_SIGNING_PASSWORD:-}" ]]; }; then
  echo "A formal native candidate requires LEVIXEL_SIGNING_KEY and LEVIXEL_SIGNING_PASSWORD for Maven Central." >&2
  echo "Use --allow-unsigned only for local release-pipeline validation." >&2
  exit 1
fi

if [[ -n "${reuse_candidate}" ]]; then
  "${script_dir}/verify-release-readiness.sh"
  reuse_work="$(mktemp -d)"
  trap 'rm -rf "${reuse_work}"' EXIT
  reuse_proof="${reuse_work}/proof.json"
  reuse_arguments=(--candidate "${reuse_candidate}" --proof "${reuse_proof}")
  for group in "${reuse_groups[@]}"; do
    reuse_arguments+=(--group "${group}")
  done
  ruby "${script_dir}/reuse-native-artifacts.rb" "${reuse_arguments[@]}"
  build_groups="$(ruby -I "${script_dir}" -r native-artifact-reuse -e '
    puts NativeArtifactReuse.groups.keys - ARGV
  ' "${reuse_groups[@]}")"
  while IFS= read -r group; do
    [[ -n "${group}" ]] || continue
    "${script_dir}/package-native-${group}.sh"
  done <<< "${build_groups}"
else
  "${script_dir}/package-native-all.sh"
fi
"${script_dir}/verify-native-all.sh"
android_maven_signed=false
if [[ ${reuses_maven} -eq 1 ]]; then
  android_maven_signed=true
elif [[ -n "${LEVIXEL_SIGNING_KEY:-}" && -n "${LEVIXEL_SIGNING_PASSWORD:-}" ]]; then
  "${script_dir}/prepare-maven-central-bundle.sh"
  android_maven_signed=true
fi

release_dir="${plugin_dir}/dist/native-release"
manifest_path="${release_dir}/levixel-native-${version}.json"
checksums_path="${release_dir}/levixel-native-${version}-SHA256SUMS"
mkdir -p "${release_dir}"

artifacts=(
  "${plugin_dir}/dist/native-android/levixel-${version}.aar"
  "${plugin_dir}/dist/native-android/levixel-${version}-maven.zip"
  "${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip"
  "${plugin_dir}/dist/native-ios/levixel-${version}-swift-package.zip"
  "${plugin_dir}/dist/native-harmonyos/levixel-${version}.har"
)
if [[ "${android_maven_signed}" == true ]]; then
  artifacts+=("${plugin_dir}/dist/native-android/levixel-${version}-maven-central.zip")
fi

for artifact in "${artifacts[@]}"; do
  if [[ ! -f "${artifact}" ]]; then
    echo "Release artifact is missing: ${artifact}" >&2
    exit 1
  fi
done

(
  cd "${plugin_dir}"
  for artifact in "${artifacts[@]}"; do
    shasum -a 256 "${artifact}" | sed "s|  ${plugin_dir}/|  |"
  done
) > "${checksums_path}"

commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
ios_source_digest="$("${script_dir}/compute-ios-source-digest.rb")"
read -r ios_source_commit embedded_ios_source_digest < <(
  "${script_dir}/verify-ios-xcframework-provenance.sh" \
    "${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip" \
    "${version}" "${ios_source_digest}"
)
dirty=false
if [[ -n "$(git -C "${plugin_dir}" status --porcelain)" ]]; then
  dirty=true
fi
if [[ ${allow_dirty} -eq 0 ]] \
    && { [[ "${dirty}" == true ]] || [[ "${commit}" != "${initial_commit}" ]]; }; then
  echo "The source revision changed while preparing the native candidate." >&2
  exit 1
fi
ruby -I "${script_dir}" -rjson -rdigest -r native-release-manifest -e '
  version, commit, dirty, signed, ios_commit, ios_digest, output, reuse_proof, root, *files = ARGV
  payload = {
    "schemaVersion" => 2,
    "plugin" => "levixel",
    "version" => version,
    "commit" => commit,
    "dirty" => dirty == "true",
    "androidMavenSigned" => signed == "true",
    "buildProvenance" => {
      "iosXcframework" => {
        "sourceCommit" => ios_commit,
        "sourceDigest" => ios_digest
      }
    },
    "artifacts" => files.map do |file|
      {
        "file" => File.basename(file),
        "bytes" => File.size(file),
        "sha256" => Digest::SHA256.file(file).hexdigest
      }
    end
  }
  unless reuse_proof.empty?
    proof = JSON.parse(File.read(reuse_proof))
    payload.fetch("buildProvenance")["artifactReuse"] = proof
    NativeArtifactReuse.verify_inputs!(proof, root: root, commit: commit)
  end
  NativeReleaseManifest.validate!(payload, plugin: "levixel", version: version)
  File.write(output, JSON.pretty_generate(payload) + "\n")
' "${version}" "${commit}" "${dirty}" "${android_maven_signed}" \
  "${ios_source_commit}" "${embedded_ios_source_digest}" \
  "${manifest_path}" "${reuse_proof}" "${plugin_dir}" "${artifacts[@]}"

"${script_dir}/verify-native-manifest-ios-provenance.sh" \
  "${manifest_path}" \
  "${plugin_dir}/dist/native-ios/levixel-${version}.xcframework.zip" \
  "${version}"

printf '%s\n' "${manifest_path}"
printf '%s\n' "${checksums_path}"
