# Earshot — Design (v1)

Earshot is an open-source macOS menu bar app for per-app volume control, output device control, and microphone control.

**Problem:** macOS only offers a single system volume. There is no way to lower one app while keeping another loud, and some outputs (e.g. HDMI monitors) expose no volume control at all.

## Decisions

### 1. Per-app volume: Core Audio Process Taps
- Use Core Audio Process Taps (`CATapDescription`, `AudioHardwareCreateProcessTap`) — no virtual audio driver / HAL plugin.
- A tapped app's original output is muted (`muteBehavior = .mutedWhenTapped`); Earshot plays the tapped audio to the output device with the user's gain applied.
- "Apps currently playing" comes from Core Audio process objects (`kAudioProcessPropertyIsRunningOutput`), not from taps.
- Known trade-off: tapped audio flows through Earshot's process. If Earshot dies, the system releases the taps and audio returns to normal.

### 2. Microphone: device-level control
- Input gain via `kAudioDevicePropertyVolumeScalar` (input scope) on the selected input device.
- Global mic mute.
- Input device cards (tapping one changes the system default input). The selected card reads "In use by <App>" with an orange dot while another app is capturing the microphone (`kAudioProcessPropertyIsRunningInput`; Earshot's own capture is excluded).
- Real-time input level meter, only while the panel is visible. It starts **by itself while another app already uses the microphone** (the privacy indicator is on and Bluetooth headsets are already in hands-free mode, so it costs nothing extra). Otherwise it is off, and a small waveform button in the Microphone section starts and stops it by hand. It always stops when the panel closes.
- Devices that expose no hardware input volume (common with USB mics) show the slider disabled with a "not supported by this device" hint; mute still works.
- Out of scope: per-app mic control and software gain above 100% (both would require a virtual driver).

### 3. Output device and master volume
- Follow the system default output device; rebuild taps when it changes.
- Output device cards in the UI (a card per device: symbol, name, connection type; the selected one is highlighted).
- Hybrid master volume: use the device's hardware volume when available, fall back to a software master when not (e.g. HDMI displays).

### 4. UI: menu bar only
- `MenuBarExtra` with `.window` style, no Dock icon (`LSUIElement`).
- Panel layout (340 pt wide, material background, sections separated by thin dividers), top to bottom:
  1. Header: the now playing track with artwork, progress and transport buttons, or an empty state when nothing plays (see §13)
  2. Output — device cards, then mute button and master volume slider
  3. Playing now — apps currently playing: icon, name, slider, mute (room for a per-app level meter)
  4. Microphone — input device cards, mute button and input slider, level meter (see §2)
  5. Footer: "Sound Settings…" shortcut and Quit
  - Device cards show a connection-type subtitle (Built-in, USB, Bluetooth, ...) and an SF Symbol derived from the transport type and name. Battery level is not shown: there is no public API for it.
- Menu bar icon: a template image derived from the audio state, most important first — muted microphone (`mic.slash.fill`), muted output (`speaker.slash.fill`), a still four-bar equalizer while any app plays (deliberately not animated, to keep the menu bar calm), the output device's symbol when idle on an external output, otherwise a speaker whose waves follow the volume. No mic-in-use badge: macOS already shows its orange indicator.
- An app that stops playing stays in the list for **10 seconds**, dimmed, before disappearing (so sliders don't vanish under the cursor on pause).
- A small Settings screen for options (keyboard, launch at login, shortcuts) is planned; the panel has no gear icon until it exists.

### 5. Persistence and app grouping
- Per-app volume is remembered by **bundle ID** and reapplied when the app plays again, across restarts. Apps never adjusted start at 100%.
- Mute state is **not** persisted.
- Helper processes (e.g. "Google Chrome Helper (Renderer)", Electron helpers) are grouped under their parent app. Consequence: no per-tab control in browsers.

### 6. Keyboard
- Hardware volume keys (F11/F12) control Earshot's software master **only when the current output has no hardware volume**; otherwise events pass through to the system.
  - Requires a `CGEventTap` and therefore the **Accessibility** permission, requested only when the user enables this option in Settings.
- Configurable global shortcut to toggle mic mute (no Accessibility needed — registered hotkey). The menu bar icon reflects mic-muted state.

### 7. Distribution
- Open source on GitHub; users build from source.
- No Developer ID, no notarization, no auto-update.
- No App Sandbox.
- Launch at login via `SMAppService`.

### 8. Build and signing
- Xcode project committed to the repo.
- `Config/Signing.xcconfig` does `#include? "Local.xcconfig"`; `Config/Local.xcconfig` is gitignored.
  - Users copy `Config/Local.xcconfig.example` and set `DEVELOPMENT_TEAM` (free Personal Team works) and their bundle ID prefix.
  - Without a team, the build falls back to ad-hoc signing ("Sign to Run Locally"). README warns that macOS will then re-prompt for permissions after every rebuild, since TCC grants are tied to the code signature.
- `Makefile` with `make install`: Release build copied to `/Applications`.

### 9. Tap policy: on demand
- An app is tapped **only** when its volume ≠ 100% or it is muted. Back to 100% and unmuted → tap destroyed, app plays directly to hardware again (zero added latency, zero dependency on Earshot).
- Per-app level meters only appear for tapped apps.
- Software master below 100% (output without hardware volume): a **single global tap** ("all processes except X") excluding Earshot itself and any individually tapped apps, so gain is never applied twice. Individually tapped apps get `appGain × masterGain`.

### 10. Minimum macOS: 14.4
- Process taps exist since 14.2; the dedicated `NSAudioCaptureUsageDescription` permission and stable behavior arrived around 14.4.
- Primary testing happens on macOS 26. README marks 14.x/15.x as best-effort until confirmed by users.

### 11. Testing
- **Pure core logic**, covered with Swift Testing:
  - helper → parent app grouping
  - tap policy (when to tap / untap; global tap exclusion list)
  - per-bundle-ID persistence
  - 10-second linger rule
  - final gain computation (app × master)
- **Core Audio layer** kept thin behind protocols — `AudioProcessMonitor`, `TapController`, `DeviceController` — with fakes in tests.
- **Manual checklist** in `docs/manual-test.md`, including:
  - set an app (e.g. Spotify) to 30%
  - switch output device while audio is playing
  - disconnect a Bluetooth headset
  - `kill -9` Earshot and verify audio returns
  - USB mic without hardware volume
  - HDMI output without hardware volume
- **CI:** GitHub Actions runs build + core tests (no real audio device in CI).

### 12. Project
- Name: **Earshot**
- Bundle ID: `com.gustavoscarpini.Earshot` (prefix overridable in `Local.xcconfig`)
- License: MIT
- Code, README, commits: English
- UI localized in **en** and **pt-BR** via String Catalog (`Localizable.xcstrings`)

### 13. Now playing
- The header at the top of the panel shows the current track (artwork, title, artist, a badge with the playing app) with previous / play-pause / next buttons and a **progress bar** (elapsed on the left, remaining on the right). The header background is tinted with the artwork's average color, computed once per artwork change. The bar is estimated from the adapter's `elapsedTime`, `timestamp`, `playbackRate` and `duration` and ticks once a second only while playing; it is hidden when the duration is unknown. When nothing reports now playing info the header shows a "Nothing playing" hint. The bar is display-only: no seeking, shuffle, repeat or likes.
- There is **no public API** for this. Apple blocks the private MediaRemote framework for third-party apps since macOS 15.4, but `/usr/bin/perl` is entitled to use it. Earshot runs the [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) Perl script (vendored in `Vendor/mediaremote-adapter/`), which loads a small helper framework into perl and prints now playing changes as JSON on stdout. Commands (`send`) go through the same script.
- **Private API risk:** a macOS update may break the adapter. Then the header simply shows its empty state (the stream yields nothing, or the process keeps failing and Earshot gives up after a few relaunches); volume control, output and microphone are unaffected.
- The helper framework is built from the vendored sources with plain `clang` by `Scripts/build-mediaremote-adapter.sh`, an Xcode run-script phase — no CMake or other extra tools. The framework is embedded and signed with the app.
- The pure parts (line splitting, stream parsing, command IDs) live in `Earshot/Core/` and are tested; the process handling sits behind the `NowPlayingSource` protocol.

## Deferred to v2
- Per-app output routing (different apps to different devices)
- Named presets (e.g. "Meeting", "Focus")
- Tap exclusion list (never tap e.g. DAWs)

## Known risks and limitations
- Bluetooth headsets drop to HFP (e.g. 16 kHz) while their mic is active, degrading output quality. This is a Bluetooth limitation, outside Earshot's control.
- Some USB mics (e.g. HyperX SoloCast) may not expose hardware input volume.
- Tapped apps get a few ms of added latency (aggregate device + playback buffer).
- No per-tab control in browsers.
