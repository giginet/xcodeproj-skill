#!/bin/bash
# Duplicate a target with xcrun xcodeproj: product type, build phases (kinds,
# script bodies, copy destinations), dependencies and every raw build setting
# per configuration. File memberships are NOT copied (xcodeproj cannot list a
# file's group from a phase), so re-add them with 'group include' afterwards.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: duplicate-target.sh <source-target> <new-target> [-P <project.xcodeproj>] [--bundle-id <id>]

  -P, --project  Path to .xcodeproj (default: XCODEPROJ_PROJECT or auto-discovery)
  --bundle-id    PRODUCT_BUNDLE_IDENTIFIER for the new target (default: copied from source)
USAGE
}

SRC=""; DST=""; PROJECT="${XCODEPROJ_PROJECT:-}"; BUNDLE_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    -P|--project) PROJECT="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "error: unknown option '$1'" >&2; usage >&2; exit 64 ;;
    *) if [ -z "$SRC" ]; then SRC="$1"; elif [ -z "$DST" ]; then DST="$1"; else echo "error: too many arguments" >&2; exit 64; fi; shift ;;
  esac
done
if [ -z "$SRC" ] || [ -z "$DST" ]; then usage >&2; exit 64; fi

# Every xcodeproj subcommand honours XCODEPROJ_PROJECT, which avoids having to
# place -P after the subcommand (and before any '--') on each call.
if [ -n "$PROJECT" ]; then export XCODEPROJ_PROJECT="$PROJECT"; fi
XP=(xcrun xcodeproj)

# 1. Product type and kind from 'target list' (columns: Name Kind ProductType).
LINE="$("${XP[@]}" target list | awk -v t="$SRC" '$1 == t { print; exit }')"
[ -n "$LINE" ] || { echo "error: no target named '$SRC'" >&2; exit 1; }
KIND="$(printf '%s\n' "$LINE" | awk '{ print $2 }')"
PRODUCT_TYPE="$(printf '%s\n' "$LINE" | awk '{ print $3 }')"

if [ "$KIND" = "aggregate" ]; then
  "${XP[@]}" target add-aggregate "$DST"
else
  "${XP[@]}" target add "$DST" --product-type "com.apple.product-type.$PRODUCT_TYPE"
fi

# 2. Build phases: replay each phase by index, in order.
INFO="$("${XP[@]}" target info --target "$SRC")"
PHASE_COUNT="$(printf '%s\n' "$INFO" | awk '/^#[[:space:]]+Kind/ { p = 1; next } p && /^[0-9]+/ { n = $1 } END { print n + 0 }')"
i=1
while [ "$i" -le "$PHASE_COUNT" ]; do
  PINFO="$("${XP[@]}" target phase info --target "$SRC" "$i")"
  PKIND="$(printf '%s\n' "$PINFO" | awk '/^Kind:/ { print $2; exit }')"
  PNAME="$(printf '%s\n' "$PINFO" | sed -n 's/^Name:  *//p' | head -1)"
  case "$PKIND" in
    sources|resources|frameworks|headers)
      "${XP[@]}" target phase add --target "$DST" "$PKIND" ;;
    script)
      SHELL_PATH="$(printf '%s\n' "$PINFO" | sed -n 's/^Shell: *//p' | head -1)"
      # Script body: everything after the "Script:" line, with the 2-space indent removed.
      SCRIPT_BODY="$(printf '%s\n' "$PINFO" | awk '/^Script:/ { p = 1; next } p' | sed 's/^  //')"
      ARGS=(--target "$DST" --name "$PNAME" --script "$SCRIPT_BODY")
      [ -n "$SHELL_PATH" ] && ARGS+=(--shell "$SHELL_PATH")
      while IFS= read -r f; do [ -n "$f" ] && ARGS+=(--input "$f"); done < <(printf '%s\n' "$PINFO" | awk '/^Input Files:/ { p = 1; next } /^[A-Z]/ { p = 0 } p && !/\(none\)/ { sub(/^  /, ""); print }')
      while IFS= read -r f; do [ -n "$f" ] && ARGS+=(--output "$f"); done < <(printf '%s\n' "$PINFO" | awk '/^Output Files:/ { p = 1; next } /^[A-Z]/ { p = 0 } p && !/\(none\)/ { sub(/^  /, ""); print }')
      while IFS= read -r f; do [ -n "$f" ] && ARGS+=(--input-file-list "$f"); done < <(printf '%s\n' "$PINFO" | awk '/^Input File Lists:/ { p = 1; next } /^[A-Z]/ { p = 0 } p && !/\(none\)/ { sub(/^  /, ""); print }')
      while IFS= read -r f; do [ -n "$f" ] && ARGS+=(--output-file-list "$f"); done < <(printf '%s\n' "$PINFO" | awk '/^Output File Lists:/ { p = 1; next } /^[A-Z]/ { p = 0 } p && !/\(none\)/ { sub(/^  /, ""); print }')
      if printf '%s\n' "$PINFO" | grep -q '^Run only when installing: true'; then ARGS+=(--run-only-when-installing); fi
      "${XP[@]}" target phase add-script "${ARGS[@]}" ;;
    copy)
      DEST="$(printf '%s\n' "$PINFO" | sed -n 's/^Destination: *//p' | head -1)"
      "${XP[@]}" target phase add-copy --target "$DST" --destination "$DEST" --name "$PNAME" ;;
    *)
      echo "warning: phase $i has unknown kind '$PKIND'; skipped" >&2 ;;
  esac
  i=$((i + 1))
done

# 3. Dependencies: "Dependencies: A (framework), B (application)" or "(none)".
DEPS="$(printf '%s\n' "$INFO" | sed -n 's/^Dependencies: *//p' | head -1)"
if [ "$DEPS" != "(none)" ] && [ -n "$DEPS" ]; then
  printf '%s\n' "$DEPS" | tr ',' '\n' | sed 's/ *(.*)//; s/^ *//; s/ *$//' | while IFS= read -r dep; do
    [ -n "$dep" ] && "${XP[@]}" target add-dependency "$DST" "$dep"
  done
fi

# 4. Build settings, per configuration. 'setting list' prints
#      [Debug]
#        KEY = 'v1' 'v2'
#    with shell-single-quoted values, so the value list can be re-parsed with eval.
CONFIG=""
while IFS= read -r line; do
  case "$line" in
    "  ["*"]")
      CONFIG="${line#  [}"; CONFIG="${CONFIG%]}" ;;
    "    "*" = "*)
      [ -n "$CONFIG" ] || continue
      kv="${line#    }"
      key="${kv%% = *}"
      rest="${kv#* = }"
      eval "vals=($rest)"
      if [ "$key" = "PRODUCT_BUNDLE_IDENTIFIER" ] && [ -n "$BUNDLE_ID" ]; then
        vals=("$BUNDLE_ID")
      fi
      if [ "${#vals[@]}" -eq 1 ]; then
        "${XP[@]}" setting set "$key" --target "$DST" --config "$CONFIG" -- "${vals[0]}" >/dev/null
      else
        "${XP[@]}" setting set-multi "$key" --target "$DST" --config "$CONFIG" -- "${vals[@]}" >/dev/null
      fi ;;
  esac
done < <("${XP[@]}" setting list --target "$SRC")

echo "Duplicated '$SRC' as '$DST' (product type, phases, dependencies, build settings)."
echo "File memberships were not copied: run 'group include ... --target $DST' for each file or synchronized folder."
"${XP[@]}" target info --target "$DST"
