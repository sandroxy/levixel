#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 6 ]]; then
  echo "Usage: $0 VERSION PACKAGE CHECKSUM NATIVE_MANIFEST ANDROID_AAR IOS_XCFRAMEWORK_ZIP" >&2
  exit 1
fi

version="$1"
artifact_path="$2"
checksum_path="$3"
native_manifest="$4"
android_artifact="$5"
ios_artifact="$6"
artifact_name="levixel-react-native-${version}.tgz"

for required_file in \
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
  ruby -rjson -e '
    manifest = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    abort("Unexpected native release schema") unless manifest["schemaVersion"] == 1
    abort("Unexpected native release plugin") unless manifest["plugin"] == "levixel"
    abort("Native release version mismatch") unless manifest["version"] == version
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

if tar -tvzf "${artifact_path}" | grep -Eq '^l'; then
  echo "Symbolic links are not allowed in the npm package." >&2
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
done < <(tar -tzf "${artifact_path}")

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

unexpected_project_urls="$(
  rg --no-filename -o '(git\+)?https://github\.com/sandroxy/[A-Za-z0-9_.-]+' "${package_root}" \
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

if tar -tzf "${artifact_path}" | rg -q \
  '(^|/)(native|Viewer|native-harmonyos)(/|$)|LevixelViewer(OverlayView|Controller|PageView)\.(java|kt|swift)$'; then
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

printf '%s\n' "Verified ${artifact_name}"
printf '%s\n' "  package sha256: ${actual_package_sha}"
printf '%s\n' "  native release: ${native_commit}"
printf '%s\n' "  Android AAR: ${expected_android_sha}"
printf '%s\n' "  iOS XCFramework: ${expected_ios_sha}"
