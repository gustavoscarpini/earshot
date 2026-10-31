import CoreAudio
import Darwin
import Foundation
import os

/// The Core Audio implementation of `TapController`.
///
/// Each tapped app gets a `ProcessTap`: a private process tap whose audio is
/// read by a private aggregate device built on the current default output, so
/// the app's own output is muted while Earshot plays it back with gain
/// (`muteBehavior = .mutedWhenTapped`, DESIGN §1). When the default output
/// changes, every tap is torn down and rebuilt against the new device
/// (DESIGN §3).
///
/// A software master below 100% adds one more `ProcessTap`, the global tap: it
/// captures every process except the individually tapped apps and Earshot
/// itself, whose playback would otherwise be captured again in a feedback loop
/// (DESIGN §9).
@MainActor
final class CoreAudioTapController: TapController {
    private static let logger = Logger(subsystem: "com.gustavoscarpini.Earshot", category: "taps")
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// The taps that exist right now, with the spec each was built from.
    private var active: [String: (spec: TapSpec, tap: ProcessTap)] = [:]

    /// The meter-only taps that exist right now (DESIGN §14).
    private var activeMeters: [String: (spec: MeterSpec, tap: ProcessTap)] = [:]

    /// The global tap, if one exists, with the spec it was built from.
    private var activeGlobal: (spec: GlobalTapSpec, tap: ProcessTap)?

    /// The last desired state, replayed when the output device changes.
    private var desired = TapPlan(perApp: [:], global: nil)

    /// The UID of the output device the taps play to.
    private var outputUID: String?

    private var defaultOutputListener: AudioObjectPropertyListenerBlock?

