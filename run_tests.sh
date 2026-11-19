#!/usr/bin/env bash
set -Eeuo pipefail

SCREENSHOT_DIR="screenshots"
APPIUM_LOG="appium.log"
APPIUM_PID=""
EMULATOR_PID=""

mkdir -p "$SCREENSHOT_DIR"

cleanup() {
  local exit_code=$?

  echo "=== Cleaning up Appium ==="
  if [[ -n "${APPIUM_PID}" ]] && kill -0 "$APPIUM_PID" 2>/dev/null; then
    kill "$APPIUM_PID" 2>/dev/null || true
    wait "$APPIUM_PID" 2>/dev/null || true
  fi

  if [[ -n "${EMULATOR_PID}" ]] && kill -0 "$EMULATOR_PID" 2>/dev/null; then
    adb emu kill 2>/dev/null || true
    wait "$EMULATOR_PID" 2>/dev/null || true
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    echo "=== Test/setup failed; collecting diagnostics ==="
    adb logcat -d > "$SCREENSHOT_DIR/logcat_failure.txt" 2>/dev/null || true
    if [[ -f "$APPIUM_LOG" ]]; then
      tail -n 250 "$APPIUM_LOG" || true
    fi
  fi

  echo "=== run_tests.sh finished with exit code: $exit_code ==="
  exit "$exit_code"
}
trap cleanup EXIT

echo "=== Checking ADB connection ==="
echo "=== Starting emulator ==="
"${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}/emulator/emulator" -avd ci-api30 \
  -no-window \
  -no-audio \
  -no-boot-anim \
  -no-snapshot \
  -gpu swiftshader_indirect \
  -accel on \
  > emulator.log 2>&1 &
EMULATOR_PID=$!

for attempt in $(seq 1 60); do
  if adb get-state 2>/dev/null | grep -q '^device$'; then
    break
  fi
  if ! kill -0 "$EMULATOR_PID" 2>/dev/null; then
    echo "Emulator process exited during startup"
    cat emulator.log
    exit 1
  fi
  echo "  ... waiting for ADB (${attempt}/60)"
  sleep 5
done

adb get-state | grep -q '^device$'
adb devices

echo "=== Waiting for sys.boot_completed ==="
BOOT_TIMEOUT=300
ELAPSED=0

until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do
  if [[ "$ELAPSED" -ge "$BOOT_TIMEOUT" ]]; then
    echo "Emulator did not fully boot within ${BOOT_TIMEOUT}s"
    adb devices
    adb logcat -d | tail -n 50 || true
    exit 1
  fi

  echo "  ... still booting (${ELAPSED}s)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

echo "Android fully booted after ${ELAPSED}s"

adb shell input keyevent 82 || true
sleep 5

echo "=== Starting Appium ==="
npx appium --port 4723 \
       --log "$APPIUM_LOG" \
       --log-level info \
       --base-path '/' &
APPIUM_PID=$!

if ! npx wait-on http://127.0.0.1:4723/status --timeout 90000 --interval 2000; then
  echo "Appium failed to start"
  tail -n 250 "$APPIUM_LOG" 2>/dev/null || true
  exit 1
fi

echo "Appium server is ready!"

echo "=== Running Appium test ==="
set +e
node test_sample.js
TEST_EXIT=$?
set -e

if [[ "$TEST_EXIT" -ne 0 ]]; then
  echo "Appium test failed with exit code $TEST_EXIT"
else
  echo "Appium test passed"
fi

exit "$TEST_EXIT"
