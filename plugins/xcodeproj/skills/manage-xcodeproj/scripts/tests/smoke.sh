#!/bin/bash
# End-to-end smoke test. Requires Xcode 27.2+ (xcrun xcodeproj) and builds a
# generated project with xcodebuild, so it only runs on macOS.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

xcrun --find xcodeproj >/dev/null || fail "xcrun xcodeproj not found — Xcode 27.2+ required"

cd "$TMP"
"$SCRIPTS/new-xcodeproj.sh" --name SmokeApp --platforms macosx --deployment-target 15.0 >/dev/null
"$SCRIPTS/new-xcodeproj.sh" --name SmokeTool --product-type tool --platforms macosx --deployment-target 15.0 >/dev/null
export XCODEPROJ_PROJECT=SmokeApp.xcodeproj

# Targets, phases, settings, groups, files.
xcrun xcodeproj target add Core --product-type framework >/dev/null
xcrun xcodeproj target phase add --target Core sources >/dev/null
xcrun xcodeproj target phase add --target Core frameworks >/dev/null
for kv in SWIFT_VERSION=5.0 SDKROOT=macosx MACOSX_DEPLOYMENT_TARGET=15.0 CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER=com.example.Core SKIP_INSTALL=YES; do
  xcrun xcodeproj setting set "${kv%%=*}" "${kv#*=}" --target Core >/dev/null
done
mkdir -p Core && printf 'public enum Core { public static let value = 1 }\n' > Core/Core.swift
xcrun xcodeproj group add Core --filesystem-path Core >/dev/null
xcrun xcodeproj group include --group Core --target Core >/dev/null
xcrun xcodeproj target add-dependency SmokeApp Core >/dev/null
xcrun xcodeproj target phase add-copy --target SmokeApp --destination frameworks --name "Embed Frameworks" >/dev/null
xcrun xcodeproj group include Core.framework --group Products --target SmokeApp --phase 2 >/dev/null
xcrun xcodeproj group include Core.framework --group Products --target SmokeApp --phase 4 >/dev/null
# shellcheck disable=SC2016  # $(DERIVED_FILE_DIR) is meant for xcodebuild, not the shell
xcrun xcodeproj target phase add-script --target SmokeApp --name Lint --script 'echo lint' --output '$(DERIVED_FILE_DIR)/lint.txt' >/dev/null
xcrun xcodeproj setting set-multi OTHER_SWIFT_FLAGS --target SmokeApp -- -DSMOKE >/dev/null
xcrun xcodeproj group add Extras >/dev/null
mkdir -p Extras && printf 'enum Extra {}\n' > Extras/Extra.swift
xcrun xcodeproj group add-file Extra.swift --group Extras >/dev/null
xcrun xcodeproj group include Extra.swift --group Extras --target SmokeApp --phase 1 >/dev/null

xcrun xcodeproj target info --target SmokeApp | grep -q "Dependencies: Core (framework)" || fail "dependency missing"
xcrun xcodeproj target phase info --target SmokeApp 1 | grep -q "Extra.swift" || fail "Extra.swift not in sources"
xcrun xcodeproj target phase info --target SmokeApp 4 | grep -q "Core.framework" || fail "Core.framework not embedded"

# duplicate-target.sh replays phases, dependencies and settings.
"$SCRIPTS/duplicate-target.sh" SmokeApp SmokeApp2 --bundle-id com.example.SmokeApp2 >/dev/null
xcrun xcodeproj target info --target SmokeApp2 | grep -q "Dependencies: Core (framework)" || fail "duplicate lost dependency"
xcrun xcodeproj target phase info --target SmokeApp2 5 | grep -q "echo lint" || fail "duplicate lost script"
xcrun xcodeproj setting get PRODUCT_BUNDLE_IDENTIFIER --target SmokeApp2 --config Debug | grep -q "com.example.SmokeApp2" || fail "duplicate bundle id"
xcrun xcodeproj setting get OTHER_SWIFT_FLAGS --target SmokeApp2 --config Debug | grep -q -- "'-DSMOKE'" || fail "duplicate multi-value setting"
xcrun xcodeproj target remove SmokeApp2 >/dev/null

# xcproj-package.py on a real project, then a real build.
"$SCRIPTS/xcproj-package.py" add SmokeTool.xcodeproj --url https://github.com/apple/swift-argument-parser --requirement from:1.5.0 --target SmokeTool --product ArgumentParser >/dev/null
printf 'import ArgumentParser\n\n@main struct Tool: ParsableCommand {\n  func run() { print("hi") }\n}\n' > SmokeTool/Tool.swift && rm -f SmokeTool/main.swift
XCODEPROJ_PROJECT=SmokeTool.xcodeproj xcrun xcodeproj target phase info --target SmokeTool 2 | grep -q ArgumentParser || fail "package product not linked"

xcodebuild -project SmokeApp.xcodeproj -scheme SmokeApp -destination 'generic/platform=macOS' -quiet build CODE_SIGNING_ALLOWED=NO
xcodebuild -project SmokeTool.xcodeproj -scheme SmokeTool -destination 'generic/platform=macOS' -quiet build CODE_SIGNING_ALLOWED=NO

echo "smoke.sh: OK"
