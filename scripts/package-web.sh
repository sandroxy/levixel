#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
web_dir="${plugin_dir}/adapters/web"
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

version="$(ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  target = manifest.fetch("targets").find { |entry| entry.fetch("id") == "web" }
  abort("Web target is missing from plugin.yaml") unless target
  print target.fetch("version", manifest.fetch("version"))
' "${plugin_dir}/plugin.yaml")"
package_version="$(node -e 'process.stdout.write(require(process.argv[1]).version)' "${web_dir}/package.json")"
if [[ "${package_version}" != "${version}" ]]; then
  echo "Web package version ${package_version} does not match target version ${version}." >&2
  exit 1
fi

if [[ ${allow_dirty} -ne 1 && -n "$(git -C "${plugin_dir}" status --porcelain --untracked-files=all)" ]]; then
  echo "Formal Web candidates require a clean worktree." >&2
  echo "Commit the reviewed release changes first, or use --allow-dirty for a local rehearsal." >&2
  exit 1
fi

dist_dir="${plugin_dir}/dist/web"
artifact_name="levixel-web-${version}.tgz"
artifact_path="${dist_dir}/${artifact_name}"
checksum_path="${artifact_path}.sha256"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

"${script_dir}/verify-web.sh"

packed_name="$(cd "${web_dir}" && npm pack --silent --pack-destination "${work_dir}")"
packed_path="${work_dir}/${packed_name}"
if [[ ! -f "${packed_path}" ]]; then
  echo "npm pack did not create the expected Web tarball: ${packed_path}" >&2
  exit 1
fi

mkdir -p "${dist_dir}"
if [[ -f "${artifact_path}" ]]; then
  if cmp -s "${packed_path}" "${artifact_path}"; then
    rm -f "${packed_path}"
  elif [[ ${replace} -eq 1 ]]; then
    mv "${packed_path}" "${artifact_path}"
  else
    echo "A different Web ${version} candidate already exists: ${artifact_path}" >&2
    echo "Do not overwrite accepted bytes silently. Review the change, then rerun with --replace." >&2
    exit 1
  fi
else
  mv "${packed_path}" "${artifact_path}"
fi

if command -v shasum >/dev/null 2>&1; then
  checksum="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
else
  checksum="$(sha256sum "${artifact_path}" | awk '{print $1}')"
fi
expected_sidecar="${work_dir}/${artifact_name}.sha256"
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${expected_sidecar}"
if [[ -f "${checksum_path}" ]] && ! cmp -s "${expected_sidecar}" "${checksum_path}"; then
  if [[ ${replace} -ne 1 ]]; then
    echo "The existing Web checksum sidecar does not match ${artifact_name}." >&2
    echo "Review the candidate, then rerun with --replace." >&2
    exit 1
  fi
fi
cp "${expected_sidecar}" "${checksum_path}"

"${script_dir}/verify-web-package.sh" "${artifact_path}" "${checksum}"

if [[ ${allow_dirty} -eq 1 ]]; then
  printf '%s\n' "Local dirty-worktree rehearsal completed; do not publish it before clean-commit verification."
fi
printf '%s\n' "${artifact_path}"
printf '%s\n' "SHA-256: ${checksum}"
