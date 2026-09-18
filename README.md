# xcodeproj Skill

[![CI](https://github.com/giginet/xcodeproj-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/giginet/xcodeproj-skill/actions/workflows/ci.yml)
[![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-D97757?logo=anthropic&logoColor=white)](#claude-code)
[![Codex](https://img.shields.io/badge/Codex-plugin-10A37F?logo=openai&logoColor=white)](#codex)
[![gh skill](https://img.shields.io/badge/gh_skill-install-1F2328?logo=github&logoColor=white)](#github-cli-gh-skill)
[![Xcode 27.2](https://img.shields.io/badge/Xcode-27.2+-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)

The **xcodeproj** plugin — teach your coding agent to inspect and modify Xcode
projects (`.xcodeproj`) with `xcrun xcodeproj`, the project-manipulation CLI
that ships with Xcode 27.2. The same package installs three ways: as a
[Claude Code plugin](https://docs.claude.com/en/docs/claude-code/plugins), a
[Codex plugin](https://developers.openai.com/codex/plugins), or a standalone
skill via [`gh skill`](https://cli.github.com/manual/gh_skill_install).

## Install

Published at <https://github.com/giginet/xcodeproj-skill>. Pick the host you use — each path installs the same `manage-xcodeproj` skill.

**Prerequisite:** Xcode 27.2 or newer selected via `xcode-select` (`xcrun --find xcodeproj` must succeed). The helper scripts need only `bash` and `python3`.

### Claude Code

```
/plugin marketplace add giginet/xcodeproj-skill
/plugin install xcodeproj@xcodeproj
```

Then run `/reload-plugins` once and confirm with `/` — you should see `/xcodeproj:manage-xcodeproj`. The `@xcodeproj` suffix names the marketplace declared in `.claude-plugin/marketplace.json`.

### Codex

```sh
codex plugin marketplace add giginet/xcodeproj-skill
codex plugin add xcodeproj@xcodeproj
```

Backed by the repo marketplace at `.agents/plugins/marketplace.json` with the manifest at `plugins/xcodeproj/.codex-plugin/plugin.json`. Codex sets `CLAUDE_PLUGIN_ROOT` for compatibility, so the skill's `${CLAUDE_PLUGIN_ROOT}/skills/manage-xcodeproj/scripts/...` references work unchanged.

### GitHub CLI (`gh skill`)

Requires GitHub CLI v2.90.0+.

```sh
gh skill install giginet/xcodeproj-skill manage-xcodeproj --agent claude-code
```

The skill is self-contained: `SKILL.md`, `references/` and `scripts/` are copied together, so `gh skill` delivers the whole toolset. Outside a plugin host `${CLAUDE_PLUGIN_ROOT}` is unset, so run the scripts from the installed skill's `scripts/` directory (the `SKILL.md` explains this).

## Skill

One skill, `manage-xcodeproj`, covers inspection, editing and the multi-step recipes:

| Triggers on | What it does |
|---|---|
| "list the targets", "what does target X compile", "show the build settings for Release" | `target list`, `target info`, `target phase info`, `group ls -R`, `setting list/get` — read-only inspection of either project format. |
| "add this file to the target", "create a group", "add a synchronized folder", "link AVFoundation", "embed the framework" | `group add / add-file / include / exclude / remove-file`, framework references under `<SDKROOT>`, copy-phase embedding with code-sign-on-copy. |
| "add a Run Script phase", "move the SwiftLint phase first", "set SWIFT_VERSION to 6", "add -lz to OTHER_LDFLAGS for Release" | `target phase add-script / add-copy / move / remove`, `setting set / set-multi / unset` per configuration. |
| "add a framework target", "add a widget extension", "duplicate the app target for staging", "create a new project", "add swift-collections" | Recipes for things the CLI has no single command for, backed by `scripts/new-xcodeproj.sh`, `scripts/duplicate-target.sh` and `scripts/xcproj-package.py`. |

## What `xcrun xcodeproj` does and doesn't do

Everything below was verified against Xcode 27.2 beta on both a legacy `project.pbxproj` project and a freshly generated JSON `project.xcproj` project, including `xcodebuild` builds of the results.

| Area | Native CLI support | This skill adds |
|---|---|---|
| Targets | list, info, add (native/aggregate), remove, dependencies | Build-ready defaults: which settings and phases a bare `target add` is missing |
| Build phases | info, add sources/resources/frameworks/headers, add-script, add-copy, move, remove | — |
| Build settings | get, list, set, set-multi, unset; project or target; per configuration in **both** formats | — |
| Groups & files | ls, add (plain or filesystem-synchronized), add-file, remove-file, remove, include/exclude in targets | Framework linking/embedding recipe, move/rename workaround |
| App extensions | *(composed from the above)* | Verified widget (ExtensionKit) and classic extension recipes |
| Duplicate target | — | `scripts/duplicate-target.sh` (settings, phases, dependencies; file memberships must be re-added) |
| Create project | — | `scripts/new-xcodeproj.sh` (writes a minimal `project.xcproj`; Xcode 27.2+ only) |
| Swift packages | — | `scripts/xcproj-package.py` list/add/remove by editing `project.xcproj` (not available for `pbxproj`) |

## Repo layout

```
.
├── .claude-plugin/
│   └── marketplace.json                 Claude Code marketplace index (points at plugins/)
├── .agents/plugins/
│   └── marketplace.json                 Codex repo marketplace (points at plugins/)
├── skills -> plugins/xcodeproj/skills   symlink for top-level `gh skill --from-local`
├── plugins/
│   └── xcodeproj/
│       ├── .claude-plugin/plugin.json   Claude Code manifest
│       ├── .codex-plugin/plugin.json    Codex manifest (skills: "./skills/")
│       └── skills/
│           └── manage-xcodeproj/
│               ├── SKILL.md             CLI reference, recipes, task index, gotchas
│               ├── references/
│               │   ├── xcproj-format.md project.xcproj JSON schema notes (packages, per-config settings)
│               │   └── product-types.md every --product-type identifier, verified against Xcode 27.2
│               └── scripts/
│                   ├── new-xcodeproj.sh     create a minimal project.xcproj
│                   ├── duplicate-target.sh  replay a target's phases/settings/dependencies
│                   ├── xcproj-package.py    list/add/remove Swift packages in project.xcproj
│                   └── tests/
│                       ├── test-xcproj-package.sh   unit test, no Xcode needed
│                       └── smoke.sh                 end-to-end with xcodebuild (Xcode 27.2+)
└── README.md
```

## Hacking on the skill locally

```sh
S=plugins/xcodeproj/skills/manage-xcodeproj/scripts

# Unit test for the package editor (python3 only)
$S/tests/test-xcproj-package.sh

# End-to-end: generate projects, exercise every recipe, build them (needs Xcode 27.2+, ~1–2 min)
$S/tests/smoke.sh

# Lint
shellcheck $S/*.sh $S/tests/*.sh
claude plugin validate plugins/xcodeproj
```

## See also

- [xcodeproj-mcp-server](https://github.com/giginet/xcodeproj-mcp-server) — the MCP server this skill grew out of.
- [apple/xcode-project-format](https://github.com/apple/xcode-project-format) — Apple's Swift package describing the `project.xcproj` JSON schema.

## License

MIT
