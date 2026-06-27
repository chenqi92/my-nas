#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="my_nas"
BUNDLE_ID="com.kkape.mynas"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/build/macos/Build/Products/Debug/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
DEBUG_DYLIB="$APP_BUNDLE/Contents/MacOS/$APP_NAME.debug.dylib"

usage() {
  echo "usage: $0 [run|--verify|--logs|--telemetry|--debug]" >&2
}

kill_existing() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -f "$APP_EXECUTABLE" >/dev/null 2>&1 || true
}

build_app() {
  (cd "$ROOT_DIR" && flutter build macos --debug)
}

postprocess_app() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: app bundle not found: $APP_BUNDLE" >&2
    exit 1
  fi

  # macOS 26 can attach provenance metadata to local build outputs. When it is
  # present on Flutter debug dylibs, dyld may reject them even though codesign
  # reports the bundle as valid.
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true

  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1
  if [[ -f "$DEBUG_DYLIB" ]]; then
    codesign --verify --verbose=2 "$DEBUG_DYLIB" >/dev/null 2>&1
  fi
}

launch_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

wait_for_process() {
  local deadline=$((SECONDS + 20))
  local pid=""

  while (( SECONDS < deadline )); do
    pid="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
    if [[ -n "$pid" ]]; then
      echo "$APP_NAME is running (pid $pid)"
      return 0
    fi
    sleep 1
  done

  echo "error: $APP_NAME did not stay running after launch" >&2
  echo "recent diagnostic reports:" >&2
  ls -lt "$HOME/Library/Logs/DiagnosticReports/$APP_NAME"-*.ips 2>/dev/null | head -5 >&2 || true
  echo "recent unified logs:" >&2
  /usr/bin/log show --style compact --last 2m \
    --predicate "process == \"$APP_NAME\" OR eventMessage CONTAINS[c] \"$APP_NAME\" OR eventMessage CONTAINS[c] \"$BUNDLE_ID\"" \
    2>/dev/null | tail -120 >&2 || true
  return 1
}

run_pipeline() {
  kill_existing
  build_app
  postprocess_app
  launch_app
}

case "$MODE" in
  run)
    run_pipeline
    ;;
  --verify|verify)
    run_pipeline
    wait_for_process
    ;;
  --logs|logs)
    run_pipeline
    wait_for_process
    /usr/bin/log stream --info --style compact \
      --predicate "process == \"$APP_NAME\" OR eventMessage CONTAINS[c] \"$BUNDLE_ID\""
    ;;
  --telemetry|telemetry)
    run_pipeline
    wait_for_process
    /usr/bin/log stream --info --style compact \
      --predicate "subsystem == \"$BUNDLE_ID\" OR process == \"$APP_NAME\""
    ;;
  --debug|debug)
    kill_existing
    build_app
    postprocess_app
    lldb -- "$APP_EXECUTABLE"
    ;;
  *)
    usage
    exit 2
    ;;
esac
