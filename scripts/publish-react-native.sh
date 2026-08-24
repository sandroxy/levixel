#!/usr/bin/env bash
set -euo pipefail

mode="${1:---dry-run}"
if [[ "${mode}" != "--dry-run" && "${mode}" != "--publish" ]]; then
  echo "Usage: $0 [--dry-run|--publish]" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${plugin_dir}/../.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_name="@sandrox/levixel"
artifact_path="${plugin_dir}/dist/react-native/levixel-react-native-${version}.tgz"
release_tag="levixel-react-native-v${version}"
registry="https://registry.npmjs.org/"

if [[ -n "$(git -C "${repo_root}" status --porcelain --untracked-files=all)" ]]; then
  echo "React Native publication requires a clean worktree." >&2
  exit 1
fi

head_commit="$(git -C "${repo_root}" rev-parse HEAD)"
tag_commit="$(git -C "${repo_root}" rev-list -n 1 "${release_tag}" 2>/dev/null || true)"
if [[ "${tag_commit}" != "${head_commit}" ]]; then
  echo "Tag ${release_tag} must point to the current commit before publication." >&2
  exit 1
fi

"${script_dir}/verify-react-native-package.sh" "${artifact_path}"

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
