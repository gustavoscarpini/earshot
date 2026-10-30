import AppKit
import Foundation
import Observation

/// Keeps the "Apps" section in sync with the apps currently playing audio, and
/// owns their per-app volume and mute.
///
/// Owns a `PlayingAppsTracker` (the 10-second linger rule) and feeds it grouped
/// processes from an `AudioProcessMonitor`. The monitor reports changes, and a
/// one-second timer re-runs `refresh()` so lingering apps disappear on time
/// (DESIGN §4, §5). After every change it tells the `TapController` which apps
/// need a tap: only those below 100% or muted, plus the global tap while the
/// software master is below 100% (DESIGN §9).
@MainActor
@Observable
final class PlayingAppsModel {
    /// The apps to show, playing first-class and lingering ones dimmed.
    private(set) var apps: [PlayingApp] = []

    /// Per-app volume by app id, `0...1`. Missing means 100%.
    private(set) var volumes: [String: Float] = [:]

    /// Display names of the other apps currently capturing the microphone, in
    /// first-seen order. Earshot's own capture is excluded.
    private(set) var micUsers: [String] = []

    /// Muted app ids. Session-only, and cleared once an app leaves the list.
    private(set) var mutedIDs: Set<String> = []

    /// The software master gain from the output device, `0...1`; `1` when the
    /// output has hardware volume.
    @ObservationIgnored private var softwareMaster: Float = 1

    private let monitor: any AudioProcessMonitor
    private let tapController: any TapController
    private let volumeStore: any VolumeStore
    private let now: () -> Date
    private let appBundleIdentifier: (String) -> String?
    private let ownPID: pid_t
    private let ownBundleID: String?
    private var tracker = PlayingAppsTracker()
    private var timer: Timer?
    private var terminationObserver: (any NSObjectProtocol)?
    private var isRunning = false

    /// App id → bundle identifier used as the persistence key, `nil` for apps
    /// without one. Resolved once per app id.
    @ObservationIgnored private var persistenceKeys: [String: String?] = [:]

    /// App id → every Core Audio process object of that app, playing or not.
    @ObservationIgnored private var processObjectIDs: [String: [UInt32]] = [:]

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - monitor: The process monitor to read and observe.
    ///   - tapController: Creates and removes the per-app taps.
    ///   - volumeStore: Remembers volumes by bundle identifier.
    ///   - now: The current-time source, injectable for tests.
    ///   - appBundleIdentifier: Resolves the bundle identifier of an app bundle
    ///     path, injectable for tests.
    ///   - ownPID: Earshot's process identifier, whose input never counts as
    ///     another app using the microphone.
    ///   - ownBundleID: Earshot's bundle identifier, likewise.
    init(
        monitor: any AudioProcessMonitor,
        tapController: any TapController,
        volumeStore: any VolumeStore,
        now: @escaping () -> Date = Date.init,
        appBundleIdentifier: @escaping (String) -> String? = { Bundle(path: $0)?.bundleIdentifier },
        ownPID: pid_t = getpid(),
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        self.monitor = monitor
        self.tapController = tapController
        self.volumeStore = volumeStore
        self.now = now
        self.appBundleIdentifier = appBundleIdentifier
        self.ownPID = ownPID
        self.ownBundleID = ownBundleID
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

    /// Stops the linger timer and the monitor, and removes every tap so all
    /// apps play directly to the hardware again.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        terminationObserver = nil
        monitor.stop()
        tapController.apply(TapPlan(perApp: [:], global: nil))
    }

    /// Reads the monitor, reconciles the shown apps and updates the taps.
    func refresh() {
        let processes = monitor.processes()
        processObjectIDs = Self.processObjectIDsByApp(processes)

        let playing = Self.group(processes.filter(\.isRunningOutput)) { path in
            Self.displayName(forAppBundlePath: path)
        }
        for entry in playing where persistenceKeys[entry.id] == nil {
            loadStoredVolume(forAppID: entry.id)
        }

        let users = Self.micUserNames(
            processes,
            ownPID: ownPID,
            ownBundleID: ownBundleID,
            displayName: { Self.displayName(forAppBundlePath: $0) }
        )
        if users != micUsers {
            micUsers = users
        }

        tracker.update(playing: playing, now: now())
        apps = tracker.apps
        mutedIDs.formIntersection(apps.map(\.id))
        applyTaps()
    }

    // MARK: Volume and mute

    /// The volume of the app with `id`, `0...1`.
    func volume(for id: String) -> Float {
        volumes[id] ?? 1
    }

    /// Sets the volume of the app with `id`, snapping near-full values to 100%,
    /// and remembers it by bundle identifier when the app has one.
    func setVolume(_ volume: Float, for id: String) {
        let volume = TapPolicy.normalizedVolume(volume)
        volumes[id] = volume
        if let key = persistenceKeys[id] ?? nil {
            volumeStore.setVolume(volume, forBundleID: key)
        }
        applyTaps()
    }

