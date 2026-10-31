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
  3. Playing now — apps currently playing: icon, name, slider, mute and, while the panel is open, a level meter (§14)
  4. Microphone — input device cards, mute button and input slider, level meter (see §2)
  5. Footer: "Sound Settings…" shortcut, the settings gear menu (§15–§17) and Quit
  - Device cards show a connection-type subtitle (Built-in, USB, Bluetooth, ...) and an SF Symbol derived from the transport type and name. Battery level is not shown: there is no public API for it.
- Menu bar icon: a template image made of the output glyph plus an optional microphone badge. The glyph is derived from the audio state, most important first — muted output (`speaker.slash.fill`), a still four-bar equalizer while any app plays (deliberately not animated, to keep the menu bar calm), the output device's symbol when idle on an external output, otherwise a speaker whose waves follow the volume. While the microphone is muted, a small `mic.slash.fill` badge is drawn to the right of the glyph (3 pt gap, 11 pt symbol, 16 pt tall image) instead of replacing it, so the output state stays visible; the pure resolution is `MenuBarIcon` in `Core/`, the compositing is `MenuBarIconRenderer`, and the image is redrawn only when the icon value changes. No mic-in-use badge: macOS already shows its orange indicator.
- An app that stops playing stays in the list for **10 seconds**, dimmed, before disappearing (so sliders don't vanish under the cursor on pause).
- Options live in a gear `Menu` in the footer (launch at login, volume keys, a "Mute Microphone" item that shows ⌃⌘M), backed by `SettingsModel`; there is no separate Settings window.

### 5. Persistence and app grouping
- Per-app volume is remembered by **bundle ID** and reapplied when the app plays again, across restarts. Apps never adjusted start at 100%.
- Mute state is **not** persisted.
- Helper processes (e.g. "Google Chrome Helper (Renderer)", Electron helpers) are grouped under their parent app. Consequence: no per-tab control in browsers.

### 6. Keyboard
- Hardware volume keys (F11/F12) control Earshot's software master **only when the current output has no hardware volume**; otherwise events pass through to the system.
  - Requires a `CGEventTap` and therefore the **Accessibility** permission, requested only when the user enables this option in Settings.
- Global shortcut to toggle mic mute: see §15. The menu bar icon reflects mic-muted state (§4).
- Volume keys: see §16.

### 7. Distribution
- Open source on GitHub; anyone can build from source with their own team.
- Pushing a `v*` tag runs `.github/workflows/release.yml`: tests, a universal build (`Scripts/package-release.sh`), and a GitHub release with the zipped app and its SHA-256.
- For now releases are ad-hoc signed and **not notarized** (no Developer ID certificate yet): users approve the first launch in System Settings › Privacy & Security, and macOS re-asks for audio permissions after each update. Adding the Developer ID secrets switches the same workflow to signed, notarized builds with no code change.
- No auto-update; new versions are downloaded from GitHub Releases.
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
- Per-app level meters are described in §14: tapped apps are measured by their own tap, other playing apps get a read-only meter tap while the panel is open.
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

### 14. Per-app level meters
- Each playing app in the mixer shows a small segmented meter under its slider. It exists **only while the panel is visible** (`PlayingAppsModel.panelDidAppear/panelDidDisappear`, called from `PanelView` like the input meter).
- **Apps with a volume tap** (volume ≠ 100% or muted): the tap's IO proc already walks every output sample, so it also records the peak of what it writes. The level is therefore **post-gain** (it follows the slider and is 0 when muted, and includes the software master). No second tap is created.
- **Apps at 100% without a tap**: while the panel is visible `MeterPlanner` asks for a **meter-only tap**: a private process tap with `muteBehavior = .unmuted`, a private aggregate device on the default output (same construction as a volume tap) and an IO proc that only measures the input and writes silence. The app keeps playing straight to the hardware, untouched, so the level is the app's own (pre-master). Earshot's own process object is never tapped (filtered in the model and again in the controller). Only apps that are playing get one; lingering (dimmed) apps do not.
- **Lifecycle:** `TapPlan` carries `meters` next to `perApp` and `global`; `TapReconciler.meterChanges` diffs them. On panel close the plan has no meters, so every meter-only tap, aggregate device and IO proc is destroyed and routing is exactly as before. A volume change away from 100% destroys the meter tap **before** the volume tap is created, and the way back destroys the volume tap before the meter tap is created, so an app never has both. A default output change tears down and rebuilds meters with the other taps (§3).
- **Interaction with the software-master global tap (§9):** the global tap excludes process objects of *volume-tapped* apps and Earshot, and nothing else. Meter-only taps do not change that list: a metered app at 100% is still captured by the global tap (muted at the source, played back with the master gain) exactly as without a meter. The meter tap adds no playback (its IO proc writes zeros), so nothing is played twice, and an unmuted tap does not alter which taps mute the process. Its aggregate device is not a process, so the global tap cannot capture it. The meter of such an app reads the audio before the master gain. Whether Core Audio hands the same audio to an unmuted tap and a muting tap on one process is expected but needs checking on hardware (manual-test).
- **Real-time safety:** the IO procs never allocate, lock, log or touch Swift concurrency. `LevelProbe` keeps a decaying peak hold (~50 ms) in I/O-thread-only state and publishes it with one aligned 32-bit store of the `Float` bit pattern into a manually allocated cell; the main actor reads it with one aligned 32-bit load. One writer, atomic word access on arm64 and x86-64, and a stale read only delays the meter by a buffer, the same justification as the gain target. `os_unfair_lock` was rejected (priority inversion on the I/O thread) and `Synchronization.Atomic` needs macOS 15.
- **Polling and smoothing:** a 25 Hz timer (run loop `.common` mode, so meters move while a slider is dragged) runs only while the panel is visible. Peaks go through `LevelScale` (dB mapping) and `LevelSmoother` (instant attack, linear fall-off), in `Core/` and tested. Helpers of one app are mixed into one tap, so a grouped app already has a single combined level.
- No new permission: meter taps use the same System Audio Recording access.

### 15. Global shortcut: mute the microphone
- **⌃⌘M** toggles the microphone mute from anywhere. It is registered with Carbon `RegisterEventHotKey`, which needs no Accessibility permission, behind the `GlobalHotKeys` protocol (`Earshot/System/`). The C callback only extracts the hot key ID and hops to the main queue before touching state (`MainActor.assumeIsolated`).
- The action is `InputModel.toggleMute()`. When the input cannot be muted (`canMute == false`, or no device) the app plays `NSSound.beep()`.
- The shortcut is fixed (not configurable) and always on. If another app already owns the combination, registration fails silently. It is shown in the mute button's tooltip and in the settings menu. The app registers it at launch except inside the unit-test host.

### 16. Volume keys for outputs without hardware volume
- Opt-in setting "Use volume keys for outputs without hardware volume" (`UserDefaults`, default off).
- When on, a `CGEventTap` (session, head insert, default tap) listens for `systemDefined` events of subtype 8 and handles `NX_KEYTYPE_SOUND_UP` (0), `SOUND_DOWN` (1) and `MUTE` (7). Decoding and key→action mapping are pure (`MediaKeyEvent`, `VolumeKeyMapper` in `Core/`): steps of 1/16, 1/64 with Option+Shift, clamped and snapped to 1/64; mute toggles `OutputModel.toggleMute()`; stepping while muted unmutes, like macOS.
- Events are consumed only while `OutputModel.usesSoftwareMaster` is true (key-up included, so the system never sees half a press); otherwise they pass through untouched. The tap is re-enabled on `tapDisabledByTimeout` / `tapDisabledByUserInput`. The tap runs on the main run loop, so its callback calls the handler synchronously on the main thread.
- Requires **Accessibility** (`AXIsProcessTrusted`). Enabling the setting without trust shows the system prompt (`AXIsProcessTrustedWithOptions`); the menu then offers "Allow in Accessibility settings…". The tap starts once trusted: trust is re-checked whenever the panel opens (no polling), so granting the permission and opening the panel is enough.
- Needs live testing with a real HDMI output; the tap itself cannot be unit-tested (`VolumeKeyInterceptor` has a fake).

### 17. Launch at login
- `SMAppService.mainApp` behind `LaunchAtLoginService`. The toggle always reflects the real `status` (re-read when the panel opens), never a stored flag. `requiresApproval` shows as on plus an "Allow in Login Items settings…" item that calls `SMAppService.openSystemSettingsLoginItems()`.
- No `Info.plist` or build setting changes are needed for any of §15–§17: Carbon hot keys, `SMAppService.mainApp` and the Accessibility prompt (system text) have no usage-description keys, and the app is not sandboxed.

## Deferred to v2
- Per-app output routing (different apps to different devices)
- Named presets (e.g. "Meeting", "Focus")
- Tap exclusion list (never tap e.g. DAWs)

## Known risks and limitations
- Bluetooth headsets drop to HFP (e.g. 16 kHz) while their mic is active, degrading output quality. This is a Bluetooth limitation, outside Earshot's control.
- Some USB mics (e.g. HyperX SoloCast) may not expose hardware input volume.
- Tapped apps get a few ms of added latency (aggregate device + playback buffer).
- No per-tab control in browsers.
