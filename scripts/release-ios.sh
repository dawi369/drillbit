#!/bin/bash
# Archives the App Store build, proves it points at production, then exports it.
#
#   scripts/release-ios.sh            archive + verify only
#   scripts/release-ios.sh --upload   archive + verify + upload to App Store Connect
#
# Bump CURRENT_PROJECT_VERSION in apps/ios/project.yml before each upload; App Store Connect rejects a reused build.
# Over SSH, unlock the keychain in the same shell first: security unlock-keychain ~/Library/Keychains/login.keychain-db
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
upload=false
[ "${1:-}" = "--upload" ] && upload=true

build=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/[^0-9]/, "", $2); print $2; exit}' "$root/apps/ios/project.yml")
version=$(awk '/MARKETING_VERSION:/ {gsub(/[^0-9.]/, "", $2); print $2; exit}' "$root/apps/ios/project.yml")
out="/tmp/drillbit-appstore/$version-$build"
archive="$out/Drillbit.xcarchive"
mkdir -p "$out"

[ -z "$(git -C "$root" status --porcelain)" ] || echo "warning: uncommitted changes go into this build" >&2

xcodegen generate --spec "$root/apps/ios/project.yml" >/dev/null
echo "Archiving $version ($build)…"
xcodebuild -project "$root/apps/ios/Drillbit.xcodeproj" -scheme Drillbit -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates archive \
  > "$out/archive.log" 2>&1 || { tail -30 "$out/archive.log"; echo "Archive failed; full log: $out/archive.log" >&2; exit 1; }

plist="$archive/Products/Applications/Drillbit.app/Info.plist"
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }
api=$(read_key APIBaseURL); clerk=$(read_key ClerkPublishableKey); privacy=$(read_key PrivacyPolicyURL)
providers=$(read_key SignInProviders); shipped="$(read_key CFBundleShortVersionString) ($(read_key CFBundleVersion))"
echo "  version   $shipped"
echo "  api       $api"
echo "  clerk     ${clerk:0:12}…"
echo "  privacy   $privacy"
echo "  sign-in   $providers"
fail=false
[ "$api" = "https://api.drillbit.t23.dev" ] || { echo "error: APIBaseURL isn't production" >&2; fail=true; }
[[ "$clerk" == pk_live_* ]] || { echo "error: Clerk key isn't a pk_live_ key" >&2; fail=true; }
[[ "$privacy" == https://* ]] || { echo "error: no privacy policy URL" >&2; fail=true; }
$fail && exit 1
echo "Archive verified: $archive"

if $upload; then
  echo "Exporting and uploading to App Store Connect…"
  "$root/scripts/export-ios-testflight.sh" "$archive" "$root/scripts/ExportOptions-AppStore.plist" "$out/export"
  echo "Uploaded $shipped. It appears in App Store Connect → TestFlight once Apple finishes processing."
else
  echo "Not uploaded. Re-run with --upload when ready."
fi
