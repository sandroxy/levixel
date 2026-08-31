#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact_path="${1:-}"

if [[ -z "${artifact_path}" ]]; then
  echo "Usage: $0 /path/to/Levixel.xcframework.zip" >&2
  exit 1
fi
if [[ ! -f "${artifact_path}" && ! -d "${artifact_path}" ]]; then
  echo "Levixel iOS core artifact does not exist: ${artifact_path}" >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
inspection_root="${artifact_path}"
if [[ -f "${artifact_path}" ]]; then
  if ! unzip -q "${artifact_path}" \
      'Levixel.xcframework/ios-arm64/Levixel.framework/*' \
      -d "${temporary_dir}"; then
    echo "Levixel iOS core archive is missing a readable device framework: ${artifact_path}" >&2
    exit 1
  fi
  inspection_root="${temporary_dir}/Levixel.xcframework"
fi

interface_path="$(find "${inspection_root}" -type f \
  -path '*/ios-arm64/Levixel.framework/Modules/Levixel.swiftmodule/arm64-apple-ios.swiftinterface' \
  -print -quit)"
if [[ -z "${interface_path}" ]]; then
  echo "Levixel iOS core is missing its public arm64 Swift interface: ${artifact_path}" >&2
  exit 1
fi

required_declarations=(
  'public protocol LevixelIdentifiedDataSource'
  'func itemIdentifier(at index: Swift.Int) -> Swift.String?'
  'itemIdentifiers: [Swift.String]'
  'func registerLevixelSource(galleryId: Swift.String, itemIdentifier: Swift.String)'
)

for declaration in "${required_declarations[@]}"; do
  if ! grep -Fq "${declaration}" "${interface_path}"; then
    echo "Levixel iOS core is incompatible with the current adapters." >&2
    echo "Missing public API: ${declaration}" >&2
    echo "Build and accept a next-version native iOS candidate before packaging React Native or UniApp." >&2
    exit 1
  fi
done

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1; then
  framework_path="$(dirname "$(dirname "$(dirname "${interface_path}")")")"
  frameworks_dir="$(dirname "${framework_path}")"
  module_cache="${temporary_dir}/ModuleCache"
  mkdir -p "${module_cache}"
  iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  xcrun swiftc \
    -typecheck \
    -parse-as-library \
    -sdk "${iphoneos_sdk}" \
    -target arm64-apple-ios13.0 \
    -F "${frameworks_dir}" \
    -module-cache-path "${module_cache}" \
    "${script_dir}/fixtures/ios-core-adapter-api.swift"
fi

printf '%s\n' "Verified adapter-facing iOS core API: ${artifact_path}"
