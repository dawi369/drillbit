#!/bin/bash
set -euo pipefail
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 ARCHIVE EXPORT_OPTIONS_PLIST EXPORT_DIRECTORY" >&2
  exit 2
fi
script_dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$script_dir/prepare-ios-symbols.py" "$1"
xcodebuild -exportArchive -archivePath "$1" -exportOptionsPlist "$2" -exportPath "$3" -allowProvisioningUpdates
