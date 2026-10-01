#!/usr/bin/env bash
set -euo pipefail

platform="${1:?Provide android or ios}"
output="${2:?Provide the recording output path}"
shift 2
: "${LEVIXEL_FLUTTER_DEVICE:?Provide the source-test device}"
mkdir -p "$(dirname "${output}")"
record_pid=''
remote_movie="/data/local/tmp/levixel-flutter-gestures-$$.mp4"

finish_recording() {
  if [[ "${platform}" == android ]]; then
    if [[ "${record_pid}" =~ ^[0-9]+$ ]]; then
      adb -s "${LEVIXEL_FLUTTER_DEVICE}" shell kill -INT "${record_pid}" || true
      for attempt in {1..50}; do
        if ! adb -s "${LEVIXEL_FLUTTER_DEVICE}" shell kill -0 "${record_pid}" 2>/dev/null; then break; fi
        sleep 0.1
      done
      adb -s "${LEVIXEL_FLUTTER_DEVICE}" pull "${remote_movie}" "${output}" || true
      adb -s "${LEVIXEL_FLUTTER_DEVICE}" shell rm -f "${remote_movie}" || true
    fi
    adb -s "${LEVIXEL_FLUTTER_DEVICE}" pull \
      /sdcard/Android/data/com.sandrox.tests.levixel_source_host/files/gestures \
      "$(dirname "${output}")/screenshots" || true
  elif [[ -n "${record_pid}" ]]; then
    kill -INT "${record_pid}" 2>/dev/null || true
    wait "${record_pid}" || true
  fi
}
trap finish_recording EXIT

case "${platform}" in
  android)
    record_pid="$(adb -s "${LEVIXEL_FLUTTER_DEVICE}" shell \
      "nohup screenrecord --time-limit 180 --bit-rate 4000000 '${remote_movie}' >/dev/null 2>&1 & echo \$!" | tr -d '\r')"
    ;;
  ios)
    xcrun simctl io "${LEVIXEL_FLUTTER_DEVICE}" recordVideo --codec=h264 --force "${output}" \
      > "${output}.log" 2>&1 &
    record_pid=$!
    ;;
  *) echo 'Recording platform must be android or ios.' >&2; exit 1 ;;
esac

"$@"
