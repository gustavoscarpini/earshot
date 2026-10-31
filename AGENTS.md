# AGENTS.md

Context for AI coding agents working on Earshot. Read this first, then
[`docs/DESIGN.md`](docs/DESIGN.md) for the reasoning behind each decision.
Users and features are described in [`README.md`](README.md).

## What Earshot is

A macOS menu bar app (SwiftUI `MenuBarExtra(.window)`, `LSUIElement`) with:

- **Per-app volume and mute** using Core Audio Process Taps (no virtual driver).
- **Output device** picker and master volume, with a **software master** for
  outputs that have no hardware volume (HDMI monitors).
- **Microphone** picker, input volume, mute, "in use by" indicator and a level
  meter.
- **Now playing** header (track, artwork, progress, transport buttons) through
  the vendored `mediaremote-adapter`.

Swift 6 language mode, strict concurrency, macOS 14.4+, Xcode 16+ (developed on
Xcode 26 / macOS 26). No App Sandbox, hardened runtime on. MIT licensed. UI in
English and Brazilian Portuguese.

## Commands

```sh
make build      # Debug build into build/ (never DerivedData)
make test       # unit tests
make release    # Release build
make dist       # release zip in build/release (VERSION=0.1.0 required)
```

The exact commands agents should use to verify a change (both must pass with
zero Swift errors **and warnings**):

```sh
xcodebuild -project Earshot.xcodeproj -scheme Earshot -configuration Debug -derivedDataPath build build
xcodebuild -project Earshot.xcodeproj -scheme Earshot -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

The test build rewrites the app unsigned; rebuild Debug afterwards before
launching it. The only expected noise is Xcode's "appintentsmetadataprocessor …
skipped" warning and `com.apple.linkd.autoShortcut` log lines.

## Layout

| Path | What lives there |
| --- | --- |
| `Earshot/Core/` | Pure logic, **Foundation only** (no CoreAudio, AppKit or SwiftUI): grouping, tracking, gain, tap policy/planning/reconciling, volume store, device and now-playing value types, stream parsing. Fully unit-tested. |
| `Earshot/CoreAudio/` | Core Audio and AVFoundation behind `@MainActor` protocols: process monitor, tap controller, device controller (input/output), input level meter. |
| `Earshot/System/` | Other system integrations behind `@MainActor` protocols: Carbon global hot keys, the volume-key `CGEventTap` (+ Accessibility trust), launch at login (`SMAppService`). |
| `Earshot/NowPlaying/` | The `mediaremote-adapter` process wrapper behind `NowPlayingSource`, artwork color. |
| `Earshot/App/` | `@Observable @MainActor` models (`PlayingAppsModel`, `OutputModel`, `InputModel`, `NowPlayingModel`, `SettingsModel`, `MenuBarIconModel`) and `EarshotApp`. |
| `Earshot/UI/` | SwiftUI views; `PanelView` is the menu bar panel. |
| `Earshot/Resources/` | `Localizable.xcstrings`, assets. |
| `EarshotTests/` | Swift Testing suites; fakes in `Fakes.swift` and `FakeAudioProcessMonitor.swift`. |
| `Config/` | `Signing.xcconfig`, `Local.xcconfig.example`, `Info.plist`, entitlements. |
| `Scripts/` | `build-mediaremote-adapter.sh` (Xcode run-script phase), `package-release.sh`, `make-app-icon.swift` (regenerates the `AppIcon` PNGs and `Contents.json`: `swift Scripts/make-app-icon.swift`). |
| `Vendor/mediaremote-adapter/` | Vendored upstream sources (BSD-3). **Never edit**; see `VENDORED.md` to update. |
| `docs/` | `DESIGN.md`, `manual-test.md`, `images/`. |

## Conventions

- Match the surrounding code: English doc comment (`///`) on every type and
  member, same naming and density.
- Pure logic goes in `Core/` and gets tests. System APIs stay behind a
  `@MainActor` protocol with a fake in `EarshotTests/Fakes.swift`.
