#!/bin/sh
# Runs the AuditScreenshots UI tests and exports every attached screenshot as a PNG.
#
#   sh scripts/audit-shots.sh <output-dir> [test-name ...]
#
# With no test names every test in AuditScreenshots runs. Each name is passed as
# -only-testing:DrillbitUITests/AuditScreenshots/<name>. Reuses the signed build's
# derived data if present, otherwise /tmp/drillbit-audit-derived. Needs exactly one
# booted iOS 26+ iPhone simulator, or DRILLBIT_SIMULATOR_ID.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:?Pass the output directory for PNGs}
shift || true
mkdir -p "$OUT"

SIMULATOR_ID=${DRILLBIT_SIMULATOR_ID:-$(xcrun simctl list devices booted --json | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group]
booted = [d["udid"] for d in devices if d["state"] == "Booted"]
if len(booted) != 1:
    raise SystemExit("Boot exactly one iOS simulator, or set DRILLBIT_SIMULATOR_ID.")
print(booted[0])')}

DERIVED=${DRILLBIT_AUDIT_DERIVED_DATA:-/tmp/drillbit-audit-derived}
RESULT=$(mktemp -d)/audit.xcresult
ONLY=""
for name in "$@"; do ONLY="$ONLY -only-testing:DrillbitUITests/AuditScreenshots/$name"; done
[ -n "$ONLY" ] || ONLY="-only-testing:DrillbitUITests/AuditScreenshots"

# shellcheck disable=SC2086
xcodebuild test -project "$ROOT/apps/ios/Drillbit.xcodeproj" -scheme Drillbit \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -configuration Debug \
  -derivedDataPath "$DERIVED" -resultBundlePath "$RESULT" CODE_SIGNING_ALLOWED=NO \
  $ONLY -quiet || echo "Some audit tests failed; exporting what was captured." >&2

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$OUT" >/dev/null
# xcresulttool names files by UUID and lists the original names in manifest.json.
python3 - "$OUT" <<'PY'
import json, os, sys
out = sys.argv[1]
manifest = os.path.join(out, "manifest.json")
if not os.path.exists(manifest):
    raise SystemExit("No attachments were exported.")
seen = {}
for test in json.load(open(manifest)):
    for item in test.get("attachments", []):
        name = item.get("suggestedHumanReadableName") or item["exportedFileName"]
        base, ext = os.path.splitext(name)
        if not ext:
            ext = os.path.splitext(item["exportedFileName"])[1]
        # Repeated names (a test re-run, or the same frame twice) get a counter.
        count = seen.get(base, 0)
        seen[base] = count + 1
        target = f"{base}{'' if count == 0 else f'-{count}'}{ext}"
        os.replace(os.path.join(out, item["exportedFileName"]), os.path.join(out, target))
os.remove(manifest)
print(f"Exported {sum(seen.values())} screenshots to {out}")
PY
