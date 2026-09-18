# `project.xcproj` — the JSON project format (Xcode 27.2+)

Inside a `.xcodeproj` bundle Xcode 27.2 writes `project.xcproj` instead of
`project.pbxproj`. It is JSON5-flavoured JSON (trailing commas, key order
preserved) and is the format `scripts/new-xcodeproj.sh` and
`scripts/xcproj-package.py` produce or edit. `xcrun xcodeproj` re-canonicalizes
the whole file on its next write, so plain JSON without trailing commas is fine
as input. Everything below was verified against Xcode 27.2 beta; the schema is
also published as the Swift package
[apple/xcode-project-format](https://github.com/apple/xcode-project-format).

## Minimal valid document

```json
{
  "default-configuration": "Release",
  "configurations": ["Debug", "Release"],
  "localizations": { "development": "en", "supported": ["Base"] },
  "files": [
    { "kind": "folder", "path": "Hand", "target-membership": ["Hand"] },
    {
      "kind": "group",
      "name": "Products",
      "children": [
        { "path": "<PRODUCTS>/Hand", "id": "A000000000000000000000B1", "type": "compiled.mach-o.executable", "index": false }
      ]
    }
  ],
  "targets": [
    {
      "name": "Hand",
      "id": "A000000000000000000000A1",
      "product": "Products/Hand",
      "product-type": "tool",
      "build-phases": ["compile-sources", "frameworks"],
      "build-settings": { "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_VERSION": "5.0", "SDKROOT": "macosx" }
    }
  ]
}
```

Required, in the order Xcode reports missing keys: `localizations`; every target
needs an `id` (24 uppercase hex characters) and a `product` pointing at an entry
in the `Products` group (`"Invalid reference: Products"` otherwise). Aggregate
targets (`"kind": "aggregate"`) have no product.

## Key map

| Key | Where | Meaning |
|---|---|---|
| `configurations` | project | Configuration names, or objects `{ "name", "file": <xcconfig ref> }`. |
| `build-settings` | project, target | Flat `KEY: string \| [string]` map. A per-configuration value uses the key suffix `KEY[config=Debug]`; conditional settings keep their normal spelling `KEY[sdk=iphoneos*]`. |
| `files` | project | Navigator tree. `{ "kind": "folder", "path", "target-membership": [<target>, …] }` is a filesystem-synchronized folder; `{ "kind": "group", "name"/"path", "children": [...] }` a plain group; a bare file entry is `{ "path", "id"?, "type"?, "target-membership": [ "App/compile-sources" \| { "build-phase": "App/copy/Embed Frameworks", "code-sign-on-copy": true, "header-preservation": "remove-on-copy" } ] }`. Anchors: `<PRODUCTS>`, `<SDKROOT>`, `<ABSOLUTE>`, `<BUILT_PRODUCTS_DIR>`, `<DEVELOPER_DIR>`, `<SRCROOT>`. |
| `targets[].build-phases` | target | Strings for simple phases (`compile-sources`, `frameworks`, `resources`, `headers`) or objects `{ "kind": "script", "name", "script", "shell-path", "input-paths", "output-paths", ... }` / `{ "kind": "copy", "name", "destination": ..., ... }`. File membership lives on the file entries (`target-membership`), not on the phase. |
| `targets[].dependencies` | target | `[ "Core", ... ]` target names. |
| `targets[].product-type` | target | Short form (`application`, `framework`, `tool`, `extensionkit-extension`); `full-product-type` for unknown identifiers. |
| `packages` | project | Swift packages (below). |
| `targets[].package-product-members` | target | Which package products a target links (below). |

## Swift packages

```jsonc
"packages": [
  { "kind": "remote", "repository": "https://github.com/apple/swift-collections",
    "version": { "up-to-next-major-version": "1.1.0" } },          // or "up-to-next-minor-version",
                                                                    // "version" (exact), "version-range": "1.0.0..<2.0.0",
                                                                    // "branch": "main", "revision": "<sha>"
  { "kind": "local", "path": "../LocalKit" },
  { "kind": "remote", "repository": "...", "version": {...}, "traits": ["Foo"] }   // optional package traits
]
```

Per target — note the doubly nested `build-phase` (the outer key holds a build
file object whose own `build-phase` names the phase):

```json
"package-product-members": [
  { "package": "swift-collections", "product-name": "Collections", "build-phase": { "build-phase": "frameworks" } }
]
```

`package` is the package identity (last path component of the URL without
`.git`, or the local directory name). A string value for the outer
`build-phase` (`"frameworks"` or `"App/frameworks"`) is **rejected**
(`Expected an instance of dictionary but an instance string was specified`).
After editing, `xcrun xcodeproj target phase info --target App <frameworks index>`
lists the product, and `xcodebuild -resolvePackageDependencies -scheme App`
fetches it.

## Validation

Any read command opens the document and fails fast with the offending JSON path:

```
Error: Failed to open “App.xcodeproj”.

Missing required value for key “id” at “/targets[0]”
```

`xcodebuild -list -project App.xcodeproj` reports the same problems from Xcode's
own loader. Run one of them after every hand edit.
