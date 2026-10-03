#!/bin/sh
set -eu

cd "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

xcodebuild -project Orzen.xcodeproj -scheme Orzen \
  -destination 'platform=macOS' -derivedDataPath /tmp/orzen-tests-derived \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -workspace Orzen.xcworkspace -scheme OrzenPlayerUITests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/orzen-ios-tests-derived CODE_SIGNING_ALLOWED=NO test
