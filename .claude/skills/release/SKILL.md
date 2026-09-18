---
name: release
description: Cut a new version of the xcodeproj plugin — bump the version in both plugin manifests, verify the CI gate locally, commit to main, and publish a GitHub release. Use this when the user asks to release, ship, cut, or tag a version ("release 1.2", "バージョン1.2を出して", "tag a new version", "publish a release").
---

# Release a new version

This repo ships a Claude Code / Codex plugin. A release is: bump the version in
every manifest, verify, commit to `main`, then create a GitHub release whose
tag `gh` creates for you.

There is no CHANGELOG file — release notes are generated from merged PR titles.

## 1. Decide the version

Ask the user if they did not say. Otherwise infer from what landed since the last
tag:

```bash
git fetch origin --tags
git log --oneline $(git describe --tags --abbrev=0)..origin/main
```

Tags are `vX.Y.Z`. Normalize a shorthand like "1.2" to the full `1.2.0`.

## 2. Preflight

```bash
git switch main && git pull --ff-only
git status --short   # must be empty
```

## 3. Bump the version

Find every file carrying the **current** version — do not trust a hardcoded list:

```bash
grep -rn "<current-version>" --include="*.json" .
```

As of 1.0.0 that is two files:

| File | How to update |
|---|---|
| `plugins/xcodeproj/.claude-plugin/plugin.json` | edit `"version"` |
| `plugins/xcodeproj/.codex-plugin/plugin.json` | edit `"version"` |

The two marketplace files carry no version. Leave them alone.

## 4. Run the CI gate locally

`.github/workflows/ci.yml` runs these steps. Run them before pushing:

```bash
shellcheck plugins/xcodeproj/skills/manage-xcodeproj/scripts/*.sh plugins/xcodeproj/skills/manage-xcodeproj/scripts/tests/*.sh
python3 -m py_compile plugins/xcodeproj/skills/manage-xcodeproj/scripts/xcproj-package.py
plugins/xcodeproj/skills/manage-xcodeproj/scripts/tests/test-xcproj-package.sh
plugins/xcodeproj/skills/manage-xcodeproj/scripts/tests/smoke.sh   # needs Xcode 27.2+
claude plugin validate plugins/xcodeproj
```

## 5. Commit to `main`

Version bumps go directly on `main`. Commit message in English, subject
`Bump version to X.Y.Z`, with a body saying what the release contains.

```bash
git add -A plugins
git commit   # subject: Bump version to X.Y.Z
git push origin main
```

End the message with the `Co-Authored-By:` trailer for the model you are running as.

## 6. Publish the release

```bash
gh release create vX.Y.Z --target main --title vX.Y.Z --generate-notes
```

## 7. Verify and report

```bash
gh release view vX.Y.Z
gh run list --limit 2
```

Report the release URL and the CI result. If CI went red after the push, say so
plainly rather than presenting the release as clean.
