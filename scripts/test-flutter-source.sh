#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_dir="$(cd "${script_dir}/.." && pwd)"
target="${1:-dart}"
mode="${2:-lifecycle}"
if [[ $# -gt 2 || ! "${target}" =~ ^(dart|android|ios|ios-cocoapods)$ \
  || ! "${mode}" =~ ^(lifecycle|gestures)$ || ( "${target}" == dart && "${mode}" != lifecycle ) ]]; then
  echo "Usage: $0 [dart|android|ios|ios-cocoapods] [lifecycle|gestures]" >&2
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
cp "${script_dir}/fixtures/flutter/gestures.dart" "${host_dir}/lib/gestures.dart"
mkdir -p "${host_dir}/integration_test"
cp "${script_dir}/fixtures/flutter/viewer_test.dart" "${host_dir}/integration_test/viewer_test.dart"
cd "${host_dir}"
flutter pub get
if [[ "${platform}" == android ]]; then
  : "${LEVIXEL_FLUTTER_DEVICE:?Set LEVIXEL_FLUTTER_DEVICE to the Android emulator or device ID}"
  export ANDROID_SERIAL="${LEVIXEL_FLUTTER_DEVICE}"
  test_package="${host_dir}/android/app/src/androidTest/java/com/sandrox/tests/levixel_source_host"
  mkdir -p "${test_package}"
  cp "${script_dir}/fixtures/flutter/NativeViewerTest.java" "${test_package}/NativeViewerTest.java"
  cp "${script_dir}/fixtures/flutter/NativeGestureTest.java" "${test_package}/NativeGestureTest.java"
  cp "${script_dir}/fixtures/flutter/android-tests.gradle" "${host_dir}/android/levixel-source-tests.gradle"
  ruby - "${host_dir}/android/app/build.gradle.kts" <<'RUBY'
path = ARGV.fetch(0)
contents = File.read(path)
entry = 'apply(from = "../levixel-source-tests.gradle")'
File.write(path, "#{contents}\n#{entry}\n") unless contents.include?(entry)
RUBY
  native_command=(bash "${script_dir}/fixtures/flutter/run-android-tests.sh" "${host_dir}" "${mode}")
else
  : "${LEVIXEL_FLUTTER_DEVICE:?Set LEVIXEL_FLUTTER_DEVICE to an available iOS simulator ID}"
  cp "${script_dir}/fixtures/flutter/RunnerTests.swift" "${host_dir}/ios/RunnerTests/RunnerTests.swift"
  entry=integration_test/viewer_test.dart
  result_bundle="${work_dir}/latest.xcresult"
  if [[ "${mode}" == gestures ]]; then
    entry=lib/gestures.dart
    result_bundle="${work_dir}/gestures.xcresult"
  fi
  flutter build ios --debug --simulator --config-only --no-codesign --target "${entry}"
  if [[ "${target}" == ios-cocoapods ]]; then (cd ios && pod install); fi
  for output in "${work_dir}/DerivedData" "${result_bundle}"; do
    if [[ -L "${output}" ]]; then echo "Flutter test output must not use symbolic links: ${output}" >&2; exit 1; fi
  done
  if [[ -e "${result_bundle}" ]]; then rm -r "${result_bundle}"; fi
  if [[ "${mode}" == gestures ]]; then
    mkdir -p "${host_dir}/ios/RunnerUITests"
    cp "${script_dir}/fixtures/flutter/RunnerUITests.swift" "${host_dir}/ios/RunnerUITests/RunnerUITests.swift"
    ruby "${script_dir}/fixtures/flutter/prepare-ios-gesture-tests.rb" "${host_dir}/ios/Runner.xcodeproj"
    native_command=(bash "${script_dir}/fixtures/flutter/run-ios-gesture-tests.sh" "${host_dir}" "${work_dir}")
  else
    native_command=(xcodebuild -quiet test -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug
      -destination "platform=iOS Simulator,id=${LEVIXEL_FLUTTER_DEVICE},arch=$(uname -m)"
      -derivedDataPath "${work_dir}/DerivedData" -resultBundlePath "${result_bundle}"
      -parallel-testing-enabled NO -test-timeouts-enabled YES
      -default-test-execution-time-allowance 120 -maximum-test-execution-time-allowance 180
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
  fi
fi
ruby -rtimeout - "${LEVIXEL_FLUTTER_TEST_TIMEOUT:-600}" "${native_command[@]}" <<'RUBY' 2>&1 | tee "${work_dir}/${mode}-test.log"
limit = Integer(ARGV.shift, 10)
abort 'LEVIXEL_FLUTTER_TEST_TIMEOUT must be positive' unless limit.positive?

def signal_group(pid, signal)
  Process.kill(signal, -pid)
rescue Errno::ESRCH
  # The command may have exited while its timeout was being delivered.
end

pid = Process.spawn(*ARGV, pgroup: true)
begin
  _, status = Timeout.timeout(limit) { Process.wait2(pid) }
  exit(status.exitstatus || 1)
rescue Timeout::Error
  warn "Flutter source test command exceeded #{limit} seconds."
  signal_group(pid, 'TERM')
  begin
    Timeout.timeout(10) { Process.wait(pid) }
  rescue Timeout::Error
    signal_group(pid, 'KILL')
    Process.wait(pid)
  rescue Errno::ECHILD
  end
  exit 124
end
RUBY
