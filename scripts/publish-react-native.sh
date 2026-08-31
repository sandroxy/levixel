#!/usr/bin/env bash
set -euo pipefail

mode="--dry-run"
candidate_manifest=""
acceptance_receipt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--publish)
      mode="$1"
      shift
      ;;
    --candidate)
      candidate_manifest="${2:-}"
      shift 2
      ;;
    --acceptance)
      acceptance_receipt="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: $0 [--dry-run|--publish] --candidate /absolute/candidate.json --acceptance /absolute/accepted-receipt.json" >&2
      exit 1
      ;;
  esac
done
if [[ -z "${candidate_manifest}" || -z "${acceptance_receipt}" ]]; then
  echo "Publication requires the accepted candidate manifest and receipt." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_name="@sandrox/levixel"
release_tag="refs/tags/${version}"
registry="https://registry.npmjs.org/"

"${script_dir}/verify-publish-candidate.rb" \
  --candidate "${candidate_manifest}" \
  --acceptance "${acceptance_receipt}" >/dev/null
artifact_path="$(ruby -rjson -rpathname -e '
  manifest_path = Pathname.new(ARGV.fetch(0)).realpath
  manifest = JSON.parse(manifest_path.read)
  entry = manifest.fetch("artifacts").find do |artifact|
    artifact.fetch("role") == "react-native-package"
  end
  abort("Accepted candidate has no React Native package") unless entry
  puts manifest_path.parent.join(entry.fetch("file"))
' "${candidate_manifest}")"

if [[ -n "$(git -C "${plugin_dir}" status --porcelain --untracked-files=all)" ]]; then
  echo "React Native publication requires a clean worktree." >&2
  exit 1
fi

head_commit="$(git -C "${plugin_dir}" rev-parse HEAD)"
tag_commit="$(git -C "${plugin_dir}" rev-list -n 1 "${release_tag}" 2>/dev/null || true)"
if [[ "${tag_commit}" != "${head_commit}" ]]; then
  echo "Canonical tag ${version} must point to the current commit before publication." >&2
  exit 1
fi

tar -xOf "${artifact_path}" package/package.json | ruby -rjson -e '
  package = JSON.parse($stdin.read)
  abort("Accepted React Native package has the wrong identity") unless
    package.fetch("name") == ARGV.fetch(0) && package.fetch("version") == ARGV.fetch(1)
' "${package_name}" "${version}"

if [[ "${mode}" == "--dry-run" ]]; then
  npm publish "${artifact_path}" \
    --access public \
    --registry "${registry}" \
    --dry-run
  exit 0
fi

npm whoami --registry "${registry}" >/dev/null

set +e
view_output="$(npm view "${package_name}@${version}" version --registry "${registry}" 2>&1)"
view_status=$?
set -e
if [[ ${view_status} -eq 0 ]]; then
  echo "${package_name}@${version} is already published and cannot be replaced." >&2
  exit 1
fi
if ! grep -q 'E404' <<<"${view_output}"; then
  echo "Could not confirm that ${package_name}@${version} is unpublished:" >&2
  echo "${view_output}" >&2
  exit 1
fi

npm publish "${artifact_path}" \
  --access public \
  --registry "${registry}"

printf '%s\n' "Published ${package_name}@${version} from ${artifact_path}"
