#!/usr/bin/env bash
set -euo pipefail

host_dir="${1:?Provide the generated Flutter source-test host}"
mode="${2:-lifecycle}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${host_dir}"
if [[ "${mode}" == gestures ]]; then
  entry=lib/gestures.dart
  test_class=com.sandrox.tests.levixel_source_host.NativeGestureTest
elif [[ "${mode}" == lifecycle ]]; then
  entry=integration_test/viewer_test.dart
  test_class=com.sandrox.tests.levixel_source_host.NativeViewerTest
else
  echo 'Test mode must be lifecycle or gestures.' >&2; exit 1
fi
flutter build apk --debug --target "${entry}" --no-pub
arguments=(-p android "-Ptarget=${host_dir}/${entry}" --no-daemon --console=plain
  "-Pandroid.testInstrumentationRunnerArguments.class=${test_class}")
if [[ "${mode}" == gestures ]]; then
  ./android/gradlew "${arguments[@]}" app:assembleDebugAndroidTest :sandrox_levixel:lintDebug
  bash "${script_dir}/record-gestures.sh" android "${host_dir}/../native-gestures.mp4" \
    ./android/gradlew "${arguments[@]}" app:connectedDebugAndroidTest
else
  ./android/gradlew "${arguments[@]}" app:connectedDebugAndroidTest :sandrox_levixel:lintDebug
fi
