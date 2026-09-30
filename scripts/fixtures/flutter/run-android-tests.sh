#!/usr/bin/env bash
set -euo pipefail

host_dir="${1:?Provide the generated Flutter source-test host}"
cd "${host_dir}"
flutter build apk --debug --target integration_test/viewer_test.dart --no-pub
./android/gradlew -p android app:connectedDebugAndroidTest :sandrox_levixel:lintDebug \
  "-Ptarget=${host_dir}/integration_test/viewer_test.dart" --no-daemon --console=plain
