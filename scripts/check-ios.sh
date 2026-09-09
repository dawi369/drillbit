#!/bin/sh
set -eu
xcodegen generate --spec apps/ios/project.yml
swift test --package-path apps/ios -j 2
xcodebuild -project apps/ios/Drillbit.xcodeproj -scheme Drillbit \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  -derivedDataPath /tmp/drillbit-ci-derived -jobs 2 CODE_SIGNING_ALLOWED=NO build
DRILLBIT_SIMULATOR_ID=$(xcrun simctl list devices available --json | python3 -c '
import json,sys,re
for runtime, devices in json.load(sys.stdin)["devices"].items():
    version=re.search(r"iOS-(\d+)",runtime)
    if version and int(version.group(1))>=26:
        for device in devices:
            if device["name"].startswith("iPhone"):
                print(device["udid"]);sys.exit(0)
raise SystemExit("Install an iOS 26+ iPhone simulator before native tests.")')
xcodebuild -project apps/ios/Drillbit.xcodeproj -scheme Drillbit \
  -destination "platform=iOS Simulator,id=$DRILLBIT_SIMULATOR_ID" -configuration Debug \
  -derivedDataPath /tmp/drillbit-ci-derived -jobs 2 CODE_SIGNING_ALLOWED=NO test
