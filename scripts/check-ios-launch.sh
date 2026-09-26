#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SIMULATOR_ID=${1:-}
if [ -z "$SIMULATOR_ID" ]; then
  SIMULATOR_ID=$(xcrun simctl list devices booted --json | python3 -c '
import json, sys
devices = [device for group in json.load(sys.stdin)["devices"].values() for device in group]
booted = [device["udid"] for device in devices if device["state"] == "Booted"]
if len(booted) != 1:
    raise SystemExit("Boot exactly one iOS simulator, or pass its UDID.")
print(booted[0])')
fi

DERIVED_DATA=${DRILLBIT_LAUNCH_DERIVED_DATA:-/tmp/drillbit-signed-launch}
APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Drillbit.app"

xcodebuild build -project "$ROOT/apps/ios/Drillbit.xcodeproj" -scheme Drillbit \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=YES -quiet
xcrun simctl terminate "$SIMULATOR_ID" dawi.drillbit >/dev/null 2>&1 || true
xcrun simctl install "$SIMULATOR_ID" "$APP"
LAUNCH=$(xcrun simctl launch "$SIMULATOR_ID" dawi.drillbit)
PID=${LAUNCH##*: }
sleep 5
if ! ps -p "$PID" -o comm= | grep -q '/Drillbit$'; then
  echo "Drillbit exited during normal startup (PID $PID). Check the simulator crash report." >&2
  exit 1
fi
echo "Drillbit launched normally on $SIMULATOR_ID (PID $PID)."
