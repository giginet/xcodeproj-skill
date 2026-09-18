#!/bin/bash
# Create a minimal Xcode project in the JSON project.xcproj format (Xcode 27.2+).
#
# xcrun xcodeproj has no "create project" command, but project.xcproj is plain
# JSON, so this script writes the smallest document Xcode and xcodeproj accept:
# one native target backed by a filesystem-synchronized folder, plus the
# Products group and product reference that every native target must have.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: new-xcodeproj.sh --name <Name> [--output-dir <dir>] [--product-type <type>]
                        [--bundle-id-prefix <com.example>] [--platforms "<sdk sdk ...>"]
                        [--swift-version <ver>] [--deployment-target <ver>] [--force]

Writes <dir>/<Name>.xcodeproj/project.xcproj and a <dir>/<Name>/ source folder.

  --product-type   application (default), framework, tool, library.static,
                   library.dynamic, bundle, unit-test-bundle, ui-test-bundle,
                   app-extension, extensionkit-extension
  --platforms      SUPPORTED_PLATFORMS value (default: "iphoneos iphonesimulator macosx")
  --swift-version  SWIFT_VERSION (default: 5.0)
  --deployment-target  Applied to every *_DEPLOYMENT_TARGET for the listed platforms
                   (default: 26.0)
  --force          Overwrite an existing .xcodeproj
USAGE
}

NAME=""
OUTPUT_DIR="."
PRODUCT_TYPE="application"
BUNDLE_PREFIX="com.example"
PLATFORMS="iphoneos iphonesimulator macosx"
SWIFT_VERSION="5.0"
DEPLOYMENT_TARGET="26.0"
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --product-type) PRODUCT_TYPE="$2"; shift 2 ;;
    --bundle-id-prefix) BUNDLE_PREFIX="$2"; shift 2 ;;
    --platforms) PLATFORMS="$2"; shift 2 ;;
    --swift-version) SWIFT_VERSION="$2"; shift 2 ;;
    --deployment-target) DEPLOYMENT_TARGET="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 64 ;;
  esac
done

[ -n "$NAME" ] || { echo "error: --name is required" >&2; usage >&2; exit 64; }
case "$NAME" in *[!A-Za-z0-9_]*) echo "error: --name must be alphanumeric/underscore" >&2; exit 64 ;; esac

# Product file name + Xcode file type + extra settings per product type.
case "$PRODUCT_TYPE" in
  application)            PRODUCT_FILE="$NAME.app";       FILE_TYPE="wrapper.application";             GEN_PLIST=YES ;;
  framework)              PRODUCT_FILE="$NAME.framework"; FILE_TYPE="wrapper.framework";               GEN_PLIST=YES ;;
  tool)                   PRODUCT_FILE="$NAME";           FILE_TYPE="compiled.mach-o.executable";      GEN_PLIST=NO ;;
  library.static)         PRODUCT_FILE="lib$NAME.a";      FILE_TYPE="archive.ar";                      GEN_PLIST=NO ;;
  library.dynamic)        PRODUCT_FILE="lib$NAME.dylib";  FILE_TYPE="compiled.mach-o.dylib";           GEN_PLIST=NO ;;
  bundle)                 PRODUCT_FILE="$NAME.bundle";    FILE_TYPE="wrapper.cfbundle";                GEN_PLIST=YES ;;
  unit-test-bundle|ui-test-bundle) PRODUCT_FILE="$NAME.xctest"; FILE_TYPE="wrapper.cfbundle";          GEN_PLIST=YES ;;
  app-extension)          PRODUCT_FILE="$NAME.appex";     FILE_TYPE="wrapper.app-extension";           GEN_PLIST=YES ;;
  extensionkit-extension) PRODUCT_FILE="$NAME.appex";     FILE_TYPE="wrapper.extensionkit-extension";  GEN_PLIST=YES ;;
  *) echo "error: unsupported --product-type '$PRODUCT_TYPE'" >&2; exit 64 ;;
esac

PROJECT_DIR="$OUTPUT_DIR/$NAME.xcodeproj"
SOURCE_DIR="$OUTPUT_DIR/$NAME"
if [ -e "$PROJECT_DIR" ] && [ "$FORCE" -ne 1 ]; then
  echo "error: $PROJECT_DIR already exists (use --force to overwrite)" >&2
  exit 1
fi

# Xcode object IDs are 24 uppercase hex characters.
gen_id() { uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24; }
TARGET_ID="$(gen_id)"
PRODUCT_ID="$(gen_id)"

