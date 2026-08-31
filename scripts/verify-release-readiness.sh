#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"

"${script_dir}/assert-release-version-available.sh" "${version}" --check-origin
"${script_dir}/verify-release-metadata.sh"

ruby -rdate -e '
  version = ARGV.shift
  ARGV.each do |path|
    heading = File.readlines(path, chomp: true).find { |line| line.start_with?("## ") }
    expected = /\A## #{Regexp.escape(version)} - (\d{4}-\d{2}-\d{2})\z/
    match = heading&.match(expected)
    abort("#{path} must put ## #{version} - YYYY-MM-DD first; found #{heading.inspect}") unless match
    Date.iso8601(match[1])
  rescue ArgumentError
    abort("#{path} contains an invalid release date: #{match && match[1]}")
  end
' "${version}" \
  "${plugin_dir}/CHANGELOG.md" \
  "${plugin_dir}/native/harmonyos/levixel/CHANGELOG.md"

printf '%s\n' "Release metadata is ready for an immutable ${version} candidate."
