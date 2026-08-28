#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 PLUGIN_MANIFEST" >&2
  exit 1
fi

ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  root_version = manifest.fetch("version")
  targets = manifest.fetch("targets")
  uts = targets.find { |target| target.fetch("id") == "uniapp" }
  abort("UniApp target is missing") unless uts
  uts_version = uts.fetch("version")
  provenance = uts.fetch("constraints", []).select do |constraint|
    constraint.fetch("name") == "native-release-version"
  end
  abort("UniApp must declare exactly one native-release-version constraint") unless provenance.length == 1
  native_version = provenance.fetch(0).fetch("value")
  abort("native-release-version must be a semantic-version string") unless native_version.is_a?(String) && native_version.match?(/\A\d+\.\d+\.\d+\z/)
  legacy = targets.find { |target| target.fetch("id") == "uniapp-native-compat" }
  abort("UniApp legacy target is missing") unless legacy
  legacy_version = legacy.fetch("version", root_version)
  puts [
    uts_version,
    native_version,
    uts.fetch("sourceRoot"),
    legacy_version,
    root_version,
  ].join(" ")
' "$1"
