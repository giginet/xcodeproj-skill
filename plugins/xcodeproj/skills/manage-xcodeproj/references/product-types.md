# `--product-type` reference

`xcrun xcodeproj target add NAME --product-type TYPE` accepts either one of 15
short names or any `com.apple.product-type.*` identifier. This table lists every
product type defined by Xcode 27.2's build system specifications (the
`*.xcspec` files inside `SwiftBuild.framework`), how `target list` prints it, and
what the CLI does with it. All rows were exercised with `target add` on both a
`project.pbxproj` and a `project.xcproj` project.

**The CLI does not validate the identifier.** Any string is stored verbatim
after prefixing `com.apple.product-type.` when needed, and `xcodebuild` only
fails later with `unable to resolve product type '<id>' for platform '<p>'`.
Two of the documented short names hit exactly this bug — see the warning below.

## Short names

| Short name | Expands to | Product | Notes |
|---|---|---|---|
| `application` | `com.apple.product-type.application` | `Name.app` | |
| `app-extension` | `com.apple.product-type.app-extension` | `Name.appex` | Classic (Foundation) extension, embedded in `PlugIns` |
| `framework` | `com.apple.product-type.framework` | `Name.framework` | |
| `library.dynamic` | `com.apple.product-type.library.dynamic` | `Name.dylib` | |
| `library.static` | `com.apple.product-type.library.static` | `libName.a` | |
| `bundle` | `com.apple.product-type.bundle` | `Name.bundle` | |
| `unit-test-bundle` | `com.apple.product-type.bundle.unit-test` | `Name.xctest` | Printed as `bundle.unit-test` |
| `ui-test-bundle` | `com.apple.product-type.bundle.ui-testing` | `Name.xctest` | Printed as `bundle.ui-testing` |
| `tool` | `com.apple.product-type.tool` | `Name` | Command-line tool |
| `kernel-extension` | `com.apple.product-type.kernel-extension` | `Name.kext` | macOS |
| `instruments-package` | `com.apple.product-type.instruments-package` | `Name.instrdst` | |
| `xcode-extension` | `com.apple.product-type.xcode-extension` | `Name.appex` | macOS only; no product reference is created in a pbxproj project |
| `driver-extension` | `com.apple.product-type.driver-extension` | `Name.dext` | DriverKit |
| `watch-app` | `com.apple.product-type.watch-app` | — | **Broken:** this identifier does not exist in Xcode. Use `com.apple.product-type.application.watchapp2` |
| `watch-extension` | `com.apple.product-type.watch-extension` | — | **Broken:** does not exist. Use `com.apple.product-type.watchkit2-extension` |

> **Warning.** `--product-type watch-app` and `--product-type watch-extension`
> write product types that Xcode's build system cannot load
> (`Couldn't load spec with identifier 'com.apple.product-type.watch-app'`).
> Always pass the full watchOS identifiers instead.

## Every identifier known to Xcode 27.2

`target list` prints the identifier without the `com.apple.product-type.` prefix.
"Product ref" says whether `target add` also created the entry under `Products`
that `group include X --group Products` needs for linking or embedding; without
one, the CLI cannot link or embed that target's product into another target.

| Identifier (`com.apple.product-type.` + …) | Xcode name | Product | Product ref | Notes |
|---|---|---|---|---|
| `application` | Application | `.app` | yes | |
| `application.on-demand-install-capable` | App Clip | `.app` | yes | |
| `application.messages` | iMessage Application | `.app` | yes | |
| `application.watchapp2` | WatchKit App | `.app` | **no** | watchOS app (WatchKit 2) |
| `application.watchapp2-container` | Watch-Only Application Stub | `.app` | yes | |
| `application.watchapp` | WatchKit App (1.0) | — | no | Deprecated; xcodebuild rejects it |
| `application.java` | Java Application | — | no | Legacy |
| `app-extension` | App Extension | `.appex` | yes | |
| `app-extension.messages` | iMessage Extension | `.appex` | yes | |
| `app-extension.messages-sticker-pack` | Sticker Pack Extension | `.appex` | yes | |
| `app-extension.intents-service` | Watch Intent App Extension | `.appex` | no | watchOS |
| `extensionkit-extension` | ExtensionKit Extension | `.appex` | yes | Widgets and other ExtensionKit points; embed with `--destination extensions` |
| `watchkit2-extension` | WatchKit Extension | `.appex` | **no** | watchOS |
| `watchkit-extension` | WatchKit Extension (1.0) | `.appex` | no | Deprecated |
| `tv-app-extension` | TV App Extension | `.appex` | no | tvOS |
| `tv-broadcast-extension` | TV Broadcast Extension | `.appex` | no | tvOS |
| `xcode-extension` | Xcode Extension | `.appex` | xcproj only | macOS |
| `framework` | Framework | `.framework` | yes | |
| `framework.static` | Static Framework | `.framework` | yes | |
| `library.dynamic` | Dynamic Library | `.dylib` | yes | |
| `library.static` | Static Library | `lib*.a` | yes | |
| `library.java.archive` | Java Library | — | no | Legacy |
| `objfile` | Object File | `.o` | yes | |
| `metal-library` | Metal Library | `.metallib` | yes | |
| `bundle` | Bundle | `.bundle` | yes | |
| `bundle.unit-test` | Unit Test Bundle | `.xctest` | yes | |
| `bundle.ui-testing` | UI Testing Bundle | `.xctest` | yes | |
| `bundle.ocunit-test` | OCUnit Test Bundle | `.octest` | yes | Legacy |
| `bundle.external-test` | External Test Bundle | `.externaltest` | yes | |
| `tool` | Command-line Tool | (none) | yes | |
| `tool.host-build` | Host Build Tool | (none) | yes | |
| `tool.swiftpm-test-runner` | SwiftPM Unit Test Runner | (none) | yes | |
| `tool.java` | Java Command-line Tool | — | no | Legacy |
| `xpc-service` | XPC Service | `.xpc` | yes | macOS |
| `pluginkit-plugin` | PlugInKit PlugIn | `.pluginkit` | yes | |
| `system-extension` | System Extension | `.systemextension` | yes | macOS |
| `driver-extension` | DriverKit Driver | `.dext` | yes | |
| `kernel-extension` | Kernel Extension | `.kext` | yes | macOS |
| `kernel-extension.iokit` | IOKit Kernel Extension | `.kext` | yes | macOS |
| `spotlight-importer` | Spotlight Importer | `.mdimporter` | no | macOS |
| `in-app-purchase-content` | In-App Purchase Content | (none) | yes | Legacy |
| `instruments-package` | Instruments Package | `.instrdst` | yes | |

Not in this table: `org.swift.product-type.*` (SwiftPM-internal object
libraries) and the generic Unix/Windows/WebAssembly specializations, which are
not meaningful in an Xcode project.

## Choosing a type

- iOS/macOS app → `application`; App Clip → `com.apple.product-type.application.on-demand-install-capable`.
- Widget, Live Activity, Intents, Share (Xcode 16+ templates) → `com.apple.product-type.extensionkit-extension`; older-style extensions → `app-extension`.
- watchOS → `com.apple.product-type.application.watchapp2` + `com.apple.product-type.watchkit2-extension` (never the short names).
- Tests → `unit-test-bundle` / `ui-test-bundle`.
- Shared code → `framework`, `framework.static` (`com.apple.product-type.framework.static`), `library.static`, `library.dynamic`.
- Helper processes → `tool` (CLI), `com.apple.product-type.xpc-service` (XPC, macOS).
