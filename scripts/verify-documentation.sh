#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
read -r version native_version _ _ _ < <(
  bash "${script_dir}/resolve-uniapp-product.sh" "${plugin_dir}/plugin.yaml"
)
marketplace_readme="${plugin_dir}/uni_modules/Sandrox-Levixel/readme.md"
marketplace_template="${plugin_dir}/adapters/uniapp/MARKETPLACE.md"
package_json="${plugin_dir}/uni_modules/Sandrox-Levixel/package.json"

version_neutral_docs=(
  "${plugin_dir}/README.md"
  "${plugin_dir}/README-EN.md"
  "${plugin_dir}/DEVELOPMENT.md"
  "${plugin_dir}/adapters/react-native/README.md"
  "${plugin_dir}/adapters/uniapp/README.md"
  "${marketplace_template}"
  "${plugin_dir}/adapters/web/README.md"
  "${plugin_dir}/native/harmonyos/levixel/README.md"
  "${plugin_dir}/packaging/swift-package/README.md"
  "${marketplace_readme}"
)

ruby -e '
  pattern = /(?<![0-9A-Za-z])\d+\.\d+\.\d+(?![0-9A-Za-z])/
  failures = ARGV.each_with_object([]) do |path, result|
    matches = File.read(path).scan(pattern).uniq
    result << "#{path}: #{matches.join(", ")}" unless matches.empty?
  end
  abort("Stable documentation must not contain release literals:\n#{failures.join("\n")}") unless failures.empty?
' "${version_neutral_docs[@]}"

ruby -e '
  allowed = %w[1.0.0 1.1.0]
  versions = File.read(ARGV.fetch(0)).scan(/(?<![0-9A-Za-z])\d+\.\d+\.\d+(?![0-9A-Za-z])/).uniq
  unexpected = versions - allowed
  abort("RELEASING.md contains non-historical hard-coded versions: #{unexpected.join(", ")}") unless unexpected.empty?
' "${plugin_dir}/RELEASING.md"

if [[ "$(head -n 1 "${marketplace_readme}")" != "# Levixel 共享转场图片视频查看器" ]]; then
  echo "UniApp user documentation must use the product title without a transport suffix." >&2
  exit 1
fi

for public_api in \
  openLevixel \
  closeLevixel \
  onLevixelEvent \
  prepareLevixelItem \
  warmupLevixelItem \
  openLevixelFromSelector; do
  if ! grep -Fq "${public_api}" "${marketplace_readme}"; then
    echo "UniApp user documentation is missing public API ${public_api}." >&2
    exit 1
  fi
done

if grep -Fq "readyItems" "${marketplace_readme}"; then
  echo "UniApp examples must not gate opening on thumbnail readiness." >&2
  exit 1
fi
if ! grep -Fq "不是打开前置条件" "${marketplace_readme}"; then
  echo "UniApp user documentation must explain that preview preparation is not an opening prerequisite." >&2
  exit 1
fi
if ! grep -Fq 'sourceVisibility` 默认且建议保持 `visible' "${marketplace_readme}"; then
  echo "UniApp user documentation must preserve the accepted sourceVisibility default." >&2
  exit 1
fi

for internal_phrase in \
  "SDK typecheck" \
  "native-release-version" \
  "UTSAndroid.getResourcePath" \
  "协调发布"; do
  if grep -Fq "${internal_phrase}" "${marketplace_readme}"; then
    echo "Maintainer-only detail leaked into UniApp user documentation: ${internal_phrase}" >&2
    exit 1
  fi
done

read -r hbuilderx_min classic_android_min classic_ios_min x_android_min x_ios_min < <(
  node -e '
    const p = require(process.argv[1])
    const client = p.uni_modules.platforms.client
    const minimum = String(p.engines.HBuilderX).match(/\d+(?:\.\d+){1,2}/)?.[0]
    if (!minimum) throw new Error("Cannot resolve HBuilderX minimum")
    console.log([
      minimum,
      client["uni-app"].app.android.minVersion,
      client["uni-app"].app.ios.minVersion,
      client["uni-app-x"].app.android.minVersion,
      client["uni-app-x"].app.ios.minVersion,
    ].join(" "))
  ' "${package_json}"
)

for required_compatibility in \
  "HBuilderX ${hbuilderx_min}" \
  "API ${classic_android_min}+" \
  "iOS ${classic_ios_min}+" \
  "API ${x_android_min}+" \
  "iOS ${x_ios_min}+"; do
  if ! grep -Fq "${required_compatibility}" "${marketplace_readme}"; then
    echo "UniApp documentation does not match package compatibility metadata: ${required_compatibility}" >&2
    exit 1
  fi
done

node -e '
  const p = require(process.argv[1])
  if (p.displayName !== "Levixel 共享转场图片视频查看器")
    throw new Error(`Unexpected UniApp displayName: ${p.displayName}`)
  if (/薄桥|薄桥接/.test(p.description))
    throw new Error("UniApp public description must describe user value, not bridge architecture")
' "${package_json}"

for platform in Android iOS HarmonyOS "React Native / Expo" UniApp Web; do
  if ! grep -Fq "| ${platform} |" "${plugin_dir}/README.md" || \
     ! grep -Fq "| ${platform} |" "${plugin_dir}/README-EN.md"; then
    echo "Root README platform tables are out of sync at ${platform}." >&2
    exit 1
  fi
done

ruby -e '
  failures = []
  ARGV.each do |path|
    File.read(path).scan(/!?\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
      next if target.match?(/\A(?:https?:|mailto:|#)/)
      clean = target.split("#", 2).first
      next if clean.empty?
      resolved = File.expand_path(clean, File.dirname(path))
      failures << "#{path}: #{target}" unless File.exist?(resolved)
    end
  end
  abort("Broken local Markdown links:\n#{failures.join("\n")}") unless failures.empty?
' "${version_neutral_docs[@]}" "${plugin_dir}/RELEASING.md" "${plugin_dir}/PROVENANCE.md"

rendered_marketplace="$(mktemp)"
trap 'rm -f "${rendered_marketplace}"' EXIT
ruby "${script_dir}/render-uniapp-marketplace.rb" \
  "${marketplace_template}" \
  "${package_json}" \
  "${plugin_dir}/uni_modules/Sandrox-Levixel/changelog.md" \
  "${version}" \
  "${native_version}" \
  "0000000000000000000000000000000000000000000000000000000000000000" \
  > "${rendered_marketplace}"

if grep -Eq '@[A-Z][A-Z0-9_]*@' "${rendered_marketplace}"; then
  echo "Rendered Marketplace material contains unresolved placeholders." >&2
  exit 1
fi
if ! grep -Fq "版本：\`${version}\`" "${rendered_marketplace}"; then
  echo "Rendered Marketplace material does not contain the resolved version." >&2
  exit 1
fi

printf '%s\n' "Levixel documentation boundaries and generated Marketplace material are consistent."
