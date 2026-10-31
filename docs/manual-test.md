# Manual test checklist

Scenarios that need real audio hardware, so they cannot run in CI. Check these
by hand before a release. Based on DESIGN §11.

## Per-app volume

- [ ] Set an app (e.g. Spotify) to 30% and confirm it gets quieter.
- [ ] Confirm each playing app shows a level meter that follows its audio, both
      at 100% (meter-only tap) and below 100% (the meter follows the slider).
- [ ] Return the app to 100% and confirm the tap is destroyed (the app plays
      directly to hardware again).
- [ ] Mute an app, then unmute it, and confirm audio returns.
- [ ] Restart the app and confirm its remembered volume is reapplied
      (persistence is keyed by bundle ID).
- [ ] Confirm an app that stops playing stays in the list, dimmed, for ~10
      seconds before it disappears.
- [ ] Confirm helper processes (e.g. "Google Chrome Helper (Renderer)") are
      grouped under their parent app.

## Per-app level meters

- [ ] Open the panel with an app playing at 100%: its meter moves and its audio
      is unchanged (no echo, no doubling, no level or latency change).
- [ ] Mute the app: the meter reads empty. Unmute: it moves again.
- [ ] Close the panel and confirm the meter taps are torn down: the system
      audio recording indicator in Control Center goes away and no "Earshot Tap"
      device shows up in Audio MIDI Setup (private aggregates are hidden, so
      also check `system_profiler SPAudioDataType` before and after), and the
      audio is unchanged.
- [ ] With the panel open, drag an app from 100% to 50% and back: no double
      audio at any point, the meter keeps moving, and no clicks beyond a brief
      transition.
- [ ] Set the software master below 100% (HDMI output) with an app at 100%
      and the panel open: the app is not played twice, its meter moves, and
      closing the panel does not change what you hear.
- [ ] Switch the output device with the panel open: meters resume on the new
      device within a moment and audio is not doubled.
- [ ] A browser with several helper processes shows a single meter.
- [ ] Earshot itself never gets a meter row or a meter tap.
- [ ] Meters keep moving while a slider is being dragged.

## Output device

- [ ] Switch the output device while audio is playing and confirm audio
      continues and taps are rebuilt correctly.
- [ ] Disconnect a Bluetooth headset while audio is playing and confirm Earshot
      recovers and audio returns to the built-in output.
- [ ] On an HDMI output that has no hardware volume, confirm the software master
      works and that gain is never applied twice.
- [ ] Change the system default output from System Settings and confirm Earshot
      follows it.

## Microphone

- [ ] Adjust mic input gain on a device that has hardware input volume.
- [ ] Mute and unmute the microphone globally.
- [ ] Confirm the menu bar icon shows the crossed-out mic badge next to the
      output glyph while muted, and loses it when unmuted.
- [ ] Press ⌃⌘M from another app: the mic mutes and unmutes (panel slider and
      menu bar badge follow). The mute button's tooltip mentions ⌃⌘M.
- [ ] Select a mic that cannot be muted (no hardware volume or mute) and press
      ⌃⌘M: the system beeps and nothing changes.
- [ ] Switch the input device by tapping its card and confirm it becomes the system
      default input.
- [ ] Connect a USB mic without hardware volume (e.g. HyperX SoloCast) and
      confirm the slider is disabled with a "not supported by this device" hint
      while mute still works.

- [ ] Open the panel while no other app records: no meter, and the waveform
      button starts and stops it by hand. Closing the panel stops it.
- [ ] Start a call or recording in another app, then open the panel: the meter
      starts by itself and the selected mic card reads "In use by <App>".

## Menu bar icon

- [ ] Idle on the built-in speakers, confirm the speaker's waves follow the
      volume slider.
- [ ] Play audio and confirm the icon becomes a still equalizer (no motion);
      pause and confirm it returns to the idle icon once the app stops playing.
- [ ] Mute the output and confirm `speaker.slash.fill`; mute the microphone and
      confirm the output glyph stays and a small `mic.slash.fill` badge appears
      to its right (also while playing and on AirPods).
- [ ] Switch to AirPods or a display and confirm the idle icon shows the device.
- [ ] Confirm the icon reads well on light and dark menu bars and when pressed.

## Volume keys and login (gear menu)

- [ ] On an HDMI output without hardware volume, with the option off, F11/F12
      and mute do nothing (system behavior).
- [ ] Turn "Use volume keys for outputs without hardware volume" on: the system
      Accessibility prompt appears; the menu shows "Allow in Accessibility
      settings…" until granted. Grant it, reopen the panel and confirm the item
      disappears.
- [ ] On the HDMI output, F12/F11 raise/lower the Earshot slider in 1/16 steps
      (Option+Shift: 1/64), mute toggles, and stepping while muted unmutes. No
      system volume HUD for the HDMI output.
- [ ] Switch to the built-in speakers: the keys control the system volume as
      usual (the event passes through).
- [ ] Turn the option off and confirm the keys revert to the system's behavior.
- [ ] "Launch at Login" on: Earshot appears in System Settings › General ›
      Login Items and opens after logging out and in. Turn it off in System
      Settings and confirm the menu toggle follows after reopening the panel.
- [ ] If macOS asks for approval, the menu shows "Allow in Login Items
      settings…" and it opens the right pane.
- [ ] The gear menu shows "Mute Microphone ⌃⌘M"; choosing it mutes the mic, and it then reads "Unmute Microphone". It is disabled when the input cannot be muted.

## Robustness

- [ ] `kill -9` Earshot while a tapped app is playing and confirm audio returns
      to normal.
- [ ] Quit Earshot from its panel and confirm no taps are left behind.
- [ ] Confirm Earshot has no Dock icon (`LSUIElement`).

## Keyboard (optional)

- [ ] With the volume-key option enabled (Accessibility granted), on an output
      with no hardware volume, confirm F11/F12 control Earshot's software
      master.
- [ ] On an output that has hardware volume, confirm F11/F12 still reach the
      system.
- [ ] Confirm the global mic-mute shortcut toggles mute.

## Localization

- [ ] Switch the system language to Portuguese (Brazil) and confirm the panel
      and menu bar title are translated.
