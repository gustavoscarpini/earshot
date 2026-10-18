import CoreAudio
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
@MainActor
final class CoreAudioTapController: TapController {
    private static let logger = Logger(subsystem: "com.gustavoscarpini.Earshot", category: "taps")
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    /// The taps that exist right now, with the spec each was built from.
    private var active: [String: (spec: TapSpec, tap: ProcessTap)] = [:]

    /// The last desired state, replayed when the output device changes.
    private var desired: [String: TapSpec] = [:]

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

    func apply(_ desired: [String: TapSpec]) {
        self.desired = desired
        let current = active.mapValues(\.spec)

        for change in TapReconciler.changes(current: current, desired: desired) {
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
    }

    // MARK: Private

    private func build(id: String, spec: TapSpec) {
        guard let outputUID else {
            Self.logger.error("No default output device; cannot tap \(id, privacy: .public)")
            return
        }
        do {
            let tap = try ProcessTap(
                processObjectIDs: spec.processObjectIDs,
                outputDeviceUID: outputUID,
                gain: spec.gain
            )
            active[id] = (spec, tap)
        } catch {
            Self.logger.error("Could not tap \(id, privacy: .public): \(error, privacy: .public)")
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
        apply(desired)
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
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

/// One app's tap: process tap → private aggregate device → IOProc with gain.
///
/// The process tap mixes the app's processes to stereo and mutes their own
/// output while it is being read. The aggregate device uses the output device
/// as its clock and output, with the tap as its input (drift-compensated). The
/// IOProc copies tap input to the output, applying the gain.
private final class ProcessTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let renderer: TapRenderer

    init(processObjectIDs: [UInt32], outputDeviceUID: String, gain: Float) throws {
        renderer = TapRenderer(gain: gain)

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs.map { AudioObjectID($0) })
        description.name = "Earshot"
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

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

            let renderer = self.renderer
            try Self.check(
                "AudioDeviceCreateIOProcIDWithBlock",
                AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
                    renderer.render(input: input, output: output)
                }
            )
            try Self.check("AudioDeviceStart", AudioDeviceStart(aggregateID, ioProcID))
        } catch {
            destroy()
            throw error
        }
    }

    func setGain(_ gain: Float) {
        renderer.targetGain = gain
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

    /// The gain at the end of the previous buffer. I/O thread only.
    private var current: Float32

    init(gain: Float) {
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
                    samples[frame * channels + channel] = sample * gain
                }
            }
        }

        current = end
    }
}
