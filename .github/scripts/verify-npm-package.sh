#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 7 ]]; then
  echo "Usage: $0 VERSION PACKAGE CHECKSUM NATIVE_MANIFEST ANDROID_AAR IOS_XCFRAMEWORK_ZIP RELEASE_SOURCE" >&2
  exit 1
fi

version="$1"
artifact_path="$2"
checksum_path="$3"
native_manifest="$4"
android_artifact="$5"
ios_artifact="$6"
release_source="$(cd "$7" && pwd)"
artifact_name="levixel-react-native-${version}.tgz"
release_adapter="${release_source}/adapters/react-native"

if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Only stable semantic versions are publishable: ${version}" >&2
  exit 1
fi

for required_file in \
  "${release_source}/plugin.yaml" \
  "${release_adapter}/package.json" \
  "${artifact_path}" \
  "${checksum_path}" \
  "${native_manifest}" \
  "${android_artifact}" \
  "${ios_artifact}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "Required release input is missing: ${required_file}" >&2
    exit 1
  fi
done

tag_commit="$(git -C "${release_source}" rev-parse --verify "refs/tags/${version}^{commit}")"
release_commit="$(git -C "${release_source}" rev-parse HEAD)"
if [[ "${release_commit}" != "${tag_commit}" ]]; then
  echo "Release source HEAD ${release_commit} does not equal tag ${version} commit ${tag_commit}." >&2
  exit 1
fi

read -r source_version source_package_version < <(
  ruby -ryaml -rjson -e '
    root = ARGV.fetch(0)
    manifest = YAML.load_file(File.join(root, "plugin.yaml"))
    package = JSON.parse(File.read(File.join(root, "adapters/react-native/package.json")))
    puts [manifest.fetch("version"), package.fetch("version")].join(" ")
  ' "${release_source}"
)
if [[ "${source_version}" != "${version}" || "${source_package_version}" != "${version}" ]]; then
  echo "Canonical tag source does not declare React Native ${version}." >&2
  exit 1
fi

ios_api_verifier="${release_source}/scripts/verify-ios-core-adapter-api.sh"
if [[ -f "${ios_api_verifier}" ]]; then
  bash "${ios_api_verifier}" "${ios_artifact}"
elif grep -E -q \
  'itemIdentifiers[[:space:]]*:|registerLevixelSource\([^)]*itemIdentifier[[:space:]]*:' \
  "${release_adapter}/ios/LevixelView.swift"; then
  echo "Release source uses stable iOS media identities but is missing its matching API verifier." >&2
  exit 1
fi

if [[ "$(basename "${artifact_path}")" != "${artifact_name}" ]]; then
  echo "Unexpected npm package filename: ${artifact_path}" >&2
  exit 1
fi

actual_package_sha="$(shasum -a 256 "${artifact_path}" | awk '{print $1}')"
read -r recorded_package_sha recorded_package_name < "${checksum_path}"
if [[ "${recorded_package_sha}" != "${actual_package_sha}" \
  || "${recorded_package_name}" != "${artifact_name}" ]]; then
  echo "Package checksum sidecar does not match ${artifact_name}." >&2
  exit 1
fi

read -r expected_android_sha expected_android_bytes expected_ios_sha expected_ios_bytes native_commit < <(
  ruby -I "${release_source}/scripts" -rjson -r native-release-manifest -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    NativeReleaseManifest.validate!(manifest, plugin: "levixel", version: version)
    abort("Dirty native release is not publishable") unless manifest["dirty"] == false
    commit = manifest.fetch("commit")
    abort("Unexpected native release commit") unless commit.match?(/\A[0-9a-f]{40}\z/)
    artifacts = manifest.fetch("artifacts").to_h { |entry| [entry.fetch("file"), entry] }
    android = artifacts.fetch("levixel-#{version}.aar")
    ios = artifacts.fetch("levixel-#{version}.xcframework.zip")
    puts [
      android.fetch("sha256"), android.fetch("bytes"),
      ios.fetch("sha256"), ios.fetch("bytes"), commit
    ].join(" ")
  ' "${native_manifest}" "${version}"
)

if [[ "${native_commit}" != "${tag_commit}" ]]; then
  echo "Native manifest commit ${native_commit} does not equal canonical ${version} tag commit ${tag_commit}." >&2
  exit 1
fi
"${release_source}/scripts/verify-native-manifest-ios-provenance.sh" \
  "${native_manifest}" "${ios_artifact}" "${version}"

file_size() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then
    stat -f '%z' "$1"
  else
    stat -c '%s' "$1"
  fi
}

actual_android_sha="$(shasum -a 256 "${android_artifact}" | awk '{print $1}')"
actual_ios_sha="$(shasum -a 256 "${ios_artifact}" | awk '{print $1}')"
if [[ "${actual_android_sha}" != "${expected_android_sha}" \
  || "$(file_size "${android_artifact}")" != "${expected_android_bytes}" ]]; then
  echo "Public Android AAR does not match the accepted native release." >&2
  exit 1
fi
if [[ "${actual_ios_sha}" != "${expected_ios_sha}" \
  || "$(file_size "${ios_artifact}")" != "${expected_ios_bytes}" ]]; then
  echo "Public iOS XCFramework does not match the accepted native release." >&2
  exit 1
fi

temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT
listing_path="${temporary_dir}/package-listing.txt"
tar -tzf "${artifact_path}" > "${listing_path}"

ruby -e '
  entries = File.readlines(ARGV.fetch(0), chomp: true)
  abort("npm archive is empty") if entries.empty?
  entries.each do |entry|
    abort("Unsafe absolute npm archive path: #{entry}") if entry.start_with?("/")
    abort("Unsafe npm archive path separator: #{entry}") if entry.include?("\\")
    abort("Unsafe parent npm archive path: #{entry}") if entry.split("/").include?("..")
  end