# Deployment-target settings for each listed platform.
DEPLOY_SETTINGS=""
for sdk in $PLATFORMS; do
  case "$sdk" in
    iphoneos|iphonesimulator) key=IPHONEOS_DEPLOYMENT_TARGET ;;
    macosx)                   key=MACOSX_DEPLOYMENT_TARGET ;;
    appletvos|appletvsimulator) key=TVOS_DEPLOYMENT_TARGET ;;
    watchos|watchsimulator)   key=WATCHOS_DEPLOYMENT_TARGET ;;
    xros|xrsimulator)         key=XROS_DEPLOYMENT_TARGET ;;
    *) key="" ;;
  esac
  [ -n "$key" ] || continue
  case "$DEPLOY_SETTINGS" in *"\"$key\""*) continue ;; esac
  DEPLOY_SETTINGS="$DEPLOY_SETTINGS        \"$key\": \"$DEPLOYMENT_TARGET\",
"
done

mkdir -p "$PROJECT_DIR" "$SOURCE_DIR"

cat > "$PROJECT_DIR/project.xcproj" <<JSON
{
  "default-configuration": "Release",
  "configurations": ["Debug", "Release"],
  "localizations": { "development": "en", "supported": ["Base"] },
  "files": [
    { "kind": "folder", "path": "$NAME", "target-membership": ["$NAME"] },
    {
      "kind": "group",
      "name": "Products",
      "children": [
        { "path": "<PRODUCTS>/$PRODUCT_FILE", "id": "$PRODUCT_ID", "type": "$FILE_TYPE", "index": false }
      ]
    }
  ],
  "targets": [
    {
      "name": "$NAME",
      "id": "$TARGET_ID",
      "product": "Products/$PRODUCT_FILE",
      "product-type": "$PRODUCT_TYPE",
      "build-phases": ["compile-sources", "frameworks", "resources"],
      "build-settings": {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "$GEN_PLIST",
$DEPLOY_SETTINGS        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "$BUNDLE_PREFIX.$NAME",
        "PRODUCT_NAME": "\$(TARGET_NAME)",
        "SDKROOT": "auto",
        "SUPPORTED_PLATFORMS": "$PLATFORMS",
        "SWIFT_VERSION": "$SWIFT_VERSION",
        "TARGETED_DEVICE_FAMILY": "1,2"
      }
    }
  ],
  "build-settings": {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT[config=Debug]": "dwarf",
    "DEBUG_INFORMATION_FORMAT[config=Release]": "dwarf-with-dsym",
    "ENABLE_NS_ASSERTIONS[config=Release]": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_TESTABILITY[config=Debug]": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_NO_COMMON_BLOCKS": "YES",
    "GCC_OPTIMIZATION_LEVEL[config=Debug]": "0",
    "GCC_PREPROCESSOR_DEFINITIONS[config=Debug]": "DEBUG=1 \$(inherited)",
    "ONLY_ACTIVE_ARCH[config=Debug]": "YES",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS[config=Debug]": "DEBUG \$(inherited)",
    "SWIFT_COMPILATION_MODE[config=Release]": "wholemodule",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_OPTIMIZATION_LEVEL[config=Debug]": "-Onone",
    "SWIFT_OPTIMIZATION_LEVEL[config=Release]": "-O"
  }
}
JSON

# Starter source so the target compiles out of the box.
if [ ! -e "$SOURCE_DIR/$NAME.swift" ] && [ -z "$(ls -A "$SOURCE_DIR")" ]; then
  case "$PRODUCT_TYPE" in
    application)
      cat > "$SOURCE_DIR/${NAME}App.swift" <<SWIFT
import SwiftUI

@main
struct ${NAME}App: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello, $NAME!")
        }
    }
}
SWIFT
      ;;
    tool)
      printf 'import Foundation\n\nprint("Hello, %s!")\n' "$NAME" > "$SOURCE_DIR/main.swift"
      ;;
    *)
      printf 'import Foundation\n\npublic enum %s {}\n' "$NAME" > "$SOURCE_DIR/$NAME.swift"
      ;;
  esac
fi

# Validate: xcodeproj refuses to open a malformed document.
if xcrun xcodeproj target list -P "$PROJECT_DIR" >/dev/null; then
  echo "Created $PROJECT_DIR (target '$NAME', product type $PRODUCT_TYPE)"
  echo "Sources: $SOURCE_DIR (filesystem-synchronized folder)"
else
  echo "error: xcrun xcodeproj could not open the generated project" >&2
  exit 1
fi
