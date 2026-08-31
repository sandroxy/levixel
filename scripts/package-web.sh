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
"${script_dir}/verify-product-release-readiness.sh" \
  "${version}" \
  "${web_dir}/CHANGELOG.md"
"${script_dir}/verify-release-metadata.sh"
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
candidate_path="${work_dir}/${artifact_name}"
candidate_checksum_path="${candidate_path}.sha256"
artifact_install_path="${artifact_path}.tmp.$$"
checksum_install_path="${checksum_path}.tmp.$$"
cleanup() {
  rm -rf "${work_dir}"
  rm -f "${artifact_install_path}" "${checksum_install_path}"
}
trap cleanup EXIT

"${script_dir}/verify-web.sh"

packed_name="$(cd "${web_dir}" && npm pack --silent --pack-destination "${work_dir}")"
packed_path="${work_dir}/${packed_name}"
if [[ ! -f "${packed_path}" ]]; then
  echo "npm pack did not create the expected Web tarball: ${packed_path}" >&2
  exit 1
fi
if [[ "${packed_path}" != "${candidate_path}" ]]; then
  mv "${packed_path}" "${candidate_path}"
fi

if command -v shasum >/dev/null 2>&1; then
  checksum="$(shasum -a 256 "${candidate_path}" | awk '{print $1}')"
else
  checksum="$(sha256sum "${candidate_path}" | awk '{print $1}')"
fi
printf '%s  %s\n' "${checksum}" "${artifact_name}" > "${candidate_checksum_path}"

"${script_dir}/verify-web-package.sh" "${candidate_path}" "${checksum}"

install_candidate=1
if [[ -f "${artifact_path}" ]]; then
  if cmp -s "${candidate_path}" "${artifact_path}"; then
    install_candidate=0
    if [[ ! -f "${checksum_path}" ]] || ! cmp -s "${candidate_checksum_path}" "${checksum_path}"; then
      if [[ ${replace} -eq 1 ]]; then
        install_candidate=1
      else
        echo "The existing Web checksum sidecar does not match ${artifact_name}." >&2
        echo "Review the candidate, then rerun with --replace." >&2
        exit 1
      fi
    fi
  elif [[ ${replace} -ne 1 ]]; then
    echo "A different Web ${version} candidate already exists: ${artifact_path}" >&2
    echo "Do not overwrite accepted bytes silently. Review the change, then rerun with --replace." >&2
    exit 1
  fi
fi

if [[ ${install_candidate} -eq 1 ]]; then
  mkdir -p "${dist_dir}"
  cp "${candidate_path}" "${artifact_install_path}"
  cp "${candidate_checksum_path}" "${checksum_install_path}"
  mv "${artifact_install_path}" "${artifact_path}"
  mv "${checksum_install_path}" "${checksum_path}"
fi

if [[ ! -f "${artifact_path}" || ! -f "${checksum_path}" ]]; then
  echo "Web candidate installation did not complete: ${artifact_path}" >&2
  exit 1
fi

if [[ ${allow_dirty} -eq 1 ]]; then
  printf '%s\n' "Local dirty-worktree rehearsal completed; do not publish it before clean-commit verification."
fi
printf '%s\n' "${artifact_path}"
printf '%s\n' "SHA-256: ${checksum}"
