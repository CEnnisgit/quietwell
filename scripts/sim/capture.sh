#!/usr/bin/env bash
# Launches every DEBUG screenshot hook, waits for Documents/app-state.json to say ready, lets the
# screen settle and captures a Simulator screenshot.
# Usage: capture.sh <udid> <bundle-id> <out-dir> <hook[:pro]>...
set -euo pipefail
UDID="$1"; BUNDLE="$2"; OUT="$3"; shift 3
mkdir -p "$OUT"
TMP=$(mktemp -d)
STATE_FILE="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)/Documents/app-state.json"

wait_ready() {
  local waited=0
  while [ "$waited" -lt 60 ]; do
    if [ -f "$STATE_FILE" ] && python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("ready")=="true" else 1)' "$STATE_FILE" 2>/dev/null; then
      return 0
    fi
    sleep 2; waited=$((waited + 2))
  done
  echo "  state never became ready:"; cat "$STATE_FILE" 2>/dev/null || echo "  (no state file)"
  return 1
}

settle_and_capture() {
  local target="$1" prev="$TMP/prev.png" cur="$TMP/cur.png" waited=0
  sleep 2
  xcrun simctl io "$UDID" screenshot --type=png "$prev" >/dev/null 2>&1
  while [ "$waited" -lt 30 ]; do
    sleep 2; waited=$((waited + 2))
    xcrun simctl io "$UDID" screenshot --type=png "$cur" >/dev/null 2>&1
    if cmp -s "$prev" "$cur"; then break; fi
    mv "$cur" "$prev"
  done
  xcrun simctl io "$UDID" screenshot --type=png "$target"
}

fail=0; i=0
for spec in "$@"; do
  i=$((i + 1))
  hook="${spec%%:*}"; pro=NO
  [ "$spec" != "$hook" ] && pro=YES
  file=$(printf "%s/%02d-%s.png" "$OUT" "$i" "$hook")
  echo "== $hook (pro=$pro) -> $file"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  rm -f "$STATE_FILE"; sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" -AppScreen "$hook" -AppPro "$pro"
  wait_ready || fail=1
  settle_and_capture "$file"
  cp "$STATE_FILE" "${file%.png}.json" 2>/dev/null || true
done
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
rm -rf "$TMP"
exit "$fail"
