#!/bin/bash
# Unit test for xcproj-package.py. Needs only python3 — no Xcode.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../xcproj-package.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PROJ="$TMP/Fixture.xcodeproj"
mkdir -p "$PROJ"
# JSON5-style fixture as Xcode writes it: trailing commas everywhere, plus a
# script body containing ",]" and ",}" inside a string to prove the
# trailing-comma stripper is string-aware.
cat > "$PROJ/project.xcproj" <<'JSON'
{
  "default-configuration": "Release",
  "configurations": [
    "Debug",
    "Release",
  ],
  "localizations": { "development": "en", "supported": [ "Base", ], },
  "files": [
    { "kind": "folder", "path": "App", "target-membership": [ "App", ] },
  ],
  "targets": [
    {
      "name": "App",
      "id": "A000000000000000000000A1",
      "product-type": "application",
      "build-phases": [
        "compile-sources",
        "frameworks",
        { "kind": "script", "name": "Lint", "script": "echo 'x,]' && echo \"y,}\"", },
      ],
      "build-settings": { "PRODUCT_NAME": "$(TARGET_NAME)", },
    },
    {
      "name": "NoFrameworks",
      "id": "A000000000000000000000A2",
      "product-type": "tool",
      "build-phases": [ "compile-sources", ],
    },
  ],
}
JSON

fail() { echo "FAIL: $*" >&2; exit 1; }

out="$("$SCRIPT" list "$PROJ")"
[ "$out" = "No Swift packages." ] || fail "expected no packages, got: $out"

"$SCRIPT" add "$PROJ" --url https://github.com/apple/swift-collections.git --requirement from:1.1.0 --target App --product Collections --product DequeModule >/dev/null
"$SCRIPT" add "$PROJ" --path ../LocalKit --target App >/dev/null

python3 - "$PROJ/project.xcproj" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
pk = doc["packages"]
assert pk[0] == {"kind": "remote", "repository": "https://github.com/apple/swift-collections.git",
                 "version": {"up-to-next-major-version": "1.1.0"}}, pk[0]
assert pk[1] == {"kind": "local", "path": "../LocalKit"}, pk[1]
members = doc["targets"][0]["package-product-members"]
assert [m["product-name"] for m in members] == ["Collections", "DequeModule", "LocalKit"], members
assert all(m["build-phase"] == {"build-phase": "frameworks"} for m in members)
assert members[0]["package"] == "swift-collections"
# the script body survived trailing-comma stripping untouched
assert doc["targets"][0]["build-phases"][2]["script"] == "echo 'x,]' && echo \"y,}\""
PY

out="$("$SCRIPT" list "$PROJ")"
echo "$out" | grep -q "swift-collections .*up-to-next-major-version 1.1.0" || fail "list output: $out"
echo "$out" | grep -q -- "-> App: DequeModule (frameworks)" || fail "list output: $out"
echo "$out" | grep -q "📁 LocalKit  ../LocalKit" || fail "list output: $out"

# Adding the same package twice must not duplicate it.
"$SCRIPT" add "$PROJ" --url https://github.com/apple/swift-collections.git --requirement from:1.1.0 --target App --product Collections >/dev/null
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d["packages"])==2; assert len(d["targets"][0]["package-product-members"])==3' "$PROJ/project.xcproj"

# A target without a frameworks phase is rejected.
if "$SCRIPT" add "$PROJ" --url https://example.com/x --requirement exact:1.0.0 --target NoFrameworks >/dev/null 2>&1; then
  fail "expected rejection for a target without a frameworks phase"
fi

# Requirement spellings.
for pair in "exact:2.0.0=version" "upToNextMinor:2.0.0=up-to-next-minor-version" "branch:main=branch" "revision:abc=revision" "range:1.0.0..<2.0.0=version-range" "3.0.0=up-to-next-major-version"; do
  req="${pair%%=*}"; key="${pair#*=}"
  "$SCRIPT" add "$PROJ" --url "https://example.com/$key" --requirement "$req" >/dev/null
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=[p for p in d["packages"] if p.get("repository")==sys.argv[2]][0]; assert sys.argv[3] in p["version"], p' "$PROJ/project.xcproj" "https://example.com/$key" "$key"
done

"$SCRIPT" remove "$PROJ" --package-name swift-collections >/dev/null
"$SCRIPT" remove "$PROJ" --path ../LocalKit >/dev/null
python3 - "$PROJ/project.xcproj" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert not any(p.get("kind") == "local" for p in doc["packages"])
assert not any("swift-collections" in p.get("repository", "") for p in doc["packages"])
assert "package-product-members" not in doc["targets"][0], doc["targets"][0]
PY

if "$SCRIPT" remove "$PROJ" --package-name nope >/dev/null 2>&1; then fail "expected failure removing unknown package"; fi

mkdir -p "$TMP/Legacy.xcodeproj" && touch "$TMP/Legacy.xcodeproj/project.pbxproj"
if "$SCRIPT" list "$TMP/Legacy.xcodeproj" >/dev/null 2>&1; then fail "expected pbxproj rejection"; fi

echo "test-xcproj-package.sh: OK"
