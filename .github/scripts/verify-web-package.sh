#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 && $# -ne 6 ]]; then
  echo "Usage: $0 VERSION RELEASE_SOURCE PACKAGE CHECKSUM ACCEPTED_SHA256 [--require-tag]" >&2
  exit 1
fi

version="$1"
release_source="$(cd "$2" && pwd)"
artifact_path="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
checksum_path="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
accepted_sha256="$5"
require_tag=0
if [[ $# -eq 6 ]]; then
  if [[ "$6" != "--require-tag" ]]; then
    echo "Usage: $0 VERSION RELEASE_SOURCE PACKAGE CHECKSUM ACCEPTED_SHA256 [--require-tag]" >&2
    exit 1
  fi
  require_tag=1
fi
artifact_name="levixel-web-${version}.tgz"
web_source="${release_source}/adapters/web"

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Only stable semantic versions are verifiable: ${version}" >&2
  exit 1
fi
if [[ ! "${accepted_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Accepted Web SHA-256 is invalid: ${accepted_sha256}" >&2
  exit 1
fi
for required_path in \
  "${release_source}/.git" \
  "${release_source}" \
  "${web_source}/package.json" \
  "${web_source}/dist" \
  "${artifact_path}" \
  "${checksum_path}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "Required Web release input is missing: ${required_path}" >&2
    exit 1
  fi
done
if [[ "$(basename "${artifact_path}")" != "${artifact_name}" ]]; then
  echo "Unexpected Web package filename: ${artifact_path}" >&2
  exit 1
fi

if [[ ${require_tag} -eq 1 ]]; then
  tag_commit="$(git -C "${release_source}" rev-parse --verify "refs/tags/${version}^{commit}")"
  release_commit="$(git -C "${release_source}" rev-parse HEAD)"
  if [[ "${release_commit}" != "${tag_commit}" ]]; then
    echo "Release source HEAD ${release_commit} does not equal tag ${version} commit ${tag_commit}." >&2
    exit 1
  fi
fi

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

actual_sha256="$(sha256_file "${artifact_path}")"
read -r recorded_sha256 recorded_name < "${checksum_path}"
if [[ "${actual_sha256}" != "${accepted_sha256}" \
  || "${recorded_sha256}" != "${accepted_sha256}" \
  || "${recorded_name}" != "${artifact_name}" ]]; then
  echo "Web package checksum does not match the accepted ${artifact_name}." >&2
  exit 1
fi

read -r manifest_web_version package_version < <(
  ruby -ryaml -rjson -e '
    root = ARGV.fetch(0)
    manifest = YAML.load_file(File.join(root, "plugin.yaml"))
    target = manifest.fetch("targets").find { |entry| entry.fetch("id") == "web" }
    abort("Web target is missing") unless target
    package = JSON.parse(File.read(File.join(root, "adapters/web/package.json")))
    puts [target.fetch("version", manifest.fetch("version")), package.fetch("version")].join(" ")
  ' "${release_source}"
)
if [[ "${manifest_web_version}" != "${version}" || "${package_version}" != "${version}" ]]; then
  echo "Web source metadata does not match ${version}." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT
listing_path="${work_dir}/package-listing.txt"
tar -tzf "${artifact_path}" > "${listing_path}"
node -e '
  const { readFileSync } = require("node:fs")
  const entries = readFileSync(process.argv[1], "utf8").split(/\r?\n/).filter(Boolean)
  if (entries.length === 0)
    throw new Error("Web npm archive is empty")
  for (const entry of entries) {
    if (entry.startsWith("/") || entry.includes("\\") || entry.split("/").includes(".."))
      throw new Error(`Unsafe Web npm archive path: ${entry}`)
  }
' "${listing_path}"
if tar -tvzf "${artifact_path}" | awk '$1 ~ /^l/ { found = 1 } END { exit(found ? 0 : 1) }'; then
  echo "Symbolic links are not allowed in the Web npm package." >&2
  exit 1
fi

while IFS= read -r entry; do
  case "${entry}" in
    package|package/|package/dist|package/dist/|package/dist/*.js|package/dist/*.js.map|\
    package/dist/*.d.ts|package/dist/*.d.ts.map|package/package.json|package/README.md|\
    package/CHANGELOG.md|package/LICENSE|package/PROVENANCE.md|package/THIRD_PARTY_NOTICES.md) ;;
    *)
      echo "Unexpected file in Web npm package: ${entry}" >&2
      exit 1
      ;;
  esac
done < "${listing_path}"
for required_entry in \
  package/package.json \
  package/README.md \
  package/CHANGELOG.md \
  package/LICENSE \
  package/PROVENANCE.md \
  package/THIRD_PARTY_NOTICES.md \
  package/dist/index.js \
  package/dist/index.d.ts; do
  if ! grep -Fxq "${required_entry}" "${listing_path}"; then
    echo "Web npm package is missing ${required_entry}." >&2
    exit 1
  fi
done

tar -xzf "${artifact_path}" -C "${work_dir}"
package_root="${work_dir}/package"
node -e '
  const packageJson = require(process.argv[1])
  const version = process.argv[2]
  const expected = {
    name: "@sandrox/levixel-web",
    version,
    description: "Framework-independent Levixel shared-transition image and video viewer for Web.",
    type: "module",
    license: "MIT",
    author: "sandrox",
    homepage: "https://github.com/sandroxy/levixel",
    main: "./dist/index.js",
    module: "./dist/index.js",
    types: "./dist/index.d.ts",
    sideEffects: false,
  }
  for (const [key, value] of Object.entries(expected)) {
    if (packageJson[key] !== value)
      throw new Error(`Unexpected Web package metadata ${key}: ${packageJson[key]}`)
  }
  if (packageJson.private === true)
    throw new Error("Web package must not be private")
  if (packageJson.repository?.type !== "git"
    || packageJson.repository?.url !== "git+https://github.com/sandroxy/levixel.git"
    || packageJson.repository?.directory !== "adapters/web")
    throw new Error("Unexpected Web package repository metadata")
  if (packageJson.bugs?.url !== "https://github.com/sandroxy/levixel/issues")
    throw new Error("Unexpected Web package bugs URL")
  if (packageJson.publishConfig?.access !== "public"
    || packageJson.publishConfig?.registry !== "https://registry.npmjs.org/")
    throw new Error("Unexpected Web package publication metadata")
  if (Object.keys(packageJson.dependencies ?? {}).length !== 0)
    throw new Error("Web package must not contain runtime dependencies")
  const lifecycle = Object.keys(packageJson.scripts ?? {}).filter(name =>
    /^(preinstall|install|postinstall|prepublish|prepare)$/.test(name))
  if (lifecycle.length !== 0)
    throw new Error(`Unexpected Web lifecycle scripts: ${lifecycle.join(", ")}`)
  const rootExport = packageJson.exports?.["."]
  if (rootExport?.types !== "./dist/index.d.ts" || rootExport?.import !== "./dist/index.js")
    throw new Error("Unexpected Web package exports")
' "${package_root}/package.json" "${version}"

for relative_path in package.json README.md CHANGELOG.md; do
  cmp "${web_source}/${relative_path}" "${package_root}/${relative_path}"
done
for relative_path in LICENSE PROVENANCE.md THIRD_PARTY_NOTICES.md; do
  cmp "${release_source}/${relative_path}" "${package_root}/${relative_path}"
done
if ! grep -Eq "^## ${version}( |$)" "${package_root}/CHANGELOG.md"; then
  echo "Web CHANGELOG.md does not contain the ${version} release entry." >&2
  exit 1
fi
diff -qr "${web_source}/dist" "${package_root}/dist"

if find "${package_root}" -type f \
  \( -name '.env*' -o -name '.npmrc' -o -name '*.jks' -o -name '*.keystore' \
     -o -name '*.p12' -o -name '*.p8' -o -name '*private*key*' \) \
  -print -quit | grep -q .; then
  echo "Potential secret file found in the Web npm package." >&2
  exit 1
fi
if find "${package_root}/dist" -type f -name '*.map' -exec grep -E -n \
  '(/Users/|/home/runner/|[A-Za-z]:\\\\)' {} + | grep -q .; then
  echo "Web source maps contain an absolute build path." >&2
  exit 1
fi

consumer_dir="${work_dir}/consumer"
mkdir -p "${consumer_dir}"
printf '%s\n' '{"name":"levixel-web-artifact-consumer","private":true,"type":"module"}' \
  > "${consumer_dir}/package.json"
npm install \
  --prefix "${consumer_dir}" \
  --ignore-scripts \
  --no-audit \
  --no-fund \
  --package-lock=false \
  "${artifact_path}" >/dev/null
(
  cd "${consumer_dir}"
  node --input-type=module -e '
    const api = await import("@sandrox/levixel-web")
    const expected = [
      "LevixelContractError",
      "closeLevixel",
      "onLevixelEvent",
      "onLevixelSourceActivate",
      "openLevixel",
      "openLevixelFromSelector",
      "prepareLevixelItem",
      "warmupLevixelItem",
    ]
    for (const name of expected) {
      if (typeof api[name] !== "function")
        throw new Error(`Installed Web package is missing ${name}`)
    }
  '
)
cat > "${consumer_dir}/consumer.ts" <<'TYPESCRIPT'
import {
  closeLevixel,
  onLevixelEvent,
  onLevixelSourceActivate,
  openLevixel,
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
  type LevixelMediaItem,
} from '@sandrox/levixel-web';

const item: LevixelMediaItem = {
  id: 'artifact-image',
  type: 'image',
  url: 'https://example.com/full.jpg',
  thumbnailUrl: 'https://example.com/thumbnail.jpg',
};

const disposeEvent = onLevixelEvent(() => {});
const disposeActivation = onLevixelSourceActivate(document.body, () => {});
void openLevixel({ items: [item] });
void openLevixelFromSelector({ items: [item], sourceSelector: '.source' });
void prepareLevixelItem(item);
void warmupLevixelItem(item);
void closeLevixel();
disposeActivation();
disposeEvent();
TYPESCRIPT
cat > "${consumer_dir}/tsconfig.json" <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022", "DOM"],
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true
  },
  "include": ["consumer.ts"]
}
JSON
node "${web_source}/node_modules/typescript/bin/tsc" -p "${consumer_dir}/tsconfig.json"

cat > "${consumer_dir}/index.html" <<'HTML'
<!doctype html>
<html lang="en">
  <head><meta charset="UTF-8"><title>Levixel Web artifact consumer</title></head>
  <body><button class="source" type="button">Open</button><script type="module" src="/main.ts"></script></body>
</html>
HTML
cat > "${consumer_dir}/main.ts" <<'TYPESCRIPT'
import { onLevixelEvent, openLevixelFromSelector } from '@sandrox/levixel-web';

onLevixelEvent(() => {});
document.querySelector('.source')?.addEventListener('click', () => {
  void openLevixelFromSelector({
    items: [{ id: 'image', type: 'image', url: '/image.jpg' }],
    sourceSelector: '.source',
  });
});
TYPESCRIPT
(
  cd "${consumer_dir}"
  node "${web_source}/node_modules/vite/bin/vite.js" build --outDir vite-dist >/dev/null
)

LEVIXEL_WEB_DIST_ROOT="${consumer_dir}/node_modules/@sandrox/levixel-web/dist" \
  node "${web_source}/tests/browser.test.mjs"

printf '%s\n' "Verified ${artifact_name}"
printf '%s\n' "  package sha256: ${actual_sha256}"
