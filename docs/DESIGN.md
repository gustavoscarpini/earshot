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
- Input device picker (changes the system default input).
- Real-time input level meter.
- Devices that expose no hardware input volume (common with USB mics) show the slider disabled with a "not supported by this device" hint; mute still works.
- Out of scope: per-app mic control and software gain above 100% (both would require a virtual driver).

### 3. Output device and master volume
- Follow the system default output device; rebuild taps when it changes.
- Output device picker in the UI.
- Hybrid master volume: use the device's hardware volume when available, fall back to a software master when not (e.g. HDMI displays).

### 4. UI: menu bar only
- `MenuBarExtra` with `.window` style, no Dock icon (`LSUIElement`).
- Panel layout, top to bottom:
  1. Master volume + output device picker
  2. Apps currently playing — icon, name, slider, mute
  3. Microphone — input picker, slider, mute, level meter
- An app that stops playing stays in the list for **10 seconds**, dimmed, before disappearing (so sliders don't vanish under the cursor on pause).
- Small Settings screen for options (keyboard, launch at login, shortcuts).

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

## Deferred to v2
- Per-app output routing (different apps to different devices)
- Named presets (e.g. "Meeting", "Focus")
- Tap exclusion list (never tap e.g. DAWs)

## Known risks and limitations
- Bluetooth headsets drop to HFP (e.g. 16 kHz) while their mic is active, degrading output quality. This is a Bluetooth limitation, outside Earshot's control.
- Some USB mics (e.g. HyperX SoloCast) may not expose hardware input volume.
- Tapped apps get a few ms of added latency (aggregate device + playback buffer).
- No per-tab control in browsers.
