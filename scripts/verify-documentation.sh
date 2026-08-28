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

public_facing_docs=(
  "${plugin_dir}/CHANGELOG.md"
  "${plugin_dir}/PROVENANCE.md"
  "${plugin_dir}/README.md"
  "${plugin_dir}/README-EN.md"
  "${plugin_dir}/adapters/react-native/README.md"
  "${plugin_dir}/adapters/web/CHANGELOG.md"
  "${plugin_dir}/adapters/web/PROVENANCE.md"
  "${plugin_dir}/adapters/web/README.md"
  "${plugin_dir}/native/harmonyos/levixel/CHANGELOG.md"
  "${plugin_dir}/native/harmonyos/levixel/README.md"
  "${plugin_dir}/packaging/swift-package/README.md"
  "${plugin_dir}/uni_modules/Sandrox-Levixel/changelog.md"
  "${marketplace_readme}"
)

ruby -e '
  pattern = /(?<![0-9A-Za-z])(?:\d+\.\d+\.\d+|\d+\.(?:x|X|\*))(?![0-9A-Za-z])/
  failures = ARGV.each_with_object([]) do |path, result|
    matches = File.read(path).scan(pattern).uniq
    result << "#{path}: #{matches.join(", ")}" unless matches.empty?
  end
  abort("Stable documentation must not contain release literals or floating major aliases:\n#{failures.join("\n")}") unless failures.empty?
' "${version_neutral_docs[@]}"

ruby -e '
  forbidden = {
    /已验收|验收\s*SHA-?256|字节级一致|正式候选|独立实现/ => "maintainer-only Chinese release or provenance wording",
    /\b(?:accepted artifacts?|immutable candidate|canonical release pipeline|byte-identical|artifact-only|independently implemented)\b/i => "maintainer-only English release or provenance wording",
    /SDK typecheck|native-release-version|proof of concept|product authority/i => "internal implementation or audit wording"
  }
  failures = []
  ARGV.each do |path|
    contents = File.read(path)
    forbidden.each do |pattern, description|
      match = contents.match(pattern)
      failures << "#{path}: #{description}: #{match[0]}" if match
    end
  end
  abort("Maintainer-only wording leaked into a public-facing document:\n#{failures.join("\n")}") unless failures.empty?
' "${public_facing_docs[@]}"

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
  echo "UniApp user documentation must preserve the declared sourceVisibility default." >&2
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
  expected_channels = {
    "Android" => "https://central.sonatype.com/artifact/io.gitee.sandrox/levixel",
    "iOS" => "https://github.com/sandroxy/levixel",
    "HarmonyOS" => "https://ohpm.openharmony.cn/#/cn/detail/@sandrox%2Flevixel",
    "React Native / Expo" => "https://www.npmjs.com/package/@sandrox/levixel",
    "UniApp" => "https://ext.dcloud.net.cn/plugin?id=29394",
    "Web" => "https://www.npmjs.com/package/@sandrox/levixel-web"
  }
  failures = []
  ARGV.each do |path|
    lines = File.readlines(path, chomp: true)
    expected_channels.each do |platform, url|
      row = lines.find { |line| line.start_with?("| #{platform} |") }
      failures << "#{path}: missing #{platform} row" unless row
      failures << "#{path}: #{platform} channel is not linked to #{url}" if row && !row.include?("](#{url})")
    end
  end
  abort("Root README distribution links are incomplete:\n#{failures.join("\n")}") unless failures.empty?
' "${plugin_dir}/README.md" "${plugin_dir}/README-EN.md"

ruby -ryaml -e '
  manifest = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
  targets = manifest.fetch("targets").to_h { |target| [target.fetch("id"), target] }
  constraint = lambda do |target_id, name|
    entry = targets.fetch(target_id).fetch("constraints").find { |item| item.fetch("name") == name }
    abort("Missing #{target_id} constraint #{name}") unless entry
    entry.fetch("value").to_s
  end

  android = constraint.call("native-android", "minimum-sdk")
  ios = constraint.call("native-ios", "minimum-ios")
  harmony = constraint.call("native-harmonyos", "minimum-api")
  checks = {
    ARGV.fetch(1) => ["最低支持 Android API #{android}", "最低支持 iOS #{ios}", "最低支持 HarmonyOS API #{harmony}"],
    ARGV.fetch(2) => ["minimum supported Android version is API #{android}", "minimum supported iOS version is #{ios}", "minimum supported HarmonyOS version is API #{harmony}"],
    ARGV.fetch(3) => ["HarmonyOS API #{harmony} or newer"],
    ARGV.fetch(4) => ["iOS #{ios} and newer"]
  }
  failures = []
  checks.each do |path, phrases|
    contents = File.read(path)
    phrases.each { |phrase| failures << "#{path}: #{phrase}" unless contents.include?(phrase) }
  end
  abort("Native compatibility documentation drifted from plugin.yaml:\n#{failures.join("\n")}") unless failures.empty?
' \
  "${plugin_dir}/plugin.yaml" \
  "${plugin_dir}/README.md" \
  "${plugin_dir}/README-EN.md" \
  "${plugin_dir}/native/harmonyos/levixel/README.md" \
  "${plugin_dir}/packaging/swift-package/README.md"

node -e '
  const fs = require("fs")
  const packageJson = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))
  const podspec = fs.readFileSync(process.argv[2], "utf8")
  const readme = fs.readFileSync(process.argv[3], "utf8")
  const displayMinimum = (range) => {
    const match = String(range).match(/\d+(?:\.\d+)*/)
    if (!match) throw new Error(`Cannot resolve minimum from ${range}`)
    const parts = match[0].split(".")
    while (parts.length > 1 && parts[parts.length - 1] === "0") parts.pop()
    return parts.join(".")
  }
  const podMinimum = podspec.match(/s\.platform\s*=\s*:ios,\s*["\x27]([^"\x27]+)["\x27]/)?.[1]
  if (!podMinimum) throw new Error("Cannot resolve React Native iOS minimum from podspec")
  const required = [
    `Expo SDK ${displayMinimum(packageJson.peerDependencies.expo)} or newer`,
    `React Native ${displayMinimum(packageJson.peerDependencies["react-native"])} or newer`,
    `React ${displayMinimum(packageJson.peerDependencies.react)} or newer`,
    `iOS ${podMinimum} or newer`,
  ]
  const missing = required.filter((phrase) => !readme.includes(phrase))
  if (missing.length) throw new Error(`React Native requirements documentation drifted: ${missing.join(", ")}`)
' \
  "${plugin_dir}/adapters/react-native/package.json" \
  "${plugin_dir}/adapters/react-native/SandroxLevixel.podspec" \
  "${plugin_dir}/adapters/react-native/README.md"

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