    init() {
        outputUID = Self.defaultOutputDeviceUID()

        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.defaultOutputChanged()
            }
        }
        if AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, DispatchQueue.main, listener) == noErr {
            defaultOutputListener = listener
        } else {
            Self.logger.error("Could not observe the default output device; taps will not follow device changes")
        }
    }

    // MARK: TapController

    func apply(_ plan: TapPlan) {
        desired = plan

        // Meter-only taps that go away (or change) are destroyed before the
        // per-app taps are touched, and new ones are built only after, so an
        // app never has a meter tap and a volume tap at once (DESIGN §14).
        let meterChanges = TapReconciler.meterChanges(current: activeMeters.mapValues(\.spec), desired: plan.meters)
        for change in meterChanges {
            switch change {
            case .destroy(let id), .recreate(let id, _):
                activeMeters.removeValue(forKey: id)?.tap.destroy()
            case .create:
                break
            }
        }

        // Per-app changes, then the meters, then the global tap.
        let current = active.mapValues(\.spec)
        for change in TapReconciler.changes(current: current, desired: plan.perApp) {
            switch change {
            case .destroy(let id):
                active.removeValue(forKey: id)?.tap.destroy()
            case .updateGain(let id, let gain):
                guard let entry = active[id] else { continue }
                entry.tap.setGain(gain)
                active[id] = (TapSpec(processObjectIDs: entry.spec.processObjectIDs, gain: gain), entry.tap)
            case .create(let id, let spec):
                build(id: id, spec: spec)
            case .recreate(let id, let spec):
                active.removeValue(forKey: id)?.tap.destroy()
                build(id: id, spec: spec)
            }
        }

        for change in meterChanges {
            switch change {
            case .create(let id, let spec), .recreate(let id, let spec):
                buildMeter(id: id, spec: spec)
            case .destroy:
                break
            }
        }

        applyGlobal(plan.global)
    }

    func peaks() -> [String: Float] {
        var result: [String: Float] = [:]
        for (id, entry) in activeMeters {
            result[id] = entry.tap.peak
        }
        for (id, entry) in active {
            result[id] = entry.tap.peak
        }
        return result
    }

    // MARK: Private

    private func build(id: String, spec: TapSpec) {
        guard let outputUID else {
            Self.logger.error("No default output device; cannot tap \(id, privacy: .public)")
            return
        }
        do {
            let description = CATapDescription(stereoMixdownOfProcesses: spec.processObjectIDs.map { AudioObjectID($0) })
            let tap = try ProcessTap(description: description, outputDeviceUID: outputUID, mode: .playback(gain: spec.gain))
            active[id] = (spec, tap)
        } catch {
            Self.logger.error("Could not tap \(id, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Builds a meter-only tap. Earshot's own process object is never tapped
    /// (it would meter Earshot's own playback), and an app left with no process
    /// object gets no meter.
    private func buildMeter(id: String, spec: MeterSpec) {
        guard let outputUID else { return }
        let own = Self.ownProcessObjectID()
        let objects = spec.processObjectIDs.filter { $0 != own }
        guard !objects.isEmpty else { return }
        do {
            let description = CATapDescription(stereoMixdownOfProcesses: objects.map { AudioObjectID($0) })
            let tap = try ProcessTap(description: description, outputDeviceUID: outputUID, mode: .meterOnly)
            activeMeters[id] = (spec, tap)
        } catch {
            Self.logger.info("Could not meter \(id, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Reconciles the global tap with `desired`.
    ///
    /// Earshot's own process object is appended to the exclusion list, so the
    /// global tap never captures Earshot's own playback (including its own) —
    /// that would be a feedback loop. Earshot gets a process object as soon as
    /// it talks to the HAL, but if it cannot be resolved the global tap is not
    /// built at all and is retried on the next call.
    private func applyGlobal(_ desired: GlobalTapSpec?) {
        var desired = desired
        if let spec = desired {
            if let own = Self.ownProcessObjectID() {
                desired = GlobalTapSpec(excludedProcessObjectIDs: spec.excludedProcessObjectIDs + [own], gain: spec.gain)
            } else {
                Self.logger.error("Earshot's own process object is unknown; skipping the global tap")
                desired = nil
            }
        }

        switch TapReconciler.globalChange(current: activeGlobal?.spec, desired: desired) {
        case nil:
            break
        case .destroy:
            activeGlobal?.tap.destroy()
            activeGlobal = nil
        case .updateGain(let gain):
            guard let entry = activeGlobal else { return }
            entry.tap.setGain(gain)
            activeGlobal = (GlobalTapSpec(excludedProcessObjectIDs: entry.spec.excludedProcessObjectIDs, gain: gain), entry.tap)
        case .create(let spec):
            buildGlobal(spec)
        case .recreate(let spec):
            activeGlobal?.tap.destroy()
            activeGlobal = nil
            buildGlobal(spec)
        }
    }

    private func buildGlobal(_ spec: GlobalTapSpec) {
        guard let outputUID else {
            Self.logger.error("No default output device; cannot build the global tap")
            return
        }
        do {
            let description = CATapDescription(
                stereoGlobalTapButExcludeProcesses: spec.excludedProcessObjectIDs.map { AudioObjectID($0) }
            )
            let tap = try ProcessTap(description: description, outputDeviceUID: outputUID, mode: .playback(gain: spec.gain))
            activeGlobal = (spec, tap)
        } catch {
            Self.logger.error("Could not build the global tap: \(error, privacy: .public)")
        }
    }

    private func defaultOutputChanged() {
        let uid = Self.defaultOutputDeviceUID()
        guard uid != outputUID else { return }
        outputUID = uid

        for entry in active.values {
            entry.tap.destroy()
        }
        active.removeAll()
        for entry in activeMeters.values {
            entry.tap.destroy()
        }
        activeMeters.removeAll()
        activeGlobal?.tap.destroy()
        activeGlobal = nil
        apply(desired)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Earshot's own Core Audio process object, or `nil` while the HAL has none
    /// for this process yet (it appears once Earshot starts playing audio).
    private static func ownProcessObjectID() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            systemObject,
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &object
        )
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }

    /// The UID of the system default output device, if any.
    private static func defaultOutputDeviceUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else {
            return nil
        }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
}

/// A failed Core Audio call.
struct CoreAudioError: Error, CustomStringConvertible {
    let operation: String
    let status: OSStatus

    var description: String { "\(operation) failed (OSStatus \(status))" }
}

/// One tap: process tap → private aggregate device → IOProc.
///
/// In `.playback` mode the IOProc applies the gain and plays to the output; in
/// `.meterOnly` mode (DESIGN §14) the tap is unmuted and the IOProc only
/// measures and writes silence.
///
/// The process tap (per-app, or global with exclusions) delivers stereo and
/// mutes the captured processes' own output while it is being read. The
/// aggregate device uses the output device as its clock and output, with the
/// tap as its input (drift-compensated). The IOProc copies tap input to the
/// output, applying the gain.
private final class ProcessTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let probe = LevelProbe()
    private let renderer: TapRenderer?

    /// What the tap's IOProc does.
    enum Mode {
        /// Mute the app's own output and play it back with this gain.
        case playback(gain: Float)
        /// Leave the app's output alone and only measure it.
        case meterOnly
    }

    /// The latest peak of the audio the IOProc handled (post-gain in playback
    /// mode). Readable from the main actor.
    var peak: Float { probe.value }

    /// - Parameters:
    ///   - description: A ready tap description; name, privacy and mute
    ///     behavior are set here.
    ///   - outputDeviceUID: The output device the aggregate plays to.
    ///   - mode: Playback with a gain, or meter only.
    init(description: CATapDescription, outputDeviceUID: String, mode: Mode) throws {
        switch mode {
        case .playback(let gain):
            renderer = TapRenderer(gain: gain, probe: probe)
            description.muteBehavior = .mutedWhenTapped
        case .meterOnly:
            renderer = nil
            description.muteBehavior = .unmuted
        }

        description.name = "Earshot"
        description.isPrivate = true

        do {
            try Self.check("AudioHardwareCreateProcessTap", AudioHardwareCreateProcessTap(description, &tapID))

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Earshot Tap",
                kAudioAggregateDeviceUIDKey: "com.gustavoscarpini.Earshot.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [
                    [kAudioSubDeviceUIDKey: outputDeviceUID]
                ],
                kAudioAggregateDeviceTapListKey: [
                    [
                        kAudioSubTapDriftCompensationKey: true,
                        kAudioSubTapUIDKey: description.uuid.uuidString
                    ]
                ]
            ]
            try Self.check(
                "AudioHardwareCreateAggregateDevice",
                AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
            )

            if let renderer {
                try Self.check(
                    "AudioDeviceCreateIOProcIDWithBlock",
                    AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                        renderer.render(input: input, output: output)
                    }
                )
            } else {
                let probe = self.probe
                try Self.check(
                    "AudioDeviceCreateIOProcIDWithBlock",
                    AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                        MeterRenderer.measure(input: input, output: output, probe: probe)
                    }
                )
            }
            try Self.check("AudioDeviceStart", AudioDeviceStart(aggregateID, ioProcID))
        } catch {
            destroy()
            throw error
        }
    }

    func setGain(_ gain: Float) {
        renderer?.targetGain = gain
    }

    /// Stops playback and releases every Core Audio object, in reverse order of
    /// creation. Safe to call more than once.
    func destroy() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        destroy()
    }

    private static func check(_ operation: String, _ status: OSStatus) throws {
        guard status == noErr else { throw CoreAudioError(operation: operation, status: status) }
    }
}

