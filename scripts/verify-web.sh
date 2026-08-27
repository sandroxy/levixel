#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
web_dir="${plugin_dir}/adapters/web"
version="$(ruby -ryaml -e '
  manifest = YAML.load_file(ARGV.fetch(0))
  target = manifest.fetch("targets").find { |entry| entry.fetch("id") == "web" }
  abort("Web target is missing from plugin.yaml") unless target
  abort("Unexpected Web sourceRoot") unless target.fetch("sourceRoot") == "adapters/web"
  abort("Unexpected Web build command") unless target.dig("build", "command") == "./scripts/package-web.sh"
  expected_verify = ["./scripts/verify-web.sh", "./scripts/verify-web-package.sh"]
  abort("Unexpected Web verify commands") unless target.dig("verify", "commands") == expected_verify
  artifact = target.fetch("artifacts").find { |entry| entry.fetch("id") == "npm-package" }
  abort("Web npm artifact is missing") unless artifact
  version = target.fetch("version", manifest.fetch("version"))
  abort("Unexpected Web artifact output") unless artifact.fetch("output") == "dist/web/levixel-web-#{version}.tgz"
  abort("Unexpected Web distribution channel") unless artifact.dig("distribution", "channel") == "npm"
  abort("Unexpected Web npm package id") unless artifact.dig("distribution", "packageId") == "@sandrox/levixel-web"
  print version
' "${plugin_dir}/plugin.yaml")"

cmp "${plugin_dir}/LICENSE" "${web_dir}/LICENSE"
cmp "${plugin_dir}/PROVENANCE.md" "${web_dir}/PROVENANCE.md"
cmp "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${web_dir}/THIRD_PARTY_NOTICES.md"

node -e '
  const packageJson = require(process.argv[1])
  const expectedVersion = process.argv[2]
  if (packageJson.name !== "@sandrox/levixel-web")
    throw new Error(`Unexpected Web package name: ${packageJson.name}`)
  if (packageJson.version !== expectedVersion)
    throw new Error(`Web package version ${packageJson.version} does not match ${expectedVersion}`)
  if (packageJson.private === true)
    throw new Error("The accepted Web package must not remain private")
  if (packageJson.publishConfig?.access !== "public")
    throw new Error("The Web package must publish publicly")
  if (packageJson.publishConfig?.registry !== "https://registry.npmjs.org/")
    throw new Error("The Web package must use the public npm registry")
  if (Object.keys(packageJson.dependencies ?? {}).length !== 0)
    throw new Error("The Web package must not have runtime dependencies")
  const lifecycle = Object.keys(packageJson.scripts ?? {}).filter(name =>
    /^(preinstall|install|postinstall|prepublish|prepare)$/.test(name))
  if (lifecycle.length !== 0)
    throw new Error(`Unexpected Web lifecycle scripts: ${lifecycle.join(", ")}`)
' "${web_dir}/package.json" "${version}"

npm --prefix "${web_dir}" run verify

pack_report="$(mktemp)"
trap 'rm -f "${pack_report}"' EXIT
(
  cd "${web_dir}"
  npm pack --dry-run --json > "${pack_report}"
)
node -e '
  const { readFileSync } = require("node:fs")
  const report = JSON.parse(readFileSync(process.argv[1], "utf8"))
  if (!Array.isArray(report) || report.length !== 1)
    throw new Error("Unexpected npm pack dry-run report")
  const files = report[0].files.map(entry => entry.path).sort()
  const required = [
    "CHANGELOG.md",
    "LICENSE",
    "PROVENANCE.md",
    "README.md",
    "THIRD_PARTY_NOTICES.md",
    "dist/index.d.ts",
    "dist/index.js",
    "package.json",
  ]
  for (const path of required) {
    if (!files.includes(path))
      throw new Error(`Web npm package is missing ${path}`)
  }
  const unexpected = files.filter(path =>
    path.startsWith("src/")
    || path.startsWith("tests/")
    || path.startsWith("demo/")
    || path === "package-lock.json")
  if (unexpected.length !== 0)
    throw new Error(`Unexpected Web npm payload: ${unexpected.join(", ")}`)
' "${pack_report}"

printf '%s\n' "Levixel Web ${version} source candidate is consistent."
