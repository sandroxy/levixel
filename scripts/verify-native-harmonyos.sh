#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
default_artifact_path="${plugin_dir}/dist/native-harmonyos/levixel-${version}.har"
artifact_path="${1:-${default_artifact_path}}"

if [[ "$#" -gt 1 ]]; then
  echo "Usage: $0 [artifact.har]" >&2
  exit 1
fi

deveco_contents="${DEVECO_STUDIO_CONTENTS:-/Applications/DevEco-Studio.app/Contents}"

ohpm="${OHPM:-}"
if [[ -z "${ohpm}" ]]; then
  ohpm="$(command -v ohpm || true)"
fi
if [[ -z "${ohpm}" && -x "${deveco_contents}/tools/ohpm/bin/ohpm" ]]; then
  ohpm="${deveco_contents}/tools/ohpm/bin/ohpm"
fi
if [[ -z "${ohpm}" || ! -x "${ohpm}" ]]; then
  echo "ohpm was not found. Set OHPM or add it to PATH." >&2
  exit 1
fi

if [[ ! -f "${artifact_path}" ]]; then
  echo "Packaged HarmonyOS artifact is missing: ${artifact_path}" >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
tar -xzf "${artifact_path}" -C "${temporary_dir}"

package_dir="${temporary_dir}/package"
if [[ ! -f "${package_dir}/Index.d.ets" || ! -f "${package_dir}/ets/modules.abc" ]]; then
  echo "Packaged HAR does not contain the Levixel public API and bytecode." >&2
  exit 1
