#!/usr/bin/env bash
# Boot the iOS Simulator on a Codemagic Mac, install Runner.app, launch it,
# capture logs/screenshot, and fail if the process crashes.
# No external device farm — simctl only.
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.vero265.app}"
APP_PATH="${APP_PATH:-build/ios/iphonesimulator/Runner.app}"
WAIT_SECONDS="${WAIT_SECONDS:-25}"
LOG_DIR="${LOG_DIR:-build/simulator-smoke}"
PLIST_PATH="${PLIST_PATH:-ios/Runner/GoogleService-Info.plist}"

mkdir -p "$LOG_DIR"
export LOG_DIR

fail() {
  echo "::error::$1" >&2
  echo "$1" | tee -a "$LOG_DIR/result.txt" >&2
  exit 1
}

echo "=== iOS simulator smoke ==="
echo "bundle: $BUNDLE_ID"
echo "app:    $APP_PATH"

if [[ ! -d "$APP_PATH" ]]; then
  fail "Simulator .app not found at $APP_PATH. Build with: flutter build ios --simulator"
fi

if [[ -f "$PLIST_PATH" ]]; then
  src_bundle="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$PLIST_PATH" 2>/dev/null || true)"
  echo "GoogleService-Info.plist BUNDLE_ID=$src_bundle"
  if [[ -n "$src_bundle" && "$src_bundle" != "$BUNDLE_ID" ]]; then
    fail "Firebase plist bundle '$src_bundle' does not match app '$BUNDLE_ID'"
  fi
fi

app_plist="$APP_PATH/GoogleService-Info.plist"
if [[ ! -f "$app_plist" ]]; then
  fail "GoogleService-Info.plist was not copied into Runner.app (not in Copy Bundle Resources)"
fi
copied_bundle="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$app_plist" 2>/dev/null || true)"
echo "Runner.app GoogleService-Info.plist BUNDLE_ID=$copied_bundle"
if [[ -n "$copied_bundle" && "$copied_bundle" != "$BUNDLE_ID" ]]; then
  fail "Runner.app Firebase plist bundle '$copied_bundle' does not match '$BUNDLE_ID'"
fi

python3 - <<'PY' > "$LOG_DIR/device_udid.txt"
import json, subprocess, sys

raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"])
data = json.loads(raw)
preferred = ("iPhone 16", "iPhone 16 Pro", "iPhone 15", "iPhone 15 Pro", "iPhone 14")
candidates = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime and "iPhone" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable"):
            continue
        name = d.get("name", "")
        if "iPhone" not in name:
            continue
        candidates.append((name, d["udid"], runtime))

if not candidates:
    sys.exit("No available iPhone simulator")

def rank(item):
    name, udid, runtime = item
    for i, p in enumerate(preferred):
        if name.startswith(p):
            return i
    return 50

candidates.sort(key=rank)
name, udid, runtime = candidates[0]
print(udid)
open(__import__("os").environ["LOG_DIR"] + "/device.txt", "w").write(f"{name}\n{udid}\n{runtime}\n")
print(f"Using {name} ({udid}) {runtime}", file=sys.stderr)
PY

UDID="$(tr -d '[:space:]' < "$LOG_DIR/device_udid.txt")"
[[ -n "$UDID" ]] || fail "Could not pick a simulator UDID"
cat "$LOG_DIR/device.txt"

echo "Shutting down existing simulators..."
xcrun simctl shutdown all >/dev/null 2>&1 || true
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
echo "Simulator booted"

xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP_PATH"
echo "Installed $BUNDLE_ID"

# Stream logs BEFORE launch so a 200ms Firebase abort is captured.
xcrun simctl spawn "$UDID" log stream \
  --style compact \
  --level debug \
  --predicate '(process CONTAINS[c] "Runner") OR (eventMessage CONTAINS[c] "Firebase") OR (eventMessage CONTAINS[c] "GoogleService") OR (eventMessage CONTAINS[c] "SIGABRT") OR (eventMessage CONTAINS[c] "uncaught exception")' \
  > "$LOG_DIR/simctl-stream.log" 2>&1 &
