import Foundation

/// A `NowPlayingSource` backed by the vendored mediaremote-adapter.
///
/// Apple blocks the private MediaRemote framework for third-party apps, but
/// `/usr/bin/perl` is entitled to use it. So the source runs the adapter's Perl
/// script, which loads the helper framework built into the app bundle, and reads
/// its JSON stream from stdout (DESIGN §13).
///
/// If the script or the framework is missing, or the stream keeps failing, the
/// source stays inactive and reports `nil`; nothing else in the app is affected.
@MainActor
final class MediaRemoteAdapterSource: NowPlayingSource {
    /// Parses the adapter's output off the main thread.
    ///
    /// All of its state is confined to `queue`: `handle(_:)` must only be called
    /// from there, which is why `@unchecked Sendable` is safe. Results are
    /// forwarded through the two callbacks, which must hop to the main actor.
    private final class StreamReader: @unchecked Sendable {
        let queue = DispatchQueue(label: "Earshot.NowPlaying.parser")
        private var buffer = LineBuffer()
        private var parser = NowPlayingStreamParser()
        private var lastEmitted: NowPlayingInfo?
        private var didReportValidLine = false
        private let onValidLine: @Sendable () -> Void
        private let onChange: @Sendable (NowPlayingInfo?) -> Void

        init(
            onValidLine: @escaping @Sendable () -> Void,
            onChange: @escaping @Sendable (NowPlayingInfo?) -> Void
        ) {
            self.onValidLine = onValidLine
            self.onChange = onChange
        }

        /// Feeds a chunk of stdout. Call on `queue` only.
        func handle(_ data: Data) {
            for line in buffer.append(data) {
                guard case .state(let info) = parser.consume(line: line) else { continue }
                if !didReportValidLine {
                    didReportValidLine = true
                    onValidLine()
                }
                if info != lastEmitted {
                    lastEmitted = info
                    onChange(info)
                }
            }
        }
    }

    /// Delay before the first relaunch; it doubles up to `maxRelaunchDelay`.
    private static let initialRelaunchDelay: Duration = .seconds(2)
    private static let maxRelaunchDelay: Duration = .seconds(60)

    /// Consecutive launches without a valid line after which the source gives up.
    private static let maxFailures = 5

    private static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")

    private let scriptURL: URL?
    private let frameworkURL: URL?

    private var onChange: (@MainActor (NowPlayingInfo?) -> Void)?
    private var process: Process?
    private var relaunchTask: Task<Void, Never>?

    /// Identifies the current launch, so callbacks from a previous one are
    /// ignored.
    private var generation = 0

    /// Launches since the last valid line that ended without one.
    private var failures = 0
    private var lastDelivered: NowPlayingInfo?

    /// Creates the source.
    ///
    /// - Parameters:
    ///   - scriptURL: The adapter's Perl script; defaults to the one in the app
    ///     bundle's resources.
    ///   - frameworkURL: The built helper framework; defaults to the one in the
    ///     app bundle's private frameworks.
    init(
        scriptURL: URL? = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
        frameworkURL: URL? = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("MediaRemoteAdapter.framework")
    ) {
        self.scriptURL = scriptURL
        self.frameworkURL = frameworkURL
    }

    func start(onChange: @escaping @MainActor (NowPlayingInfo?) -> Void) {
        guard self.onChange == nil else { return }
        self.onChange = onChange
        failures = 0
        killOrphanedStreams()
        launch()
    }

    func stop() {
        guard onChange != nil else { return }
        onChange = nil
        generation += 1
        relaunchTask?.cancel()
        relaunchTask = nil
        terminateProcess()
        lastDelivered = nil
    }

    func send(_ command: NowPlayingCommand) {
        guard let scriptURL, let frameworkURL else { return }
        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = [scriptURL.path, frameworkURL.path, "send", String(command.rawValue)]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: Private

    /// Terminates stream processes left behind by an Earshot that did not quit
    /// gracefully (crash, SIGKILL, a test host). They were reparented to launchd
    /// (PID 1) and would otherwise linger until their next write fails.
    private func killOrphanedStreams() {
        guard let scriptURL else { return }
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-P", "1", "-f", "\(scriptURL.path) .* stream"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        do {
            try pkill.run()
            pkill.waitUntilExit()
        } catch {}
    }

    /// Starts the streaming process, or reports `nil` when it cannot run.
    private func launch() {
        guard let scriptURL, let frameworkURL, onChange != nil else {
            deliver(nil)
            return
        }

        generation += 1
        let current = generation
        let reader = StreamReader(
            onValidLine: { [weak self] in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.sawValidLine(generation: current) }
                }
            },
            onChange: { [weak self] info in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.deliver(info, generation: current) }
                }
            }
        )

        let stdout = Pipe()
        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = [scriptURL.path, frameworkURL.path, "stream", "--debounce=100"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.processEnded(generation: current) }
            }
        }
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            reader.queue.async { reader.handle(data) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            deliver(nil)
            scheduleRelaunch()
        }
    }

    /// Clears the handlers and terminates the streaming process, if any.
    private func terminateProcess() {
        guard let process else { return }
        self.process = nil
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    /// The stream produced a valid line: the adapter works, so reset the backoff.
    private func sawValidLine(generation: Int) {
        guard generation == self.generation else { return }
        failures = 0
    }

    /// The streaming process exited while the source was started.
    private func processEnded(generation: Int) {
        guard generation == self.generation, onChange != nil else { return }
        terminateProcess()
        deliver(nil)
        scheduleRelaunch()
    }

    /// Relaunches after an exponentially growing delay, or gives up silently
    /// after too many failures in a row.
    private func scheduleRelaunch() {
        failures += 1
        guard failures < Self.maxFailures else { return }
        var delay = Self.initialRelaunchDelay
        for _ in 1..<failures {
            delay = min(delay * 2, Self.maxRelaunchDelay)
        }
        relaunchTask?.cancel()
        relaunchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func deliver(_ info: NowPlayingInfo?, generation: Int) {
        guard generation == self.generation else { return }
        deliver(info)
    }

    /// Reports `info` unless it equals the last reported value.
    private func deliver(_ info: NowPlayingInfo?) {
        guard let onChange, info != lastDelivered else { return }
        lastDelivered = info
        onChange(info)
    }
}