/// The real-time part of a tap: copies tap input to the output with gain.
///
/// `render` runs on the HAL I/O thread, so it never allocates, locks or logs.
/// The gain target is written from the main actor and read on the I/O thread
/// through a raw pointer: an aligned 32-bit store is atomic on Apple platforms,
/// and a stale read only delays a change by one buffer. Gain changes are ramped
/// linearly across a buffer to avoid zipper noise.
private final class TapRenderer: @unchecked Sendable {
    private let target: UnsafeMutablePointer<Float32>
    private let probe: LevelProbe

    /// The gain at the end of the previous buffer. I/O thread only.
    private var current: Float32

    init(gain: Float, probe: LevelProbe) {
        self.probe = probe
        target = .allocate(capacity: 1)
        target.initialize(to: gain)
        current = gain
    }

    deinit {
        target.deallocate()
    }

    var targetGain: Float {
        get { target.pointee }
        set { target.pointee = newValue }
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)

        // Locate the left and right input channels, interleaved or not. A mono
        // input feeds both sides.
        var left: UnsafePointer<Float32>?
        var right: UnsafePointer<Float32>?
        var leftStride = 1
        var rightStride = 1
        var frames = 0
        for buffer in inputs {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let channels = Int(buffer.mNumberChannels)
            let samples = UnsafePointer(data.assumingMemoryBound(to: Float32.self))
            let bufferFrames = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channels)
            if left == nil {
                left = samples
                leftStride = channels
                frames = bufferFrames
                if channels > 1 {
                    right = samples + 1
                    rightStride = channels
                }
            } else if right == nil {
                right = samples
                rightStride = channels
                frames = min(frames, bufferFrames)
            }
        }
        if right == nil {
            right = left
            rightStride = leftStride
        }

        let start = current
        let end = target.pointee
        let totalOutputChannels = outputs.reduce(0) { $0 + Int($1.mNumberChannels) }

        // Write left/right to the first two output channels across buffers
        // (downmixed when the output is mono); silence everything else.
        var channelOffset = 0
        var peak: Float32 = 0
        for buffer in outputs {
            guard let data = buffer.mData else { continue }
            memset(data, 0, Int(buffer.mDataByteSize))
            let channels = Int(buffer.mNumberChannels)
            defer { channelOffset += channels }
            guard let left, let right, channels > 0, channelOffset < 2 else { continue }

            let samples = data.assumingMemoryBound(to: Float32.self)
            let count = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * channels))
            guard count > 0 else { continue }
            let step = (end - start) / Float32(count)

            for channel in 0..<channels where channelOffset + channel < 2 {
                let isLeft = channelOffset + channel == 0
                for frame in 0..<count {
                    let gain = start + step * Float32(frame + 1)
                    let l = left[frame * leftStride]
                    let r = right[frame * rightStride]
                    let sample: Float32
                    if totalOutputChannels == 1 {
                        sample = (l + r) * 0.5
                    } else {
                        sample = isLeft ? l : r
                    }
                    let scaled = sample * gain
                    samples[frame * channels + channel] = scaled
                    peak = max(peak, abs(scaled))
                }
            }
        }

        current = end
        probe.publish(peak: peak, frames: frames)
    }
}

