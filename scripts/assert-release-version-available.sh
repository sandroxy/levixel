#!/usr/bin/env bash
set -euo pipefail

check_origin=0
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 VERSION [--check-origin]" >&2
  exit 1
fi

version="$1"
if [[ $# -eq 2 ]]; then
  if [[ "$2" != "--check-origin" ]]; then
    echo "Usage: $0 VERSION [--check-origin]" >&2
    exit 1
  fi
  check_origin=1
fi

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Only stable semantic versions can become public release identities: ${version}" >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
tag_ref="refs/tags/${version}"

if git -C "${plugin_dir}" show-ref --verify --quiet "${tag_ref}"; then
  tag_commit="$(git -C "${plugin_dir}" rev-parse "${version}^{commit}")"
  echo "Release version ${version} is already claimed by ${tag_ref} (${tag_commit})." >&2
  echo "Published versions are immutable; choose a new version before building release artifacts." >&2
  exit 1
fi

if [[ ${check_origin} -eq 1 ]]; then
  if ! git -C "${plugin_dir}" remote get-url origin >/dev/null 2>&1; then
    echo "Cannot prove that ${version} is unused because the origin remote is missing." >&2
    exit 1
  fi

  set +e
  remote_output="$(git -C "${plugin_dir}" ls-remote --exit-code --tags origin "${tag_ref}" 2>&1)"
  remote_status=$?
  set -e
  case "${remote_status}" in
    0)
      echo "Release version ${version} already exists on origin:" >&2
      printf '%s\n' "${remote_output}" >&2
      echo "Published versions are immutable; choose a new version before building release artifacts." >&2
      exit 1
      ;;
    2)
      ;;
    *)
      echo "Could not verify whether ${tag_ref} already exists on origin." >&2
      echo "Release preparation fails closed when the canonical tag state cannot be verified." >&2
      exit 1
      ;;
  esac
fi

printf '%s\n' "Release version is available: ${version}"
