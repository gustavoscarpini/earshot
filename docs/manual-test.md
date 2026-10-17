# Manual test checklist

Scenarios that need real audio hardware, so they cannot run in CI. Check these
by hand before a release. Based on DESIGN §11.

## Per-app volume

- [ ] Set an app (e.g. Spotify) to 30% and confirm it gets quieter.
- [ ] Confirm the level meter appears only for tapped apps.
- [ ] Return the app to 100% and confirm the tap is destroyed (the app plays
      directly to hardware again).
- [ ] Mute an app, then unmute it, and confirm audio returns.
- [ ] Restart the app and confirm its remembered volume is reapplied
      (persistence is keyed by bundle ID).
- [ ] Confirm an app that stops playing stays in the list, dimmed, for ~10
      seconds before it disappears.
- [ ] Confirm helper processes (e.g. "Google Chrome Helper (Renderer)") are
      grouped under their parent app.

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
- [ ] Confirm the menu bar icon reflects the mic-muted state.
- [ ] Switch the input device via the picker and confirm it becomes the system
      default input.
- [ ] Connect a USB mic without hardware volume (e.g. HyperX SoloCast) and
      confirm the slider is disabled with a "not supported by this device" hint
      while mute still works.

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
