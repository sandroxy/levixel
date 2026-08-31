#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
artifact_path="${1:-}"
shift || true

if [[ -z "${artifact_path}" ]]; then
  echo "Usage: $0 /path/to/Levixel.xcframework.zip [README ...]" >&2
  exit 1
fi
if [[ ! -f "${artifact_path}" && ! -d "${artifact_path}" ]]; then
  echo "Levixel iOS core artifact does not exist: ${artifact_path}" >&2
  exit 1
fi

readmes=("$@")
if [[ ${#readmes[@]} -eq 0 ]]; then
  readmes=("${plugin_dir}/README.md" "${plugin_dir}/README-EN.md")
fi
for readme in "${readmes[@]}"; do
  if [[ ! -f "${readme}" ]]; then
    echo "README does not exist: ${readme}" >&2
    exit 1
  fi
done

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

for declaration in \
  'public init(items: [Levixel.LevixelMediaItem])' \
  'public func setupLevixelViewer(dataSource: any Levixel.LevixelDataSource'; do
  if ! grep -Fq "${declaration}" "${interface_path}"; then
    echo "Levixel iOS core cannot satisfy the stable README example." >&2
    echo "Missing public API: ${declaration}" >&2
    exit 1
  fi
done

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1; then
  framework_path="$(dirname "$(dirname "$(dirname "${interface_path}")")")"
  frameworks_dir="$(dirname "${framework_path}")"
  iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
  module_cache="${temporary_dir}/ModuleCache"
  mkdir -p "${module_cache}"

  for index in "${!readmes[@]}"; do
    readme="${readmes[${index}]}"
    harness="${temporary_dir}/README-${index}.swift"
    ruby -e '
      source, output = ARGV
      lines = File.readlines(source, chomp: true)
      opening = lines.index("```swift")
      abort("#{source} must contain one Swift example") unless opening
      closing = lines[(opening + 1)..].index("```")
      abort("#{source} has an unterminated Swift example") unless closing
      snippet = lines[(opening + 1)...(opening + 1 + closing)]
      snippet.reject! { |line| line.match?(/\Aimport\s+/) }
      body = snippet.map { |line| line.empty? ? "" : "    #{line}" }.join("\n")
      File.write(output, <<~SWIFT)
        import Foundation
        import Levixel
        import UIKit

        @MainActor
        func verifyStableReadmeExample() {
            let imageView = UIImageView()
            let fullImageURL = URL(string: "https://example.com/full.jpg")!
            let thumbnailURL = URL(string: "https://example.com/thumbnail.jpg")!
            let videoURL = URL(string: "https://example.com/video.mp4")!
            let posterURL = URL(string: "https://example.com/poster.jpg")!
        #{body}
        }
      SWIFT
    ' "${readme}" "${harness}"

    xcrun swiftc \
      -typecheck \
      -parse-as-library \
      -sdk "${iphoneos_sdk}" \
      -target arm64-apple-ios13.0 \
      -F "${frameworks_dir}" \
      -module-cache-path "${module_cache}" \
      "${harness}"
  done
fi

printf '%s\n' "Verified stable iOS README examples against ${artifact_path}"