/// A peak value shared between the HAL I/O thread (one writer) and the main
/// actor (readers), without locks.
///
/// The I/O thread keeps a decaying peak hold (`held`, I/O thread only), so a
/// 25 Hz poll does not miss the peaks of the ~100 buffers per second it skips,
/// and publishes it as the bit pattern of a `Float` with one aligned 32-bit
/// store. The main actor does one aligned 32-bit load. That is atomic on arm64
/// and x86-64, there is exactly one writer, and a stale read only delays the
/// meter by one buffer, the same justification as `TapRenderer.target`. A lock
/// (`os_unfair_lock`) would risk priority inversion on the I/O thread, and
/// `Synchronization.Atomic` needs macOS 15.
final class LevelProbe: @unchecked Sendable {
    /// Frames over which the hold falls by a factor of e (~50 ms at 48 kHz).
    private static let releaseFrames: Float = 2_400

    private let storage: UnsafeMutablePointer<UInt32>
    private var held: Float32 = 0

    init() {
        storage = .allocate(capacity: 1)
        storage.initialize(to: 0)
    }

    deinit {
        storage.deallocate()
    }

    /// The last published peak, `0...`. Any thread.
    var value: Float { Float(bitPattern: storage.pointee) }

    /// Folds in the peak of one buffer. I/O thread only; does not allocate or lock.
    func publish(peak: Float32, frames: Int) {
        let decay = expf(-Float(frames) / Self.releaseFrames)
        var next = max(peak, held * decay)
        if next < 1e-6 { next = 0 }
        held = next
        storage.pointee = next.bitPattern
    }
}

/// The real-time part of a meter-only tap: measures the input, writes silence.
///
/// Runs on the HAL I/O thread, so it never allocates, locks or logs.
private enum MeterRenderer {
    static func measure(
        input: UnsafePointer<AudioBufferList>,
        output: UnsafeMutablePointer<AudioBufferList>,
        probe: LevelProbe
    ) {
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }

        var peak: Float32 = 0
        var frames = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
            guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let samples = data.assumingMemoryBound(to: Float32.self)
            for index in 0..<count {
                peak = max(peak, abs(samples[index]))
            }
            if frames == 0 { frames = count / Int(buffer.mNumberChannels) }
        }
        probe.publish(peak: peak, frames: frames)
    }
}