- Models expose idempotent `start()` / `stop()`, stop on
  `NSApplication.willTerminateNotification`, and take injectable dependencies
  (`now:`, stores, controllers) for tests.
- Swift 6 concurrency: never touch main-actor state from audio or I/O threads.
  Hop with `DispatchQueue.main.async { MainActor.assumeIsolated { … } }`; use a
  small documented `@unchecked Sendable` box only when state is confined to one
  queue.
- Tests use Swift Testing (`@Test`, `#expect`), never XCTest. Do not weaken or
  delete assertions to make a test pass.
- User-visible strings are written in English in code and localized in
  `Localizable.xcstrings` with a `pt-BR` translation. Keep the file valid JSON,
  keys sorted case-insensitively, the same two-space `"key": value` formatting
  (`json.dumps(indent=2, ensure_ascii=False)`), and remove keys that become
  unused.
- Code, comments, docs and commit messages in English.

## Things that are easy to get wrong

- **Xcode project:** `Earshot/` and `EarshotTests/` are
  file-system-synchronized groups, so new `.swift` files are picked up
  automatically. Do not edit `project.pbxproj` unless the task requires it.
- **Taps are on demand:** a per-app tap exists only when the app's volume is not
  100% or it is muted (values ≥ 0.99 snap to 1). The global tap for the software
  master excludes tapped apps and Earshot's own process object, and is skipped
  when that object is unknown (to avoid feedback). Changes here need live
  testing on real hardware; unit tests cannot cover them.
- **Devices to hide:** Earshot's own aggregates (`com.gustavoscarpini.Earshot…`)
  and `CADefaultDeviceAggregate-*` (created for `AVAudioEngine`) must not
  appear in pickers.
- **Mic users:** only processes inside an `.app` bundle count, so daemons such
  as CoreSpeech ("Hey Siri") never show as "in use by". Earshot itself is
  excluded.
- **Mic metering** shows the orange privacy dot and switches Bluetooth headsets
  to the hands-free profile. It runs only while the panel is visible, and only
  automatically when another app already uses the mic.
- **Now playing** relies on a private framework: `/usr/bin/perl` loads the
  bundled `MediaRemoteAdapter.framework`. If it breaks after a macOS update,
  the header shows its empty state and nothing else may be affected. The app
  does not start the adapter inside the unit-test host. **Never run the
  adapter's `send` command** while testing: it controls the user's real music.
  `get --no-artwork` is safe.
- **Signing:** `Config/Local.xcconfig` (gitignored) sets `DEVELOPMENT_TEAM`,
  `CODE_SIGN_IDENTITY = Apple Development` and `CODE_SIGN_STYLE = Automatic`.
  Without it builds are ad-hoc signed and macOS re-asks for audio permissions
  after every rebuild. Never commit team IDs, certificates (`*.p12`, `*.cer`),
  API keys (`*.p8`) or provisioning profiles.
- **Do not launch** Earshot or kill the user's running instance unless asked;
  live audio testing is done by the human.

## Commits and releases

- Short imperative subject ("Add …", "Fix …"), a wrapped body explaining what
  and why, and a `Co-Authored-By` trailer for the agent.
- Commit and push only when asked. History authors must use the maintainer's
  personal identity, never a work email.
- Releases: push a `v*` tag; `.github/workflows/release.yml` tests, builds a
  universal app with `Scripts/package-release.sh` and publishes the zip and its
  SHA-256. Builds are ad-hoc signed and not notarized until Developer ID
  secrets are configured (see README › Releases).
- The README screenshot `docs/images/panel.png` is rendered from the real panel
  by the opt-in `EarshotTests/ReadmeScreenshot.swift` (command in README ›
  Testing). Regenerate it when the panel changes visibly.

## Before you finish

1. Both verification commands pass with zero errors and warnings.
2. New logic has tests; existing tests still pass.
3. `Localizable.xcstrings` is valid and has pt-BR for every new string.
4. `docs/DESIGN.md`, `README.md` and `docs/manual-test.md` are updated when
   behavior changes.
5. Report what you changed, what you could not verify (e.g. live audio), and
   the result line of each command.
