#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 9 && $# -ne 12 ]]; then
  echo "Usage: $0 UTS_VERSION NATIVE_VERSION RELEASE_SOURCE NATIVE_MANIFEST ANDROID_AAR IOS_XCFRAMEWORK_ZIP UTS_ZIP UTS_CHECKSUM UTS_ACCEPTED_SHA256 [LEGACY_ZIP LEGACY_CHECKSUM LEGACY_ACCEPTED_SHA256]" >&2
  exit 1
fi

version="$1"
native_version="$2"
release_source="$3"
native_manifest="$4"
android_artifact="$5"
ios_artifact="$6"
uts_artifact="$7"
uts_checksum="$8"
uts_accepted_sha256="$9"
legacy_artifact="${10:-}"
legacy_checksum="${11:-}"
legacy_accepted_sha256="${12:-}"

for declared_version in "${version}" "${native_version}"; do
  if [[ ! "${declared_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Only stable semantic versions are verifiable: ${declared_version}" >&2
    exit 1
  fi
done

for checksum in "${uts_accepted_sha256}" "${legacy_accepted_sha256}"; do
  if [[ -n "${checksum}" && ! "${checksum}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Accepted SHA-256 is invalid: ${checksum}" >&2
    exit 1
  fi
done

for required_path in \
  "${release_source}" \
  "${native_manifest}" \
  "${android_artifact}" \
  "${ios_artifact}" \
  "${uts_artifact}" \
  "${uts_checksum}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "Required release input is missing: ${required_path}" >&2
    exit 1
  fi
done

ios_runtime_source="${release_source}/adapters/uniapp/ios/LevixelUniRuntime"
ios_api_verifier="${release_source}/scripts/verify-ios-core-adapter-api.sh"
if [[ -f "${ios_api_verifier}" ]]; then
  bash "${ios_api_verifier}" "${ios_artifact}"
elif grep -R -E -q \
  'itemIdentifiers[[:space:]]*:|registerLevixelSource\([^)]*itemIdentifier[[:space:]]*:' \
  "${ios_runtime_source}" 2>/dev/null; then
  echo "Release source uses stable iOS media identities but is missing its matching API verifier." >&2
  exit 1
fi

if [[ -n "${legacy_artifact}" || -n "${legacy_checksum}" || -n "${legacy_accepted_sha256}" ]]; then
  if [[ -z "${legacy_artifact}" || -z "${legacy_checksum}" || -z "${legacy_accepted_sha256}" ]]; then
    echo "Legacy verification requires the ZIP, checksum sidecar, and accepted SHA-256 together." >&2
    exit 1
  fi
  for required_path in "${legacy_artifact}" "${legacy_checksum}"; do
    if [[ ! -f "${required_path}" ]]; then
      echo "Required legacy release input is missing: ${required_path}" >&2
      exit 1
    fi
  done
  if [[ "${native_version}" != "${version}" ]]; then
    echo "Legacy verification must use its own release where product and native versions match." >&2
    exit 1
  fi
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

sha256_file() {
  ruby -rdigest -e 'print Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$1"
}

verify_checksum_sidecar() {
  local artifact_path="$1"
  local checksum_path="$2"
  local accepted_sha256="$3"
  local expected_name="$4"
  local actual_sha256
  local recorded_sha256
  local recorded_name

  actual_sha256="$(sha256_file "${artifact_path}")"
  read -r recorded_sha256 recorded_name < "${checksum_path}"
  if [[ "${actual_sha256}" != "${accepted_sha256}" \
    || "${recorded_sha256}" != "${accepted_sha256}" \
    || "${recorded_name}" != "${expected_name}" ]]; then
    echo "Release checksum does not match the accepted ${expected_name}." >&2
    exit 1
  fi
}

verify_safe_zip() {
  local archive_path="$1"
  local listing_path="$2"

  unzip -Z1 "${archive_path}" > "${listing_path}"
  ruby -e '
    entries = File.readlines(ARGV.fetch(0), chomp: true)
    abort("ZIP is empty") if entries.empty?
    entries.each do |entry|
      abort("Unsafe absolute ZIP path: #{entry}") if entry.start_with?("/")
      abort("Unsafe ZIP path separator: #{entry}") if entry.include?("\\")
      parts = entry.split("/")
      abort("Unsafe parent ZIP path: #{entry}") if parts.include?("..")
    end
  ' "${listing_path}"

  if grep -Eq '(^|/)(__MACOSX|\.DS_Store)(/|$)' "${listing_path}"; then
    echo "Release ZIP contains macOS metadata: ${archive_path}" >&2
    exit 1
  fi
  if zipinfo -l "${archive_path}" | awk '$1 ~ /^l/ { found = 1 } END { exit(found ? 0 : 1) }'; then
    echo "Release ZIP contains a symbolic link: ${archive_path}" >&2
    exit 1
  fi
}

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
  ' "${native_manifest}" "${native_version}"
)

actual_release_commit="$(git -C "${release_source}" rev-parse HEAD)"
uts_tag_commit="$(git -C "${release_source}" rev-parse --verify "refs/tags/${version}^{commit}")"
native_tag_commit="$(git -C "${release_source}" rev-parse --verify "refs/tags/${native_version}^{commit}")"
if [[ "${actual_release_commit}" != "${uts_tag_commit}" ]]; then
  echo "Release source HEAD ${actual_release_commit} does not equal UniApp tag ${version} commit ${uts_tag_commit}." >&2
  exit 1
fi
if [[ "${native_commit}" != "${native_tag_commit}" ]]; then
  echo "Native manifest commit ${native_commit} does not equal native tag ${native_version} commit ${native_tag_commit}." >&2
  exit 1
fi

read -r source_version source_uts_version source_native_version source_legacy_version uts_source_version < <(
  ruby -ryaml -rjson -e '
    root = ARGV.fetch(0)
    manifest = YAML.load_file(File.join(root, "plugin.yaml"))
    root_version = manifest.fetch("version")
    targets = manifest.fetch("targets")
    uts = targets.find { |target| target.fetch("id") == "uniapp" }
    abort("UniApp target is missing") unless uts
    native_constraints = uts.fetch("constraints", []).select do |constraint|
      constraint.fetch("name") == "native-release-version"
    end
    abort("Multiple native-release-version constraints") if native_constraints.length > 1
    resolved_native_version = native_constraints.empty? ? root_version : native_constraints.fetch(0).fetch("value")
    legacy = targets.find { |target| target.fetch("id") == "uniapp-native-compat" }
    puts [
      root_version,
      uts.fetch("version", root_version),
      resolved_native_version,
      legacy ? legacy.fetch("version", root_version) : root_version,
      JSON.parse(File.read(File.join(root, "uni_modules/Sandrox-Levixel/package.json"))).fetch("version")
    ].join(" ")
  ' "${release_source}"
)
if [[ "${source_uts_version}" != "${version}" \
  || "${uts_source_version}" != "${version}" \
  || "${source_native_version}" != "${native_version}" \
  || "${source_version}" != "${native_version}" ]]; then
  echo "Release source does not declare UTS ${version} with native ${native_version}." >&2
  exit 1
fi
if [[ -n "${legacy_artifact}" && "${source_legacy_version}" != "${version}" ]]; then
  echo "Legacy verification must run against its own ${source_legacy_version} release source, not UTS ${version}." >&2
  exit 1
fi

actual_android_sha="$(sha256_file "${android_artifact}")"
actual_ios_sha="$(sha256_file "${ios_artifact}")"
actual_android_bytes="$(wc -c < "${android_artifact}" | tr -d ' ')"
actual_ios_bytes="$(wc -c < "${ios_artifact}" | tr -d ' ')"
if [[ "${actual_android_sha}" != "${expected_android_sha}" \
  || "${actual_android_bytes}" != "${expected_android_bytes}" ]]; then
  echo "Public Android AAR does not match the accepted native release." >&2
  exit 1
fi
if [[ "${actual_ios_sha}" != "${expected_ios_sha}" \
  || "${actual_ios_bytes}" != "${expected_ios_bytes}" ]]; then
  echo "Public iOS XCFramework does not match the accepted native release." >&2
  exit 1
fi

unzip -q "${ios_artifact}" 'Levixel.xcframework/ios-arm64/*' -d "${work_dir}/native-ios"
accepted_ios_framework="${work_dir}/native-ios/Levixel.xcframework/ios-arm64/Levixel.framework"
if [[ ! -d "${accepted_ios_framework}" ]]; then
  echo "Accepted XCFramework does not contain its iOS device framework." >&2
  exit 1
fi

verify_android_runtime() {
  local runtime_aar="$1"
  local classes_jar="$2"
  local classes_listing="$3"

  unzip -p "${runtime_aar}" classes.jar > "${classes_jar}"
  jar tf "${classes_jar}" > "${classes_listing}"
  if ! grep -q '^com/sandrox/levixel/uniapp/runtime/LevixelUniRuntime.class$' "${classes_listing}"; then
    echo "Android shared runtime facade is missing." >&2
    exit 1
  fi
  if awk '
    /^io\/dcloud\/.+\.class$/ { found = 1 }
    /^com\/sandrox\/levixel\/.+\.class$/ && $0 !~ /^com\/sandrox\/levixel\/uniapp\/runtime\// { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "${classes_listing}"; then
    echo "Android shared runtime contains DCloud or copied core classes." >&2
    exit 1
  fi
}

verify_uts() {
  local artifact_name="levixel-uniapp-${version}.zip"
  local package_root="${work_dir}/uts-package"
  local listing_path="${work_dir}/uts-listing.txt"
  local source_root="${release_source}/uni_modules/Sandrox-Levixel"

  if [[ "$(basename "${uts_artifact}")" != "${artifact_name}" ]]; then
    echo "Unexpected UTS release filename: ${uts_artifact}" >&2
    exit 1
  fi
  verify_checksum_sidecar "${uts_artifact}" "${uts_checksum}" "${uts_accepted_sha256}" "${artifact_name}"
  verify_safe_zip "${uts_artifact}" "${listing_path}"
  if ! grep -q '^package\.json$' "${listing_path}" \
    || ! grep -q '^utssdk/' "${listing_path}" \
    || grep -q '^Sandrox-Levixel/' "${listing_path}"; then
    echo "UTS ZIP must expose package.json and utssdk directly at its root." >&2
    exit 1
  fi
  if grep -Eiq '(^|/)(nativeplugins|uniapp-v8-release|DCUni\.framework|DCloud[^/]*\.framework|libWeex)(/|$)' "${listing_path}"; then
    echo "UTS ZIP contains an unexpected legacy or DCloud SDK payload." >&2
    exit 1
  fi

  unzip -q "${uts_artifact}" -d "${package_root}"
  for required_path in \
    package.json \
    readme.md \
    changelog.md \
    license.md \
    LICENSE \
    THIRD_PARTY_NOTICES.md \
    js_sdk/index.js \
    js_sdk/canonical.js \
    js_sdk/index.d.ts \
    utssdk/interface.uts \
    utssdk/app-android/index.uts \
    utssdk/app-android/config.json \
    "utssdk/app-android/libs/LevixelUniRuntime-${native_version}.aar" \
    "utssdk/app-android/libs/Levixel-${native_version}.aar" \
    utssdk/app-android/libs/PhotoView-2.3.0.aar \
    utssdk/app-ios/index.uts \
    utssdk/app-ios/config.json \
    utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/LevixelUniRuntime \
    utssdk/app-ios/Frameworks/Levixel.framework/Levixel; do
    if [[ ! -e "${package_root}/${required_path}" ]]; then
      echo "UTS release is missing ${required_path}." >&2
      exit 1
    fi
  done

  for source_path in \
    package.json \
    readme.md \
    changelog.md \
    license.md \
    LICENSE \
    THIRD_PARTY_NOTICES.md \
    js_sdk/index.js \
    js_sdk/canonical.js \
    utssdk/interface.uts \
    utssdk/app-android/index.uts \
    utssdk/app-android/config.json \
    utssdk/app-ios/index.uts \
    utssdk/app-ios/config.json; do
    cmp "${source_root}/${source_path}" "${package_root}/${source_path}"
  done
  cmp "${release_source}/adapters/uniapp/js_sdk/index.d.ts" "${package_root}/js_sdk/index.d.ts"

  ruby -rjson -e '
    package = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    source_package = JSON.parse(File.read(ARGV.fetch(2)))
    abort("Unexpected package id") unless package.fetch("id") == "Sandrox-Levixel"
    abort("Unexpected package version") unless package.fetch("version") == version
    abort("Package must be a UTS plugin") unless package.dig("dcloudext", "type") == "uts"
    abort("Legacy metadata must not exist") if package.key?("_dp_nativeplugin")
    abort("Release-source package id mismatch") unless source_package.fetch("id") == package.fetch("id")
    abort("Release-source package version mismatch") unless source_package.fetch("version") == version
    abort("Engine declaration drifted from release source") unless package.fetch("engines") == source_package.fetch("engines")
    expected_platforms = source_package.dig("uni_modules", "platforms")
    abort("Platform declaration drifted from release source") unless package.dig("uni_modules", "platforms") == expected_platforms
    keywords = package.fetch("keywords")
    abort("DCloud permits at most five keywords") unless keywords.is_a?(Array) && keywords.length <= 5

    client = expected_platforms.fetch("client")
    client.each_value do |runtime|
      next unless runtime.is_a?(Hash)
      app = runtime["app"]
      next unless app.is_a?(Hash)
      %w[android ios].each do |platform|
        declaration = app[platform]
        next if declaration.nil? || declaration == "x"
        abort("Invalid #{platform} support declaration") unless declaration.is_a?(Hash)
        abort("#{platform} extVersion must match the package version") unless declaration["extVersion"] == version
        minimum = declaration["minVersion"]
        abort("#{platform} minVersion must be non-empty") unless minimum.is_a?(String) && !minimum.empty?
      end
    end
  ' "${package_root}/package.json" "${version}" "${source_root}/package.json"

  verify_android_runtime \
    "${package_root}/utssdk/app-android/libs/LevixelUniRuntime-${native_version}.aar" \
    "${work_dir}/uts-runtime-classes.jar" \
    "${work_dir}/uts-runtime-classes.txt"
  cmp "${android_artifact}" "${package_root}/utssdk/app-android/libs/Levixel-${native_version}.aar"
  if [[ "${version}" != "${native_version}" \
    && ( -e "${package_root}/utssdk/app-android/libs/Levixel-${version}.aar" \
      || -e "${package_root}/utssdk/app-android/libs/LevixelUniRuntime-${version}.aar" ) ]]; then
    echo "UTS ${version} must not relabel its native ${native_version} Android dependencies." >&2
    exit 1
  fi
  diff -qr "${accepted_ios_framework}" "${package_root}/utssdk/app-ios/Frameworks/Levixel.framework"

  local runtime_binary="${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/LevixelUniRuntime"
  if ! file "${runtime_binary}" | grep -qF 'current ar archive'; then
    echo "UTS iOS runtime must be a static framework." >&2
    exit 1
  fi
  if ! grep -Eq 'openWithJSON:.*rootView:.*viewController:.*completion:' \
    "${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/Headers/LevixelUniRuntime-Swift.h" \
    || ! grep -q 'setJSONEventHandler:' \
    "${package_root}/utssdk/app-ios/Frameworks/LevixelUniRuntime.framework/Headers/LevixelUniRuntime-Swift.h"; then
    echo "UTS iOS runtime entry points are incomplete." >&2
    exit 1
  fi

  node --input-type=module --check < "${package_root}/js_sdk/index.js"
  node --input-type=module --check < "${package_root}/js_sdk/canonical.js"
  LEVIXEL_UNIAPP_SDK_PATH="${package_root}/js_sdk/canonical.js" \
    node "${release_source}/adapters/uniapp/js_sdk/index.test.mjs"

  printf '%s\n' "Verified public UTS asset: ${artifact_name}"
  printf '%s\n' "  accepted sha256: ${uts_accepted_sha256}"
}

verify_legacy() {
  local artifact_name="levixel-uniapp-legacy-${version}.zip"
  local package_root="${work_dir}/legacy-package/Sandrox-Levixel"
  local listing_path="${work_dir}/legacy-listing.txt"

  if [[ "$(basename "${legacy_artifact}")" != "${artifact_name}" ]]; then
    echo "Unexpected legacy release filename: ${legacy_artifact}" >&2
    exit 1
  fi
  verify_checksum_sidecar "${legacy_artifact}" "${legacy_checksum}" "${legacy_accepted_sha256}" "${artifact_name}"
  verify_safe_zip "${legacy_artifact}" "${listing_path}"
  if grep -Evq '^Sandrox-Levixel(/|$)' "${listing_path}"; then
    echo "Legacy ZIP must contain only the Sandrox-Levixel plugin root." >&2
    exit 1
  fi
  if grep -Eiq '(^|/)(uniapp-v8-release|DCUni\.framework|DCloud[^/]*\.framework|libWeex)(/|$)' "${listing_path}"; then
    echo "Legacy ZIP must not redistribute the DCloud SDK." >&2
    exit 1
  fi

  unzip -q "${legacy_artifact}" -d "${work_dir}/legacy-package"
  for required_path in \
    package.json \
    LICENSE \
    THIRD_PARTY_NOTICES.md \
    js_sdk/index.js \
    js_sdk/index.d.ts \
    android/LevixelUniApp-release.aar \
    "android/LevixelUniRuntime-${version}.aar" \
    "android/Levixel-${version}.aar" \
    android/PhotoView-2.3.0.aar \
    ios/LevixelUniApp.framework/LevixelUniApp \
    ios/LevixelUniRuntime.framework/LevixelUniRuntime \
    ios/Levixel.framework/Levixel; do
    if [[ ! -e "${package_root}/${required_path}" ]]; then
      echo "Legacy release is missing ${required_path}." >&2
      exit 1
    fi
  done

  cmp "${release_source}/LICENSE" "${package_root}/LICENSE"
  cmp "${release_source}/THIRD_PARTY_NOTICES.md" "${package_root}/THIRD_PARTY_NOTICES.md"
  cmp "${release_source}/adapters/uniapp/js_sdk/index.js" "${package_root}/js_sdk/index.js"
  cmp "${release_source}/adapters/uniapp/js_sdk/index.d.ts" "${package_root}/js_sdk/index.d.ts"

  ruby -rjson -e '
    package = JSON.parse(File.read(ARGV.fetch(0)))
    version = ARGV.fetch(1)
    abort("Unexpected package id") unless package.fetch("id") == "Sandrox-Levixel"
    abort("Unexpected package version") unless package.fetch("version") == version
    abort("Package must be a native plugin") unless package.fetch("_dp_type") == "nativeplugin"
    native = package.fetch("_dp_nativeplugin")
    android = native.fetch("android")
    ios = native.fetch("ios")
    expected_android = [{"type" => "module", "name" => "Sandrox-Levixel", "class" => "com.sandrox.levixel.uniapp.LevixelUniModule"}]
    expected_ios = [{"type" => "module", "name" => "Sandrox-Levixel", "class" => "LevixelUniModule"}]
    abort("Unexpected Android module") unless android.fetch("plugins") == expected_android
    abort("Unexpected iOS module") unless ios.fetch("plugins") == expected_ios
    abort("Unexpected Android minimum") unless android.fetch("minSdkVersion") == "21"
    abort("Unexpected iOS minimum") unless ios.fetch("deploymentTarget") == "13.0"
    abort("Unexpected iOS architecture") unless ios.fetch("validArchitectures") == ["arm64"]
    abort("Levixel.framework must be embedded") unless ios.fetch("embedFrameworks") == ["Levixel.framework"]
  ' "${package_root}/package.json" "${version}"

  unzip -p "${package_root}/android/LevixelUniApp-release.aar" classes.jar > "${work_dir}/legacy-bridge-classes.jar"
  jar tf "${work_dir}/legacy-bridge-classes.jar" > "${work_dir}/legacy-bridge-classes.txt"
  if ! grep -q '^com/sandrox/levixel/uniapp/LevixelUniModule.class$' "${work_dir}/legacy-bridge-classes.txt" \
    || grep -Eq '^io/dcloud/.+\.class$|^com/sandrox/levixel/uniapp/runtime/.+\.class$' "${work_dir}/legacy-bridge-classes.txt"; then
    echo "Legacy Android bridge classes are incomplete or contain copied dependencies." >&2
    exit 1
  fi

  verify_android_runtime \
    "${package_root}/android/LevixelUniRuntime-${version}.aar" \
    "${work_dir}/legacy-runtime-classes.jar" \
    "${work_dir}/legacy-runtime-classes.txt"
  cmp "${android_artifact}" "${package_root}/android/Levixel-${version}.aar"
  diff -qr "${accepted_ios_framework}" "${package_root}/ios/Levixel.framework"

  if ! file "${package_root}/ios/LevixelUniApp.framework/LevixelUniApp" | grep -qF 'current ar archive' \
    || ! file "${package_root}/ios/LevixelUniRuntime.framework/LevixelUniRuntime" | grep -qF 'current ar archive'; then
    echo "Legacy iOS bridge and runtime must be static frameworks." >&2
    exit 1
  fi

  LEVIXEL_UNIAPP_SDK_PATH="${package_root}/js_sdk/index.js" \
    node "${release_source}/adapters/uniapp/js_sdk/index.test.mjs"

  printf '%s\n' "Verified public legacy compatibility asset: ${artifact_name}"
  printf '%s\n' "  accepted sha256: ${legacy_accepted_sha256}"
}

verify_uts
if [[ -n "${legacy_artifact}" ]]; then
  verify_legacy
fi

printf '%s\n' "  UTS release source: ${actual_release_commit}"
printf '%s\n' "  native ${native_version} source: ${native_commit}"
printf '%s\n' "  Android AAR: ${expected_android_sha}"
printf '%s\n' "  iOS XCFramework: ${expected_ios_sha}"
