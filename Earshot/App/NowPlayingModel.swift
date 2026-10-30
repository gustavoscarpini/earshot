import AppKit
import Observation

/// Owns the now playing header: the item reported by the system and the
/// transport controls (DESIGN §13).
///
/// `info` is `nil` when nothing is playing or the adapter is unavailable; the
/// header shows its empty state then. Commands do nothing without an item.
@MainActor
@Observable
final class NowPlayingModel {
    /// The current now playing item, or `nil`.
    private(set) var info: NowPlayingInfo?

    /// The decoded artwork for `info`, decoded once per artwork change.
    private(set) var artwork: NSImage?

    /// The icon of the app playing `info`, used when there is no artwork. `nil`
    /// when the app cannot be found.
    private(set) var appIcon: NSImage?

    /// The average color of `artwork`, used as the header's ambient background.
    /// `nil` without artwork. Computed once per artwork change.
    private(set) var ambientColor: NSColor?

    /// The localized name of the app playing `info` (e.g. "Spotify"), shown in
    /// the source badge. `nil` when the app cannot be found.
    private(set) var sourceName: String?

    private let source: any NowPlayingSource
    private let now: () -> Date
    private var isRunning = false
    private var terminationObserver: (any NSObjectProtocol)?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - source: Reports the now playing item and sends commands.
    ///   - now: The current-time source, injectable for tests.
    init(source: any NowPlayingSource, now: @escaping () -> Date = Date.init) {
        self.source = source
        self.now = now
    }

    /// Starts the source.
    ///
    /// Idempotent: calling it again while running does nothing.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        source.start { [weak self] info in
            self?.apply(info)
        }

        // Quitting must not leave the adapter's perl process behind.
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }
    }

    /// Stops the source and clears the item.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        source.stop()
        apply(nil)
    }

    /// Toggles play/pause. The header flips right away, freezing or resuming the
    /// progress estimate; the next update from the source wins.
    func togglePlayPause() {
        guard let info else { return }
        source.send(.togglePlayPause)
        self.info = info.togglingPlayback(at: now())
    }

    /// Skips to the next track.
    func nextTrack() {
        guard info != nil else { return }
        source.send(.nextTrack)
    }

    /// Goes back to the previous track.
    func previousTrack() {
        guard info != nil else { return }
        source.send(.previousTrack)
    }

    // MARK: Private

    /// Stores the new item and refreshes the artwork, its average color, the
    /// icon and the source name only when their inputs changed.
    private func apply(_ new: NowPlayingInfo?) {
        let old = info
        info = new

        if new?.artworkData != old?.artworkData {
            artwork = new?.artworkData.flatMap { NSImage(data: $0) }
            ambientColor = new?.artworkData.flatMap(ArtworkColor.average(of:))
        }

        if new?.bundleID != old?.bundleID || new?.parentBundleID != old?.parentBundleID {
            appIcon = new.flatMap { info in
                [info.parentBundleID, info.bundleID]
                    .compactMap { $0 }
                    .lazy
                    .compactMap(Self.icon(forBundleID:))
                    .first
            }
            sourceName = new.flatMap { info in
                [info.parentBundleID, info.bundleID]
                    .compactMap { $0 }
                    .lazy
                    .compactMap(Self.appName(forBundleID:))
                    .first
            }
        }
    }

    /// The localized display name of the app with `bundleID`, without the
    /// `.app` extension, if it is installed.
    private static func appName(forBundleID bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        let suffix = ".app"
        let trimmed = name.hasSuffix(suffix) ? String(name.dropLast(suffix.count)) : name
        if !trimmed.isEmpty { return trimmed }
        return Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleName") as? String
    }

    /// The icon of the app with `bundleID`, if it is installed.
    private static func icon(forBundleID bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