fi
ruby -e '
  package_dir = ARGV.fetch(0)
  index_path = File.join(package_dir, "Index.d.ets")
  index = File.read(index_path)
  required_exports = {
    "LevixelController" => "./src/main/ets/controller/LevixelController",
    "LevixelGallery" => "./src/main/ets/components/LevixelGallery",
    "LevixelSource" => "./src/main/ets/components/LevixelSource",
    "LevixelSourceViewport" => "./src/main/ets/components/LevixelSourceViewport",
    "LevixelViewer" => "./src/main/ets/components/LevixelViewer",
  }
  required_exports.each do |symbol, path|
    expected = "export { #{symbol} } from \x27#{path}\x27;"
    abort("Packaged HarmonyOS public API is missing #{symbol}.") unless index.include?(expected)
  end
  abort("Packaged HarmonyOS root API must use explicit exports.") if index.match?(/export\s*\*/)
  %w[LevixelViewerContext LevixelViewerHost resolveLevixelContext].each do |internal_symbol|
    abort("Packaged HarmonyOS root API exposes internal #{internal_symbol}.") if index.include?(internal_symbol)
  end
  %w[LevixelSourceImageFit LevixelAction LevixelActionLayout LevixelMediaContext LevixelViewerEvent].each do |symbol|
    abort("Packaged HarmonyOS public API is missing #{symbol}.") unless index.match?(/\b#{symbol}\b/)
  end

  declarations = {
    "src/main/ets/controller/LevixelController.d.ets" => [
      "export declare class LevixelController",
      "constructor();",
      "open(itemId: string): void;",
      "close(): void;",
      "retry(): boolean;",
      "handleBack(): boolean;",
      "onEvent(listener: (event: LevixelViewerEvent) => void): () => void;",
    ],
    "src/main/ets/components/LevixelViewer.d.ets" => [
      "export declare struct LevixelViewer",
      "controller: LevixelController | null;",
      "items: LevixelMediaItem[];",
      "actions: LevixelAction[];",
      "actionLayout: LevixelActionLayout;",
      "actionListIcons: boolean;",
      "theme: \x27dark\x27 | \x27light\x27;",
      "onEvent: (event: LevixelViewerEvent) => void;",
      "content: () => void;",
    ],
    "src/main/ets/components/LevixelGallery.d.ets" => [
      "export declare struct LevixelGallery",
      "actions: LevixelAction[];",
      "actionLayout: LevixelActionLayout;",
      "actionListIcons: boolean;",
      "theme: \x27dark\x27 | \x27light\x27;",
      "onEvent: (event: LevixelViewerEvent) => void;",
    ],
    "src/main/ets/model/LevixelModels.d.ets" => [
      "export interface LevixelAction",
      "export type LevixelActionLayout = \x27list\x27 | \x27grid\x27;",
      "icon?: string;",
      "group?: string;",
      "disabled?: boolean;",
      "destructive?: boolean;",
      "onPress?: (event: LevixelViewerEvent) => void;",
      "export interface LevixelMediaContext",
      "sessionId: string;",
      "galleryId: string;",
      "itemId: string;",
      "actionId?: string;",
      "export interface LevixelViewerEvent",
      "payload: LevixelMediaContext;",
    ],
    "src/main/ets/components/LevixelSource.d.ets" => [
      "export declare struct LevixelSource",
      "controller: LevixelController | null;",
      "itemId: string;",
      "viewportId: string;",
      "cornerRadius: number;",
      "imageFit: LevixelSourceImageFit;",
      "content: () => void;",
      "decoration?: () => void;",
    ],
    "src/main/ets/components/LevixelSourceViewport.d.ets" => [
      "export declare struct LevixelSourceViewport",
      "controller: LevixelController | null;",
      "viewportId: string;",
      "content: () => void;",
    ],
  }
  declarations.each do |relative_path, markers|
    declaration_path = File.join(package_dir, relative_path)
    abort("Packaged HarmonyOS declaration is missing: #{relative_path}") unless File.file?(declaration_path)
    declaration = File.read(declaration_path)
    missing = markers.reject { |marker| declaration.include?(marker) }
    abort("Packaged HarmonyOS declaration #{relative_path} is missing: #{missing.join(", ")}") unless missing.empty?
    abort("Packaged HarmonyOS composition API must not depend on implicit provider ancestry: #{relative_path}") if
      declaration.match?(/@(?:Consume|Provide)\b/)
    abort("Packaged HarmonyOS controller must retain its plain object identity: #{relative_path}") if
      declaration.match?(/@(?:Prop|State|Link|ObjectLink)\b[^\n]*\s+controller\s*:/)
  end
' "${package_dir}"
if ! grep -Eq '"name":"@sandrox/levixel"' "${package_dir}/oh-package.json5"; then
  echo "Packaged HAR has unexpected package metadata." >&2
  exit 1
fi
ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "name" => "@sandrox/levixel",
    "version" => ARGV.fetch(1),
    "author" => {
      "name" => "SandroX",
      "email" => "wangyifengjxc@gmail.com",
      "url" => "https://github.com/sandroxy"
    },
    "homepage" => "https://github.com/sandroxy/levixel",
    "repository" => "https://github.com/sandroxy/levixel",
    "types" => "Index.d.ets",
    "artifactType" => "obfuscation",
    "compatibleSdkVersion" => 23,
    "compatibleSdkType" => "HarmonyOS",
    "obfuscated" => false
  }
  mismatches = expected.reject { |key, value| package[key] == value }
  abort("Unexpected HarmonyOS release metadata: #{mismatches.inspect}") unless mismatches.empty?
' "${package_dir}/oh-package.json5" "${version}"
for required_file in README.md CHANGELOG.md LICENSE; do
  if [[ ! -f "${package_dir}/${required_file}" ]]; then
    echo "Packaged HarmonyOS artifact is missing ${required_file}." >&2
    exit 1
  fi
done
if ! grep -Eq 'Copyright \(c\) 2025 Fernando Rojo' "${package_dir}/LICENSE" ||
   ! grep -Eq 'Copyright \(c\) 2013 Michael Henry Pantaleon' "${package_dir}/LICENSE"; then
  echo "Packaged HarmonyOS LICENSE is missing required third-party notices." >&2
  exit 1
fi

while IFS= read -r -d '' packaged_file; do
  if grep -a -n -E 'Galeria|galeria|com\.chris' "${packaged_file}"; then
    echo "Legacy Galeria identifiers found in packaged HarmonyOS runtime content." >&2
    exit 1
  fi
done < <(find "${package_dir}" -type f \
  ! -name 'LICENSE' \
  ! -name 'THIRD_PARTY_NOTICES.md' \
  -print0)

"${ohpm}" prepublish "${artifact_path}"

printf '%s\n' "Verified ${artifact_path}"