' "${listing_path}"

if tar -tvzf "${artifact_path}" | awk '$1 ~ /^[lh]/ { found = 1 } END { exit(found ? 0 : 1) }'; then
  echo "Links are not allowed in the npm package." >&2
  exit 1
fi

while IFS= read -r entry; do
  case "${entry}" in
    package|package/|package/android|package/android/*|package/ios|package/ios/*|package/src|package/src/*|\
    package/package.json|package/README.md|package/LICENSE|package/CHANGELOG.md|\
    package/PROVENANCE.md|package/THIRD_PARTY_NOTICES.md|\
    package/SandroxLevixel.podspec|package/expo-module.config.json) ;;
    *)
      echo "Unexpected file in npm package: ${entry}" >&2
      exit 1
      ;;
  esac
done < "${listing_path}"

tar -xzf "${artifact_path}" -C "${temporary_dir}"
package_root="${temporary_dir}/package"
if [[ ! -d "${package_root}" ]]; then
  echo "The archive does not contain an npm package root." >&2
  exit 1
fi

ruby -rjson -e '
  package = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "name" => "@sandrox/levixel",
    "version" => ARGV.fetch(1),
    "description" => "Shared-transition image and video viewer for React Native and Expo.",
    "license" => "MIT",
    "author" => "sandrox",
    "homepage" => "https://github.com/sandroxy/levixel",
    "main" => "src/index.ts",
    "react-native" => "src/index.ts",
    "types" => "src/index.ts",
    "sideEffects" => false
  }
  mismatches = expected.reject { |key, value| package[key] == value }
  abort("Unexpected npm package metadata: #{mismatches.inspect}") unless mismatches.empty?
  abort("Unexpected npm repository") unless package["repository"] == {
    "type" => "git",
    "url" => "git+https://github.com/sandroxy/levixel.git"
  }
  abort("Unexpected npm bugs URL") unless package.dig("bugs", "url") == "https://github.com/sandroxy/levixel/issues"
  abort("Package must publish publicly") unless package.dig("publishConfig", "access") == "public"
  abort("Package must use the public npm registry") unless package.dig("publishConfig", "registry") == "https://registry.npmjs.org/"
  abort("Unexpected runtime dependencies") unless package.fetch("dependencies", {}).empty?
  lifecycle = package.fetch("scripts", {}).keys.grep(/^(preinstall|install|postinstall|prepublish|prepare)$/)
  abort("Unexpected lifecycle scripts: #{lifecycle.join(", ")}") unless lifecycle.empty?
' "${package_root}/package.json" "${version}"

for relative_path in \
  package.json \
  expo-module.config.json \
  SandroxLevixel.podspec \
  README.md; do
  cmp "${release_adapter}/${relative_path}" "${package_root}/${relative_path}"
done
for relative_path in CHANGELOG.md LICENSE PROVENANCE.md THIRD_PARTY_NOTICES.md; do
  cmp "${release_source}/${relative_path}" "${package_root}/${relative_path}"
done
diff -qr "${release_adapter}/src" "${package_root}/src"
diff -qr -x libs "${release_adapter}/android" "${package_root}/android"
diff -qr -x Frameworks "${release_adapter}/ios" "${package_root}/ios"

unexpected_project_urls="$(
  grep -R -I -h -o -E '(git\+)?https://github\.com/sandroxy/[A-Za-z0-9_.-]+' "${package_root}" \
    | sort -u \
    | grep -Ev '^(git\+)?https://github\.com/sandroxy/levixel(\.git)?$' \
    || true
)"
if [[ -n "${unexpected_project_urls}" ]]; then
  echo "The npm package exposes an unexpected project URL:" >&2
  printf '%s\n' "${unexpected_project_urls}" >&2
  exit 1
fi

packaged_aar="${package_root}/android/libs/levixel-core.aar"
packaged_xcframework="${package_root}/ios/Frameworks/Levixel.xcframework"
if [[ ! -f "${packaged_aar}" || ! -d "${packaged_xcframework}" ]]; then
  echo "The npm package is missing an accepted native artifact." >&2
  exit 1
fi
cmp "${android_artifact}" "${packaged_aar}"

mkdir -p "${temporary_dir}/native-ios"
unzip -q "${ios_artifact}" 'Levixel.xcframework/*' -d "${temporary_dir}/native-ios"
diff -qr "${temporary_dir}/native-ios/Levixel.xcframework" "${packaged_xcframework}"

if tar -tzf "${artifact_path}" | grep -E \
  '(^|/)(native|Viewer|native-harmonyos)(/|$)|LevixelViewer(OverlayView|Controller|PageView)\.(java|kt|swift)$' >/dev/null; then
  echo "Native viewer source was duplicated into the npm package." >&2
  exit 1
fi

if find "${package_root}" -type f \
  \( -name '.env*' -o -name '.npmrc' -o -name '*.jks' -o -name '*.keystore' \
     -o -name '*.p12' -o -name '*.p8' -o -name '*private*key*' \) \
  -print -quit | grep -q .; then
  echo "Potential secret file found in the npm package." >&2
  exit 1
fi

release_contract_verifier="${release_source}/scripts/verify-react-native-contract.sh"
if [[ -f "${release_contract_verifier}" ]]; then
  bash "${release_contract_verifier}" "${package_root}/src/contract.ts"
fi

printf '%s\n' "Verified ${artifact_name}"
printf '%s\n' "  package sha256: ${actual_package_sha}"
printf '%s\n' "  native release: ${native_commit}"
printf '%s\n' "  Android AAR: ${expected_android_sha}"
printf '%s\n' "  iOS XCFramework: ${expected_ios_sha}"
