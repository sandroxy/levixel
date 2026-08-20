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
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"

if [[ ${allow_dirty} -eq 0 ]] && [[ -n "$(git -C "${repo_root}" status --porcelain)" ]]; then
  echo "Release preparation requires a clean worktree. Use --allow-dirty only for local validation." >&2
  exit 1
fi

if [[ ${allow_unsigned} -eq 0 ]] && [[ -z "${LEVIXEL_SIGNING_KEY:-}" ]]; then
  echo "A formal native candidate requires LEVIXEL_SIGNING_KEY for Maven Central." >&2
  echo "Use --allow-unsigned only for local release-pipeline validation." >&2
  exit 1
fi

"${script_dir}/package-native-all.sh"
"${script_dir}/verify-native-all.sh"

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

commit="$(git -C "${repo_root}" rev-parse HEAD)"
dirty=false
if [[ -n "$(git -C "${repo_root}" status --porcelain)" ]]; then
  dirty=true
fi

ruby -rjson -rdigest -e '
  version, commit, dirty, output, *files = ARGV
  payload = {
    schemaVersion: 1,
    plugin: "levixel",
    version: version,
    commit: commit,
    dirty: dirty == "true",
    artifacts: files.map do |file|
      {
        file: File.basename(file),
        bytes: File.size(file),
        sha256: Digest::SHA256.file(file).hexdigest
      }
    end
  }
  File.write(output, JSON.pretty_generate(payload) + "\n")
' "${version}" "${commit}" "${dirty}" "${manifest_path}" "${artifacts[@]}"

printf '%s\n' "${manifest_path}"
printf '%s\n' "${checksums_path}"
