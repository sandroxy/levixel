#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 VERSION CHANGELOG" >&2
  exit 1
fi

version="$1"
changelog="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "${changelog}" ]]; then
  echo "Release changelog does not exist: ${changelog}" >&2
  exit 1
fi

"${script_dir}/assert-release-version-available.sh" "${version}" --check-origin

ruby -e '
  version, path = ARGV
  heading = File.readlines(path, chomp: true).find { |line| line.start_with?("## ") }
  expected = "## #{version}"
  abort("#{path} must put #{expected} first; found #{heading.inspect}") unless heading == expected
' "${version}" "${changelog}"

printf '%s\n' "Product metadata is ready for an immutable ${version} candidate."
