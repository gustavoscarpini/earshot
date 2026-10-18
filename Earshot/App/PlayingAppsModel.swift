import Foundation
import Observation

/// Keeps the "Apps" section in sync with the apps currently playing audio.
///
/// Owns a `PlayingAppsTracker` (the 10-second linger rule) and feeds it grouped
/// processes from an `AudioProcessMonitor`. The monitor reports changes, and a
/// one-second timer re-runs `refresh()` so lingering apps disappear on time
/// (DESIGN §4, §5).
@MainActor
@Observable
final class PlayingAppsModel {
    /// The apps to show, playing first-class and lingering ones dimmed.
    private(set) var apps: [PlayingApp] = []

    private let monitor: any AudioProcessMonitor
    private let now: () -> Date
    private var tracker = PlayingAppsTracker()
    private var timer: Timer?
    private var isRunning = false

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - monitor: The process monitor to read and observe.
    ///   - now: The current-time source, injectable for tests.
    init(monitor: any AudioProcessMonitor, now: @escaping () -> Date = Date.init) {
        self.monitor = monitor
        self.now = now
    }

    /// Starts observing the monitor and the one-second linger timer.
    ///
    /// Idempotent: calling it again while running does nothing, so the app can
    /// start it once at launch without risking duplicate timers.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        monitor.start { [weak self] in
            self?.refresh()
        }
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    /// Stops the linger timer and the monitor.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        monitor.stop()
    }

    /// Reads the monitor and reconciles the shown apps.
    func refresh() {
        let playing = Self.group(monitor.processes().filter(\.isRunningOutput)) { path in
            Self.displayName(forAppBundlePath: path)
        }
        tracker.update(playing: playing, now: now())
        apps = tracker.apps
    }

    /// Groups running-output processes into one entry per app.
    ///
    /// The id is the parent app bundle path, else the bundle identifier, else
    /// `"pid:<pid>"`; helpers of the same app collapse onto one entry (DESIGN
    /// §5). An empty bundle identifier counts as none. Processes without a
    /// bundle are named after their executable (e.g. `afplay`) when known. Pure so tests can supply a `displayName` and avoid the file system.
    ///
    /// - Parameters:
    ///   - processes: The processes to group, one entry per id.
    ///   - displayName: Resolves a display name from an app bundle path.
    /// - Returns: One `(id, name)` per app, in first-seen order.
    static func group(
        _ processes: [AudioProcess],
        displayName: (String) -> String
    ) -> [(id: String, name: String)] {
        var result: [(id: String, name: String)] = []
        var seen = Set<String>()

        for process in processes {
            let id: String
            let name: String
            if let bundlePath = process.executablePath.flatMap(AppGrouping.outermostAppBundlePath(forExecutablePath:)) {
                id = bundlePath
                name = displayName(bundlePath)
            } else if let bundleID = process.bundleID, !bundleID.isEmpty {
                id = bundleID
                name = bundleID
            } else {
                id = "pid:\(process.pid)"
                let executableName = process.executablePath.map { ($0 as NSString).lastPathComponent } ?? ""
                name = executableName.isEmpty ? "PID \(process.pid)" : executableName
            }

            guard seen.insert(id).inserted else { continue }
            result.append((id: id, name: name))
        }

        return result
    }

    /// The user-visible name of an app bundle, without the `.app` extension.
    private static func displayName(forAppBundlePath path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        let extensionSuffix = ".app"
        return name.hasSuffix(extensionSuffix) ? String(name.dropLast(extensionSuffix.count)) : name
    }
}
