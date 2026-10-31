import AppKit
import SwiftUI
import Testing
@testable import Earshot

/// Renders the real panel with sample data into docs/images/panel.png for the
/// README. Opt-in: runs only when EARSHOT_SCREENSHOT is set.
@MainActor
struct ReadmeScreenshot {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["EARSHOT_SCREENSHOT"] != nil))
    func renderPanel() throws {
        let monitor = FakeAudioProcessMonitor()
        monitor.processesToReturn = [
            AudioProcess(objectID: 1, pid: 101, bundleID: "com.spotify.client",
                         executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify",
                         isRunningOutput: true, isRunningInput: false),
            AudioProcess(objectID: 2, pid: 102, bundleID: "com.google.Chrome.helper",
                         executablePath: "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper",
                         isRunningOutput: true, isRunningInput: false),
            AudioProcess(objectID: 3, pid: 103, bundleID: "com.apple.FaceTime",
                         executablePath: "/System/Applications/FaceTime.app/Contents/MacOS/FaceTime",
                         isRunningOutput: false, isRunningInput: true)
        ]
        let taps = FakeTapController()
        taps.peaksToReturn = ["/Applications/Spotify.app": 0.5]
        let playingApps = PlayingAppsModel(
            monitor: monitor,
            tapController: taps,
            volumeStore: InMemoryVolumeStore()
        )
        playingApps.start()
        playingApps.setVolume(0.6, for: "/Applications/Spotify.app")
        playingApps.setVolume(0.4, for: "/Applications/Google Chrome.app")
        playingApps.toggleMute("/Applications/Google Chrome.app")

        let outputs = FakeAudioDeviceController()
        outputs.devicesToReturn = [
            AudioDevice(uid: "spk", name: "MacBook Pro Speakers", transport: .builtIn),
            AudioDevice(uid: "air", name: "AirPods Pro", transport: .bluetooth),
            AudioDevice(uid: "lg", name: "LG HDR 4K", transport: .hdmi)
        ]
        outputs.defaultUID = "air"
        outputs.volumes = ["spk": 0.5, "air": 0.45]
        outputs.mutes = ["spk": false, "air": false]
        let output = OutputModel(controller: outputs, defaults: UserDefaults(suiteName: "EarshotScreenshot")!)
        output.start()

        let inputs = FakeAudioDeviceController()
        inputs.devicesToReturn = [
            AudioDevice(uid: "mic", name: "MacBook Pro Microphone", transport: .builtIn),
            AudioDevice(uid: "usb", name: "USB Microphone", transport: .usb)
        ]
        inputs.defaultUID = "mic"
        inputs.volumes = ["mic": 0.7]
        inputs.mutes = ["mic": false]
        let meter = FakeInputLevelMeter()
        let input = InputModel(controller: inputs, meter: meter)
        input.start()

        let source = FakeNowPlayingSource()
        let nowPlaying = NowPlayingModel(source: source)
        nowPlaying.start()
        source.emit(NowPlayingInfo(
            bundleID: "com.spotify.client",
            title: "Midnight Drive",
            artist: "The Placeholders",
            album: "Sample Album",
            isPlaying: true,
            artworkData: Self.artwork(),
            duration: 214,
            elapsedTime: 83,
            timestamp: Date(),
            playbackRate: 0
        ))

        let settings = SettingsModel(
            launchService: FakeLaunchAtLogin(),
            volumeKeys: FakeVolumeKeyInterceptor(),
            hotKeys: FakeGlobalHotKeys(),
            input: input,
            output: output,
            defaults: UserDefaults(suiteName: "EarshotScreenshot")!
        )
        let panel = PanelView(nowPlaying: nowPlaying, playingApps: playingApps, output: output, input: input, settings: settings)
        let root = panel
            .background(Color(nsColor: NSColor(white: 0.14, alpha: 1)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(40)
            .background(Color(nsColor: NSColor(white: 0.08, alpha: 1)))
            .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.orderFrontRegardless()
        meter.emit(0.55)
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.layoutSubtreeIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/images/panel.png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        window.orderOut(nil)
    }

    /// A generated stand-in for album artwork.
    private static func artwork() -> Data? {
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1),
                NSColor(red: 0.55, green: 0.25, blue: 0.75, alpha: 1)
            ])?.draw(in: rect, angle: -45)
            NSColor.white.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: NSRect(x: 70, y: 70, width: 160, height: 160)).fill()
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: NSRect(x: 130, y: 130, width: 40, height: 40)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
