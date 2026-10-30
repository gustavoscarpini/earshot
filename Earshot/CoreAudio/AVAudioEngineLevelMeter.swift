import AVFoundation
import Foundation
import os

/// The `AVAudioEngine` implementation of `InputLevelMeter`.
///
/// Installs a tap on the engine's input node and reports the peak amplitude of
/// each buffer on the `LevelScale` dB scale. The tap runs on the real-time audio
/// thread, so it only touches a `LevelSink`, which is safe to use from any
/// thread; main-actor state is never read there. The engine is restarted when
/// the default input device changes.
@MainActor
final class AVAudioEngineLevelMeter: InputLevelMeter {
    /// Why the meter could not start.
    enum MeterError: Error {
        /// The user denied (or the system restricts) microphone access.
        case accessDenied
    }

    var onFailure: (@MainActor () -> Void)?

    private var engine: AVAudioEngine?
    private var sink: LevelSink?
    private var configurationObserver: (any NSObjectProtocol)?

    /// The callback of the current run, kept to rebuild the engine on a restart.
    private var onLevel: (@MainActor (Float) -> Void)?

    /// Whether `start(onLevel:)` ran without a matching `stop()`, including while
    /// the permission prompt is showing.
    private var isStarted = false

    /// Bumped by every `start`/`stop`, so a late permission answer from an
    /// earlier run is ignored.
    private var generation = 0

    func start(onLevel: @escaping @MainActor (Float) -> Void) throws {
        guard !isStarted else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            self.onLevel = onLevel
            isStarted = true
            generation += 1
            do {
                try startEngine()
            } catch {
                stop()
                throw error
            }
        case .notDetermined:
            self.onLevel = onLevel
            isStarted = true
            generation += 1
            let expected = generation
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor [weak self] in
                    self?.permissionAnswered(granted: granted, generation: expected)
                }
            }
        default:
            throw MeterError.accessDenied
        }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        generation += 1
        onLevel = nil
        stopEngine()
    }

    // MARK: Private

    /// Continues (or aborts) a start that was waiting for the permission prompt.
    private func permissionAnswered(granted: Bool, generation expected: Int) {
        guard isStarted, generation == expected else { return }
        guard granted else {
            stop()
            onFailure?()
            return
        }
        do {
            try startEngine()
        } catch {
            stop()
            onFailure?()
        }
    }

    /// Builds the engine, installs the tap and starts it.
    private func startEngine() throws {
        guard let onLevel else { return }
        let engine = AVAudioEngine()
        let sink = LevelSink(onLevel: onLevel)
        Self.installTap(on: engine.inputNode, sink: sink)
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            sink.deactivate()
            throw error
        }
        self.engine = engine
        self.sink = sink

        // The default input changed (or its format did): rebuild from scratch,
        // since the tap was installed for the old format.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restart()
            }
        }
    }

    /// Removes the tap, stops the engine and drops the observer.
    private func stopEngine() {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        sink?.deactivate()
        sink = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
    }

    /// Rebuilds the engine after a configuration change.
    private func restart() {
        guard isStarted, engine != nil else { return }
        stopEngine()
        do {
            try startEngine()
        } catch {
            stop()
            onFailure?()
        }
    }

    /// Installs the tap from a nonisolated context, so the closure does not
    /// inherit main-actor isolation: it runs on the audio thread.
    private nonisolated static func installTap(on node: AVAudioInputNode, sink: LevelSink) {
        node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            sink.process(buffer)
        }
    }
}

/// Turns tap buffers into throttled, normalized levels for the main actor.
///
/// Used from the audio thread and the main thread. Its only mutable state is
/// behind an unfair lock, hence `@unchecked Sendable`.
private final class LevelSink: @unchecked Sendable {
    /// The minimum time between two deliveries: about 20 per second.
    private static let minimumInterval: UInt64 = 50_000_000

    private let onLevel: @MainActor (Float) -> Void

    /// The active flag and the uptime (ns) of the last delivery.
    private let state = OSAllocatedUnfairLock(initialState: (isActive: true, lastDelivery: UInt64(0)))

    init(onLevel: @escaping @MainActor (Float) -> Void) {
        self.onLevel = onLevel
    }

    /// Stops all further deliveries, including ones already queued.
    func deactivate() {
        state.withLock { $0.isActive = false }
    }

    /// Computes the buffer's peak and delivers it unless one went out recently.
    /// Runs on the audio thread: no allocation beyond the dispatch, no main-actor
    /// state.
    func process(_ buffer: AVAudioPCMBuffer) {
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldDeliver = state.withLock { state -> Bool in
            guard state.isActive, now &- state.lastDelivery >= Self.minimumInterval else { return false }
            state.lastDelivery = now
            return true
        }
        guard shouldDeliver else { return }

        let level = LevelScale.normalized(peak: Self.peak(of: buffer))
        DispatchQueue.main.async { [self] in
            guard state.withLock({ $0.isActive }) else { return }
            MainActor.assumeIsolated {
                onLevel(level)
            }
        }
    }

    /// The largest absolute sample across all channels of the buffer.
    private static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for frame in 0..<frames {
                peak = max(peak, abs(samples[frame]))
            }
        }
        return peak
    }
}
