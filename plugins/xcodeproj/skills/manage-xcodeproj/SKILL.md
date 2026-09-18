---
name: manage-xcodeproj
description: Inspect and modify Xcode project files (.xcodeproj) from the command line with the `xcrun xcodeproj` CLI that ships in Xcode 27.2+. Use this whenever the user wants to list or change targets, build phases (run script, copy files), build settings, groups, file references, filesystem-synchronized folders, framework links, target dependencies, app extensions or Swift package dependencies in an Xcode project, to create a new .xcodeproj, or to duplicate a target — all without opening Xcode. Handles both the legacy `project.pbxproj` and the JSON `project.xcproj` format.
license: MIT
---

# Xcode projects with `xcrun xcodeproj`

Xcode 27.2 ships `xcodeproj`, a CLI for `.xcodeproj` bundles, invoked as
`xcrun xcodeproj <group> <command>`. It reads and writes both project formats
(`project.pbxproj` and the JSON `project.xcproj` introduced in Xcode 27.2) and
always preserves the format it finds. This skill is the CLI reference plus
recipes for the operations the CLI has no single command for — creating a
project, embedding extensions, duplicating a target, Swift packages — backed by
three helper scripts in this skill's `scripts/` directory.

## Preflight

```bash
xcodebuild -version                                   # Xcode 27.2 or newer
[ "$(xcrun --find xcodeproj)" = "$(xcode-select -p)/usr/bin/xcodeproj" ] && echo OK
```

The binary must be the one **inside the selected Xcode**: `xcrun --find` also
searches `PATH`, and the unrelated CocoaPods Ruby gem installs a `xcodeproj`
command there (its help starts with `Usage: xcodeproj ...` and it knows no
`setting`/`target`/`group` subcommands). If the check fails, stop and tell the
user that the selected Xcode (`xcode-select -p`) is older than 27.2; this skill
cannot proceed. Do not fall back to editing `project.pbxproj` by hand.

The helper scripts live in `scripts/` next to this file:

```bash
# Claude Code / Codex plugin install:
SCRIPTS="${CLAUDE_PLUGIN_ROOT}/skills/manage-xcodeproj/scripts"
# gh skill install: use the scripts/ directory next to this SKILL.md instead.
```

They need only bash and python3 (both present on macOS with Xcode).

## Ground rules

- **Addressing the project.** Every command takes `-P/--project <path>.xcodeproj`
  **after the subcommand words** (`xcrun xcodeproj target list -P App.xcodeproj`,
  never `xcrun xcodeproj -P ...`). Omit it to use `$XCODEPROJ_PROJECT`, else
  auto-discovery of the single `.xcodeproj` in the current directory (two or
  more → error). For a sequence of commands, `export XCODEPROJ_PROJECT=App.xcodeproj`.
- **Discover before you act.** `target list` for target names, `target info --target T`
  for the numbered phase table, `group ls -R` for group paths. Build phases are
  addressed by a **live 1-based index** that shifts whenever phases are added,
  moved or removed — re-run `target info` before every phase-indexed command.
- **`--` ends option parsing.** Values that start with `-` (`-Onone`, `-lz`,
  `-DFOO`) must follow a bare `--`, and `--target/--config` must come **before**
  it: `setting set OTHER_LDFLAGS --target App -- -lz -lsqlite3`.
- **Raw values only.** `setting get/list` print the literal string stored in the
  project — no `$(inherited)` expansion, no xcconfig layering. Use
  `xcodebuild -showBuildSettings` for resolved values.
- **Text output, not JSON.** There is no `--json`. Parse the fixed layouts shown
  below. Exit codes: 0 success, 1 domain error (`Error: ...` on stderr),
  64 usage error.
- **Nothing is written on error.** All validation runs before the save, so a
  rejected command never leaves a half-edited project.