    /// Whether the app with `id` is muted.
    func isMuted(_ id: String) -> Bool {
        mutedIDs.contains(id)
    }

    /// Mutes or unmutes the app with `id`.
    func toggleMute(_ id: String) {
        if mutedIDs.remove(id) == nil {
            mutedIDs.insert(id)
        }
        applyTaps()
    }

    /// Sets the software master gain (`0` while a software master is muted) and
    /// re-applies the taps. Pass `1` when the output has hardware volume.
    func setSoftwareMaster(_ gain: Float) {
        softwareMaster = min(max(gain, 0), 1)
        applyTaps()
    }

    // MARK: Grouping

    /// Groups running-output processes into one entry per app.
    ///
    /// The id is the parent app bundle path, else the bundle identifier, else
    /// `"pid:<pid>"`; helpers of the same app collapse onto one entry (DESIGN
    /// §5). An empty bundle identifier counts as none. Processes without a
    /// bundle are named after their executable (e.g. `afplay`) when known.
    /// Pure so tests can supply a `displayName` and avoid the file system.
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
            let identity = identity(of: process, displayName: displayName)
            guard seen.insert(identity.id).inserted else { continue }
            result.append(identity)
        }

        return result
    }

    /// The display names of the apps capturing audio input, grouped like the
    /// playing apps and in first-seen order.
    ///
    /// Only processes inside an `.app` bundle count: system daemons such as
    /// CoreSpeech ("Hey Siri") capture the microphone all the time and are not
    /// apps the user started. A process is also skipped when it is Earshot
    /// itself (`ownPID`) or belongs to Earshot's bundle (`ownBundleID`, including
    /// its helpers), so the level meter's own capture never counts as another
    /// app.
    static func micUserNames(
        _ processes: [AudioProcess],
        ownPID: pid_t,
        ownBundleID: String?,
        displayName: (String) -> String
    ) -> [String] {
        let others = processes.filter { process in
            guard process.isRunningInput, process.pid != ownPID else { return false }
            guard let path = process.executablePath,
                  AppGrouping.outermostAppBundlePath(forExecutablePath: path) != nil else { return false }
            guard let ownBundleID, let bundleID = process.bundleID else { return true }
            return bundleID != ownBundleID && !bundleID.hasPrefix(ownBundleID + ".")
        }
        return group(others, displayName: displayName).map(\.name)
    }

    /// Every process object of each app, keyed by the same id as `group`, so a
    /// tap covers helpers that are not playing yet.
    static func processObjectIDsByApp(_ processes: [AudioProcess]) -> [String: [UInt32]] {
        var result: [String: [UInt32]] = [:]
        for process in processes {
            let id = identity(of: process, displayName: { $0 }).id
            result[id, default: []].append(process.objectID)
        }
        return result
    }

    private static func identity(
        of process: AudioProcess,
        displayName: (String) -> String
    ) -> (id: String, name: String) {
        if let bundlePath = process.executablePath.flatMap(AppGrouping.outermostAppBundlePath(forExecutablePath:)) {
            return (bundlePath, displayName(bundlePath))
        }
        if let bundleID = process.bundleID, !bundleID.isEmpty {
            return (bundleID, bundleID)
        }
        let executableName = process.executablePath.map { ($0 as NSString).lastPathComponent } ?? ""
        return ("pid:\(process.pid)", executableName.isEmpty ? "PID \(process.pid)" : executableName)
    }

    // MARK: Private

    /// Resolves the persistence key of a newly seen app and restores its
    /// remembered volume.
    private func loadStoredVolume(forAppID id: String) {
        let key: String?
        if id.hasPrefix("pid:") {
            key = nil
        } else if id.hasSuffix(".app") {
            key = appBundleIdentifier(id)
        } else {
            key = id
        }
        persistenceKeys[id] = .some(key)

        if volumes[id] == nil, let key, let stored = volumeStore.volume(forBundleID: key) {
            volumes[id] = stored
        }
    }

    /// Tells the tap controller which taps are needed: per-app taps for shown
    /// apps below 100% or muted, plus the global tap when the software master
    /// is below 100% (`TapPlanner`).
    private func applyTaps() {
        let inputs = apps.map { app in
            TapPlanInput(
                id: app.id,
                volume: volume(for: app.id),
                muted: isMuted(app.id),
                processObjectIDs: processObjectIDs[app.id] ?? []
            )
        }
        tapController.apply(TapPlanner.plan(apps: inputs, softwareMaster: softwareMaster))
    }

    /// The user-visible name of an app bundle, without the `.app` extension.
    private static func displayName(forAppBundlePath path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        let extensionSuffix = ".app"
        return name.hasSuffix(extensionSuffix) ? String(name.dropLast(extensionSuffix.count)) : name
    }
}
