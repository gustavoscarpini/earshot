# Earshot

Earshot is an open-source macOS menu bar app for **per-app volume control**,
**output device control**, and **microphone control**.

macOS only offers a single system volume: there is no way to lower one app while
keeping another loud, and some outputs (like HDMI monitors) expose no volume
control at all. Earshot fixes that from the menu bar, using Core Audio Process
Taps — no virtual audio driver, no kernel extension.

See [`docs/DESIGN.md`](docs/DESIGN.md) for the full design and the reasoning
behind each decision.

## Requirements

- **macOS 14.4 or later** — process taps exist since 14.2, but the
  `NSAudioCaptureUsageDescription` permission and stable behavior arrived around
  14.4.
- **Xcode 16 or later**, with the Swift 6 toolchain.

> macOS 14.x and 15.x are **best-effort** until confirmed by users. Development
> and primary testing happen on macOS 26.

## Build and install

1. Configure your local signing settings:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   Then edit `Config/Local.xcconfig` and uncomment **both** `DEVELOPMENT_TEAM`
   (a free Personal Team works) and `CODE_SIGN_IDENTITY = Apple Development`.
   Setting only the team keeps ad-hoc signing. Optionally change
   `BUNDLE_ID_PREFIX` if `com.gustavoscarpini` collides with something you
   already registered.

2. Build and install:

   ```sh
   make install
   ```

   That runs a Release build and copies `Earshot.app` into `/Applications`.
   Prefer to run it from the build directory? Use `make release` and open
   `build/Build/Products/Release/Earshot.app`.

Other targets:

| Target | What it does |
| --- | --- |
| `make build` | Debug build |
| `make test` | Runs the unit tests |
| `make release` | Release build |
| `make install` | Release build, copied to `/Applications` |
| `make clean` | Removes `build/` and Xcode's project caches |

You can also open `Earshot.xcodeproj` in Xcode and run the `Earshot` scheme.

### ⚠️ Signing without a team

If you leave `DEVELOPMENT_TEAM` empty, the build falls back to ad-hoc signing
("Sign to Run Locally") and Earshot still runs. **However, macOS ties permission
grants to the code signature, so it will re-ask for audio-capture permission
after every rebuild.** Setting a real `DEVELOPMENT_TEAM` gives your builds a
stable identity and avoids the repeated prompts.

## Permissions

- **System Audio Recording** — required. Earshot captures each app's audio with
  Core Audio Process Taps in order to apply its volume. The prompt is explained
  by `NSAudioCaptureUsageDescription`.
- **Accessibility** — optional. Requested **only** if you enable the option that
  lets the hardware volume keys (F11/F12) control Earshot's software master on
  outputs that have no hardware volume. Everything else works without it.

Earshot is not sandboxed (`ENABLE_APP_SANDBOX = NO`). The hardened runtime is
enabled, but Xcode turns it off for ad-hoc signed builds.

## Testing

```sh
make test
```

The pure core logic (gain computation, tap policy, and more as it lands) is
covered with [Swift Testing](https://developer.apple.com/xcode/swift-testing/).
The Core Audio layer sits behind the `AudioProcessMonitor`, `TapController`, and
`DeviceController` protocols so it can be faked in tests.

A manual checklist covering the scenarios that need real hardware lives in
[`docs/manual-test.md`](docs/manual-test.md).

## License

[MIT](LICENSE) © 2026 Gustavo Scarpini