- **Never edit `project.pbxproj` by hand.** For `project.xcproj` (plain JSON),
  hand edits are acceptable for the few things the CLI cannot express (Swift
  packages — see `references/xcproj-format.md`); validate afterwards with any
  read command, because the CLI refuses to open a malformed document.

## Command reference

### `setting` — raw build settings (project or `--target <t>`; optional `--config <c>`)

| Command | Purpose |
|---|---|
| `setting list [--target T] [--config C]` | Every key/value, grouped as `  [Debug]` / `  [Release]` blocks with lines `    KEY = 'v1' 'v2'` (values shell-single-quoted; multi-valued lists are one line). |
| `setting get KEY [--target T] [--config C]` | One key, per configuration: `  Debug: '5.0'` or `(unset)`. Prints a note when values differ across configurations. |
| `setting set KEY VALUE [--target T] [--config C]` | Store a single string (all configurations unless `--config`). `''` is a valid value. |
| `setting set-multi KEY V1 V2 ... [--target T] [--config C]` | Store a list, replacing any previous value. |
| `setting unset KEY [--target T] [--config C]` | Remove the key so inheritance resumes. |

Conditional keys are ordinary strings: `setting set 'LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]' '@executable_path/../Frameworks' --target App`.
Discover configuration names from the `[..]` headers of `setting list`, or from the
`Available configurations:` line of a deliberately wrong `--config`.

### `target` — targets and build phases

| Command | Purpose |
|---|---|
| `target list` | Table `Name  Kind  Product Type` (`native`/`aggregate`; product type in short form such as `application`, `framework`, `bundle.unit-test`, `extensionkit-extension`). |
| `target info --target T` | `Name / Kind / Product Type / Dependencies: A (framework), B (...)` or `(none)`, then a phase table `#  Kind  Files`. |
| `target add NAME --product-type TYPE` | Blank native target: **no build phases**, only `PRODUCT_NAME=$(TARGET_NAME)` (and `GENERATE_INFOPLIST_FILE=YES` for application/framework/bundle/test bundles). Also creates the product reference under `Products`. |
| `target add-aggregate NAME` | Blank aggregate target. |
| `target add-dependency T DEP` / `target remove-dependency T DEP` | In-project dependency edge. Duplicate add / missing remove are errors. |
| `target remove T` | Refuses while another target depends on `T` (no `--force`); remove the dependencies first. Cleans the product reference and its copy-phase / link memberships. |
| `target phase info --target T N` | Kind-specific detail: files for sources/resources/frameworks/headers; `Shell`, `Input Files`, `Output Files`, `Run only when installing`, `Script:` body for script; `Destination:` plus files for copy. |
| `target phase add --target T KIND [--position N \| --before N \| --after N]` | KIND ∈ `sources`, `resources`, `frameworks`, `headers`. Appends by default. |
| `target phase add-script --target T --script 'body' \| @file [--name N] [--shell /bin/zsh] [--input P]* [--output P]* [--input-file-list P]* [--output-file-list P]* [--run-only-when-installing] [--no-echo-env-vars] [--position/--before/--after N]` | Run Script phase. `@path` reads the body from a file. |
| `target phase add-copy --target T --destination 'KEYWORD [subpath]' [--name N] [--position/--before/--after N]` | Copy Files phase. Keywords: `frameworks`, `plugins`, `extensions`, `resources`, `executables`, `shared-support`, `wrapper`, `xpc-services`, `system-extensions`, `app-clips`, `absolute-path <path>`, … (see `--help`). |
| `target phase remove --target T N` / `target phase move --target T N --to M` | `--to` is evaluated after the phase is lifted out. |

