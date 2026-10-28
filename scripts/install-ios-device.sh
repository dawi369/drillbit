#!/bin/bash
# Builds the production (Release) app, signs it for development and installs it on a connected iPhone.
#
#   scripts/install-ios-device.sh [device-udid]
#
# Without a UDID it picks the first paired physical iPhone. Run it from your own Terminal: SSH and agent shells
# can't reach the signing key in the login keychain (codesign fails with errSecInternalComponent).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
device="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /available/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) {print $i; exit}}')}"
[ -n "$device" ] || { echo "No paired iPhone found. Connect it, unlock it and trust this Mac." >&2; exit 1; }
derived=/tmp/drillbit-device
log=/tmp/drillbit-device.log

xcodegen generate --spec "$root/apps/ios/project.yml" >/dev/null
echo "Building Release for $device…"
xcodebuild -project "$root/apps/ios/Drillbit.xcodeproj" -scheme Drillbit -configuration Release \
  -destination "id=$device" -derivedDataPath "$derived" -allowProvisioningUpdates build >"$log" 2>&1 \
  || { grep -E "error:|errSec" "$log" | head; echo "Build failed; full log: $log" >&2; exit 1; }

app="$derived/Build/Products/Release-iphoneos/Drillbit.app"
echo "API: $(/usr/libexec/PlistBuddy -c 'Print :APIBaseURL' "$app/Info.plist")"
echo "Installing…"
xcrun devicectl device install app --device "$device" "$app" >/dev/null
xcrun devicectl device process launch --device "$device" dawi.drillbit >/dev/null 2>&1 \
  || echo "Installed. Unlock the phone and open Drillbit."
echo "Done."