LOG_PID=$!
sleep 2

LAUNCH_OUT="$(xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" 2>&1 | tee "$LOG_DIR/launch.txt")"
echo "$LAUNCH_OUT"
APP_PID="$(echo "$LAUNCH_OUT" | sed -n 's/.*: *\([0-9][0-9]*\).*/\1/p' | tail -1)"
echo "pid=$APP_PID" | tee "$LOG_DIR/pid.txt"

echo "Waiting ${WAIT_SECONDS}s for launch crash..."
sleep "$WAIT_SECONDS"

xcrun simctl io "$UDID" screenshot "$LOG_DIR/launch.png" >/dev/null 2>&1 || true
xcrun simctl spawn "$UDID" log show --last "${WAIT_SECONDS}s" --style compact \
  --predicate 'process CONTAINS[c] "Runner"' \
  > "$LOG_DIR/simctl-show.log" 2>&1 || true

kill "$LOG_PID" >/dev/null 2>&1 || true
wait "$LOG_PID" 2>/dev/null || true

xcrun simctl spawn "$UDID" ps -A > "$LOG_DIR/ps.txt" 2>&1 || true

STILL_RUNNING=0
if grep -E 'Runner\.app/Runner' "$LOG_DIR/ps.txt" >/dev/null 2>&1; then
  STILL_RUNNING=1
fi
if [[ -n "$APP_PID" ]] && grep -E "^[[:space:]]*${APP_PID}[[:space:]]" "$LOG_DIR/ps.txt" >/dev/null 2>&1; then
  STILL_RUNNING=1
fi

{
  find "$HOME/Library/Logs/CoreSimulator/$UDID" -name '*.ips' -mmin -10 2>/dev/null || true
  find "$HOME/Library/Logs/DiagnosticReports" -name '*Runner*' -mmin -10 2>/dev/null || true
  find "$HOME/Library/Logs/DiagnosticReports" -name '*vero265*' -mmin -10 2>/dev/null || true
} > "$LOG_DIR/crash-reports.txt"
if [[ -s "$LOG_DIR/crash-reports.txt" ]]; then
  while IFS= read -r report; do
    cp "$report" "$LOG_DIR/" 2>/dev/null || true
  done < "$LOG_DIR/crash-reports.txt"
fi

cat "$LOG_DIR/simctl-stream.log" "$LOG_DIR/simctl-show.log" "$LOG_DIR/launch.txt" \
  > "$LOG_DIR/combined.log" 2>/dev/null || true

CRASH_HITS="$(
  grep -Ei \
    'Terminating app due to uncaught exception|uncaught exception|SIGABRT|Fatal Exception|Could not locate configuration file|GoogleService-Info\.plist|Bundle ID is inconsistent|FirebaseApp\.configure|EXC_CRASH|abort\(\) called|\*\*\* Assertion failure' \
    "$LOG_DIR/combined.log" 2>/dev/null || true
)"

if [[ -n "${CM_EXPORT_DIR:-}" ]]; then
  mkdir -p "$CM_EXPORT_DIR/simulator-smoke"
  cp -R "$LOG_DIR/." "$CM_EXPORT_DIR/simulator-smoke/" || true
fi

echo "still_running=$STILL_RUNNING"
if [[ -n "$CRASH_HITS" ]]; then
  echo "$CRASH_HITS" | tee "$LOG_DIR/crash-hits.txt"
  fail "Simulator launch log shows a crash (Firebase/plist/SIGABRT). See simulator-smoke artifacts."
fi
if [[ -s "$LOG_DIR/crash-reports.txt" ]]; then
  cat "$LOG_DIR/crash-reports.txt"
  fail "Simulator wrote a crash report (.ips). See simulator-smoke artifacts."
fi
if [[ "$STILL_RUNNING" -ne 1 ]]; then
  fail "Runner exited within ${WAIT_SECONDS}s — treated as a launch crash. See simulator-smoke/ps.txt and logs."
fi

echo "Simulator smoke passed: $BUNDLE_ID stayed alive, no crash log." | tee "$LOG_DIR/result.txt"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