`--product-type` short names: `application`, `app-extension`, `framework`,
`library.dynamic`, `library.static`, `bundle`, `unit-test-bundle`,
`ui-test-bundle`, `tool`, `kernel-extension`, `instruments-package`,
`xcode-extension`, `driver-extension`. Everything else must be the **full
identifier** (`com.apple.product-type.extensionkit-extension`,
`com.apple.product-type.application.on-demand-install-capable`,
`com.apple.product-type.framework.static`, …). The CLI does not validate the
value: an unknown short name such as `staticFramework` is stored verbatim and
`xcodebuild` later fails with `unable to resolve product type`. **Do not use the
short names `watch-app` and `watch-extension`** — they expand to identifiers
Xcode does not have; use `com.apple.product-type.application.watchapp2` and
`com.apple.product-type.watchkit2-extension`. The complete list of the 42
identifiers Xcode 27.2 knows, with the product file each yields and whether
`target add` creates a `Products` reference for it, is in
`references/product-types.md`.

### `group` — the Project Navigator tree

Groups are addressed by a `/`-separated path (`/App/Sources/Utilities`), a bare
name when unique, or the object-ID printed by `group ls`.

| Command | Purpose |
|---|---|
| `group ls [PARENT] [-R]` | Children of a group (default root). Groups end in `/` with `(id: …)`; synchronized folders print `[filesystem-synchronized -> path]`; non-project-relative files print their anchor, e.g. `<SDKROOT>/System/Library/Frameworks/UIKit.framework`, `<BUILT_PRODUCTS_DIR>/App.app`. |
| `group add NAME [--parent P] [--filesystem-path DIR]` | Plain group, or with `--filesystem-path` a **filesystem-synchronized folder** (the directory must exist; relative paths resolve against the parent group's own directory). |
| `group add-file PATH --group G` | New file reference in a regular group only (navigator only — no target membership yet). PATH may start with `<SDKROOT>`, `<ABSOLUTE>`, `<BUILT_PRODUCTS_DIR>`, `<DEVELOPER_DIR>`, `<SRCROOT>`. |
| `group remove-file FILE --group G [--force]` | Refuses while the file is in any build phase unless `--force` (which also drops those memberships). |
| `group remove PATH [--force]` | Removes a group tree; same refusal rule. |
| `group include [FILE] --group G --target T [--phase N]` | Three forms: whole synchronized folder (`--group SYNC --target T`), one file from a regular group (`FILE --group G --target T --phase N`, `--phase` required), one file inside a synchronized folder (`FILE --group SYNC --target T`, phase chosen automatically). |
| `group exclude [FILE] --group G --target T [--phase N]` | Exact mirror of `include`. |

`FILE` is matched among the direct children of `--group` only.

## Recipes

Set `export XCODEPROJ_PROJECT=App.xcodeproj` first, or add `-P App.xcodeproj` to
each command.

### Inspect a project

```bash
xcrun xcodeproj target list
xcrun xcodeproj target info --target App              # dependencies + phase table
xcrun xcodeproj target phase info --target App 1      # files compiled by phase 1
xcrun xcodeproj group ls -R                           # whole navigator tree
xcrun xcodeproj setting list --target App --config Debug
xcrun xcodeproj setting get PRODUCT_BUNDLE_IDENTIFIER --target App
```

"Which files does target X build?" = `target info` then `target phase info` for
each sources/resources phase. Synchronized folders contribute their on-disk
contents (the CLI resolves them live, so `phase info` lists those files too).

### Add a source file to a target

Modern projects (Xcode 16+) keep sources in **filesystem-synchronized folders**
(`[filesystem-synchronized -> App]` in `group ls`). For those, just write the
file into the folder on disk — Xcode picks it up; nothing to add. To keep a file
out of (or put it back into) a target:

```bash
xcrun xcodeproj group exclude Legacy.swift --group App --target App
xcrun xcodeproj group include Legacy.swift --group App --target App
```

For a regular (non-synchronized) group, add the reference **and** the phase membership:

```bash
xcrun xcodeproj group add-file Helper.swift --group /App/Utilities        # path relative to the group's directory
xcrun xcodeproj target info --target App                                  # find the sources phase index (say 1)
xcrun xcodeproj group include Helper.swift --group /App/Utilities --target App --phase 1
```

Remove: `group remove-file Helper.swift --group /App/Utilities --force`.
**Move/rename has no command**: for a synchronized folder `mv` the file on disk;
for a regular group `remove-file --force`, move on disk, then `add-file` +
`include` again.

### Add a synchronized folder or a group

```bash
xcrun xcodeproj group add Generated --filesystem-path Generated            # dir must already exist
xcrun xcodeproj group include --group Generated --target App               # whole folder into the target
xcrun xcodeproj group add Utilities --parent /App                          # plain group
```

Nested synchronized folders are just subdirectories on disk — `group add` inside
one is rejected.

### Add a new target that actually builds

`target add` creates a bare shell. Always follow it with phases and the minimum
build settings; without `SWIFT_VERSION`/`SDKROOT` the build fails
(`SWIFT_VERSION '' is unsupported`).

```bash
xcrun xcodeproj target add Core --product-type framework
xcrun xcodeproj target phase add --target Core sources
xcrun xcodeproj target phase add --target Core frameworks
xcrun xcodeproj target phase add --target Core resources
mkdir -p Core && printf 'public enum Core {}\n' > Core/Core.swift
xcrun xcodeproj group add Core --filesystem-path Core
xcrun xcodeproj group include --group Core --target Core
for kv in SWIFT_VERSION=5.0 SDKROOT=auto "SUPPORTED_PLATFORMS=iphoneos iphonesimulator macosx" \
          PRODUCT_BUNDLE_IDENTIFIER=com.example.Core CODE_SIGN_STYLE=Automatic \
          IPHONEOS_DEPLOYMENT_TARGET=26.0 MACOSX_DEPLOYMENT_TARGET=26.0 TARGETED_DEVICE_FAMILY=1,2 \
          MARKETING_VERSION=1.0 CURRENT_PROJECT_VERSION=1 SKIP_INSTALL=YES; do
  xcrun xcodeproj setting set "${kv%%=*}" "${kv#*=}" --target Core
done
```

Copy platform/deployment settings from an existing target (`setting list --target App`)
so the new target matches the project. For a unit-test bundle also set
`TEST_HOST='$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App'`,
`BUNDLE_LOADER='$(TEST_HOST)'` and add a dependency on the app.

### Link and embed a framework

System framework — reference it under an anchor, then include it in the
`frameworks` phase:

```bash
xcrun xcodeproj group add Frameworks
xcrun xcodeproj group add-file '<SDKROOT>/System/Library/Frameworks/AVFoundation.framework' --group Frameworks
xcrun xcodeproj group include AVFoundation.framework --group Frameworks --target App --phase 2   # 2 = frameworks phase
```

In-project framework — depend on it, link it, and embed it through a copy phase
(the CLI writes `CodeSignOnCopy`/`RemoveHeadersOnCopy` automatically):

```bash
xcrun xcodeproj target add-dependency App Core
xcrun xcodeproj group include Core.framework --group Products --target App --phase 2           # link
xcrun xcodeproj target phase add-copy --target App --destination frameworks --name "Embed Frameworks"
xcrun xcodeproj target info --target App                                                       # new phase index, say 4
xcrun xcodeproj group include Core.framework --group Products --target App --phase 4           # embed
```

### Run Script and Copy Files phases

```bash
xcrun xcodeproj target phase add-script --target App --name SwiftLint \
    --script 'if which swiftlint >/dev/null; then swiftlint; fi' --before 1
xcrun xcodeproj target phase add-script --target App --name "Post Build" --script @Scripts/post.sh \
    --input '$(SRCROOT)/in.txt' --output '$(DERIVED_FILE_DIR)/out.txt' --no-echo-env-vars
xcrun xcodeproj target phase add-copy --target App --destination 'wrapper Extras' --name "Copy Extras"
xcrun xcodeproj target phase move --target App 5 --to 1
xcrun xcodeproj target phase remove --target App 6
```

Give script phases `--output` paths, or xcodebuild warns that the phase runs on every build.

### Add an app extension (widget example, verified end to end)

```bash
xcrun xcodeproj target add MyWidget --product-type com.apple.product-type.extensionkit-extension
for k in sources frameworks resources; do xcrun xcodeproj target phase add --target MyWidget $k; done
mkdir -p MyWidget && cp path/to/Widget.swift MyWidget/           # WidgetBundle + Widget sources
xcrun xcodeproj group add MyWidget --filesystem-path MyWidget
xcrun xcodeproj group include --group MyWidget --target MyWidget
for kv in SWIFT_VERSION=5.0 SDKROOT=auto "SUPPORTED_PLATFORMS=iphoneos iphonesimulator macosx" \
          PRODUCT_BUNDLE_IDENTIFIER=com.example.App.MyWidget CODE_SIGN_STYLE=Automatic \
          GENERATE_INFOPLIST_FILE=YES INFOPLIST_KEY_CFBundleDisplayName=MyWidget \
          INFOPLIST_KEY_EXExtensionPointIdentifier=com.apple.widgetkit-extension \
          IPHONEOS_DEPLOYMENT_TARGET=26.0 MACOSX_DEPLOYMENT_TARGET=26.0 TARGETED_DEVICE_FAMILY=1,2 \
          MARKETING_VERSION=1.0 CURRENT_PROJECT_VERSION=1 SKIP_INSTALL=YES SWIFT_EMIT_LOC_STRINGS=YES; do
  xcrun xcodeproj setting set "${kv%%=*}" "${kv#*=}" --target MyWidget
done
xcrun xcodeproj target add-dependency App MyWidget
xcrun xcodeproj target phase add-copy --target App --destination extensions --name "Embed ExtensionKit Extensions"
xcrun xcodeproj target info --target App                                   # note the new copy phase index
xcrun xcodeproj group include MyWidget.appex --group Products --target App --phase <index>
```

Classic (non-ExtensionKit) extensions use `--product-type app-extension`,
`INFOPLIST_KEY_NSExtensionPointIdentifier=<point>` and a copy phase with
`--destination plugins` (name it "Embed Foundation Extensions"). `GENERATE_INFOPLIST_FILE=YES`
is **not** defaulted for extension targets — set it, or the build fails with
`Couldn't load Info dictionary`.

Remove an extension: `target remove-dependency App MyWidget`, `target remove MyWidget`
(cleans the embed membership and product), then `group remove MyWidget` for its folder.

### Duplicate a target

```bash
"$SCRIPTS/duplicate-target.sh" App AppStaging -P App.xcodeproj --bundle-id com.example.app.staging
```

Copies product type/kind, every build phase (kinds, script bodies, shells,
inputs/outputs, copy destinations), dependencies, and every raw build setting per
configuration. **File memberships are not copied** (the CLI cannot report a
phase file's group): re-run `group include` for each synchronized folder or file
the new target should build.

### Create a new project

```bash
"$SCRIPTS/new-xcodeproj.sh" --name MyApp --output-dir . --bundle-id-prefix com.example \
    [--product-type application|framework|tool|...] [--platforms "iphoneos iphonesimulator macosx"] \
    [--swift-version 5.0] [--deployment-target 26.0]
```

Writes a `project.xcproj` (JSON, **Xcode 27.2+ only** — there is no way to
create a `pbxproj` project with this CLI) with one target, a synchronized source
folder containing a starter file, and Debug/Release settings, then validates it
with `xcrun xcodeproj target list`. Add more targets with the recipes above. If
the user needs an older-Xcode-compatible project, say so and point them at Xcode's
New Project dialog.

### Swift package dependencies (`project.xcproj` only)

The CLI has no package commands. For JSON projects the bundled script edits the
two relevant keys (`packages` at the top level, `package-product-members` on the
target — shapes in `references/xcproj-format.md`):

```bash
"$SCRIPTS/xcproj-package.py" list   App.xcodeproj
"$SCRIPTS/xcproj-package.py" add    App.xcodeproj --url https://github.com/apple/swift-collections \
    --requirement from:1.1.0 --target App --product Collections --product DequeModule
"$SCRIPTS/xcproj-package.py" add    App.xcodeproj --path ../LocalKit --target App --product LocalKit
"$SCRIPTS/xcproj-package.py" remove App.xcodeproj --package-name swift-collections
```

Requirements: `1.2.3`/`from:1.2.3` (up to next major), `upToNextMinor:`, `exact:`,
`range:1.0.0..<2.0.0`, `branch:`, `revision:`. The linked products show up in
`target phase info` for the frameworks phase. Resolve/build with a **scheme**
(`xcodebuild -scheme App`); `-target` builds do not resolve packages. For a
`project.pbxproj` project the script refuses — add the package in Xcode instead.

## Task index

| Task | `xcrun xcodeproj` equivalent |
|---|---|
| Create a project | `scripts/new-xcodeproj.sh` (xcproj format only) |
| List targets | `target list` |
| List build configurations | `[..]` headers of `setting list` |
| List a target's files | `target info` + `target phase info` per phase |
| List groups | `group ls -R` |
| Read build settings | `setting list --target T [--config C]` / `setting get` |
| Change a build setting | `setting set` / `set-multi` / `unset` (per-config works in both formats) |
| Add a file | `group add-file` + `group include --phase N` (or drop into a synchronized folder) |
| Remove a file | `group remove-file [--force]` |
| Move or rename a file | no command — remove + add, or `mv` inside a synchronized folder |
| Add a synchronized folder | `group add --filesystem-path` + `group include --group` |
| Create a group | `group add [--parent]` |
| Add a target | `target add` + `target phase add` ×N + `setting set` ×N (see recipe) |
| Remove a target | `target remove` (after `remove-dependency`) |
| Duplicate a target | `scripts/duplicate-target.sh` |
| Add a target dependency | `target add-dependency` |
| Link a framework | `group add-file '<SDKROOT>/…'` + `group include --phase <frameworks>`; embed via copy phase |
| Add a build phase | `target phase add-script` / `add-copy` |
| Add or remove an app extension | extension recipe above |
| Add, list or remove Swift packages | `scripts/xcproj-package.py` (xcproj only) |

## Gotchas

- `-P` goes after the subcommand; `--target`/`--config` go before `--`.
- Phase indices are positions, not IDs. `add-script --before 1` shifts every other phase; `phase move --to` counts after removal.
- `target add` seeds no platform settings and no phases. New targets need at least `SWIFT_VERSION`, `SDKROOT`, deployment target, `PRODUCT_BUNDLE_IDENTIFIER`, and `GENERATE_INFOPLIST_FILE=YES` for bundles that are not application/framework/bundle/test types.
- `--product-type` does not validate its value; use the listed short names or a full `com.apple.product-type.*` identifier from `references/product-types.md`. `watch-app` / `watch-extension` are broken short names. For watchOS/tvOS extension types and a few legacy ones no `Products` reference is created, so they cannot be linked or embedded with `group include … --group Products`.
- `target remove` has no cascade: remove dependents' `add-dependency` edges first. It does clean product references and embed memberships.
- `group add-file` rejects synchronized folders (files there are discovered from disk); `group include`/`exclude` on them writes an exception list instead.
- `group include` of a regular-group file needs `--phase`; a synchronized-folder file must not have one.
- `setting set KEY ''` stores an empty string; `unset` removes the key.
- Values are raw: `$(inherited)` is stored literally and lists come back shell-quoted one per line in `setting list`, pasteable into `set-multi`.
- Output is English prose tables. Do not localize or reformat it when relaying; quote it.
- In `project.xcproj`, a configuration-specific value is stored as a `KEY[config=Debug]` key. `setting list` still shows it under the right `[Debug]` block.
- After any structural change, confirm with `xcodebuild -list -project App.xcodeproj` (parses the project) and, when possible, a build.
