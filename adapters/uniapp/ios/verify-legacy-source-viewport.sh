#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ruby -e '
  source = File.read(ARGV.fetch(0))
  legacy_open = /openWithOptions:options\s+rootView:nil\s+viewController:self\.uniInstance\.viewController/m
  abort("UniApp legacy iOS must resolve source rectangles from the visible page viewport") unless source.match?(legacy_open)
' "${script_dir}/LevixelUniApp/LevixelUniModule.m"

printf '%s\n' "Verified the UniApp legacy iOS visible-page viewport contract."
