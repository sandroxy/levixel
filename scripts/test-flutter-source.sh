#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
target="${1:-dart}"
if [[ $# -gt 1 || ! "${target}" =~ ^(dart|android|ios|ios-cocoapods)$ ]]; then
  echo "Usage: $0 [dart|android|ios|ios-cocoapods]" >&2
  exit 1
fi

if [[ "${target}" == dart ]]; then
  cd "${plugin_dir}/adapters/flutter"
  flutter pub get
  result=0
  dart format --output=none --set-exit-if-changed lib test "${script_dir}/fixtures/flutter" || result=1
  flutter analyze --fatal-infos || result=1
  flutter test --timeout 60s || result=1
  exit "${result}"
fi

work_dir="${plugin_dir}/dist/development/flutter-source-tests/${target}"
package_dir="${work_dir}/package"
host_dir="${work_dir}/host"
for path in "${plugin_dir}/dist" "${plugin_dir}/dist/development" \
  "${plugin_dir}/dist/development/flutter-source-tests" "${work_dir}" "${package_dir}" "${host_dir}"; do
  if [[ -L "${path}" ]]; then echo "Flutter source test output must not use symbolic links: ${path}" >&2; exit 1; fi
done
mkdir -p "${package_dir}"
rsync -a --delete --exclude .dart_tool --exclude build --exclude pubspec.lock \
  "${plugin_dir}/adapters/flutter/" "${package_dir}/"
cp "${plugin_dir}/LICENSE" "${package_dir}/LICENSE"
version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${plugin_dir}/plugin.yaml")"
package_version="$(ruby -ryaml -e 'print YAML.load_file(ARGV.fetch(0)).fetch("version")' "${package_dir}/pubspec.yaml")"
if [[ "${version}" != "${package_version}" ]]; then echo 'Flutter and native source versions must match.' >&2; exit 1; fi
printf 'version=%s\n' "${version}" > "${package_dir}/native-version.properties"

if [[ "${target}" == android ]]; then
  "${plugin_dir}/native/android/gradlew" -p "${plugin_dir}/native/android" \
    :levixel:publishReleasePublicationToLocalReleaseRepository --no-daemon --console=plain
  mkdir -p "${package_dir}/android/maven"
  cp -R "${plugin_dir}/native/android/levixel/build/maven-repository/." "${package_dir}/android/maven/"
  platform=android
else
  platform=ios
  archive="${work_dir}/Levixel-Simulator.xcarchive"
  xcodebuild -quiet archive -project "${plugin_dir}/native/ios/Levixel.xcodeproj" \
    -scheme Levixel -configuration Release -destination 'generic/platform=iOS Simulator' \
    -archivePath "${archive}" SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    MARKETING_VERSION="${version}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  framework="${archive}/Products/Library/Frameworks/Levixel.framework"
  cp "${plugin_dir}/LICENSE" "${plugin_dir}/THIRD_PARTY_NOTICES.md" "${framework}/"
  cp "${plugin_dir}/native/ios/Levixel/PrivacyInfo.xcprivacy" "${framework}/"
  xcodebuild -create-xcframework -framework "${framework}" \
    -output "${package_dir}/ios/sandrox_levixel/Frameworks/Levixel.xcframework"
fi

# This generated application is a source-test harness. Artifact acceptance uses
# the separate consumer repository and its immutable candidate installation.
if [[ ! -f "${host_dir}/pubspec.yaml" ]]; then
  flutter create --platforms="${platform}" --project-name levixel_source_host \
    --org com.sandrox.tests --no-pub "${host_dir}"
fi
cat > "${host_dir}/pubspec.yaml" <<'YAML'
name: levixel_source_host
version: 1.0.0+1
publish_to: none
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  sandrox_levixel:
    path: ../package
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
flutter:
  uses-material-design: true
YAML
if [[ "${target}" == ios-cocoapods ]]; then
  printf '  config:\n    enable-swift-package-manager: false\n' >> "${host_dir}/pubspec.yaml"
fi
cp "${script_dir}/fixtures/flutter/main.dart" "${host_dir}/lib/main.dart"
mkdir -p "${host_dir}/integration_test"
cp "${script_dir}/fixtures/flutter/viewer_test.dart" "${host_dir}/integration_test/viewer_test.dart"
cd "${host_dir}"
flutter pub get
if [[ "${platform}" == android ]]; then
  : "${LEVIXEL_FLUTTER_DEVICE:?Set LEVIXEL_FLUTTER_DEVICE to the Android emulator or device ID}"
else
  : "${LEVIXEL_FLUTTER_DEVICE:?Set LEVIXEL_FLUTTER_DEVICE to an available iOS simulator ID}"
fi
flutter test integration_test/viewer_test.dart -d "${LEVIXEL_FLUTTER_DEVICE}" --reporter expanded
if [[ "${platform}" == android ]]; then
  ./android/gradlew -p android :sandrox_levixel:lintDebug --no-daemon --console=plain
fi
