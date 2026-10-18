import Foundation

/// One Core Audio process object.
///
/// Core Audio exposes an object per process that is producing or consuming
/// audio. `AudioProcess` is a plain snapshot of the properties Earshot cares
/// about, decoupled from `AudioObjectID` so the pure core can group and track
/// apps without importing Core Audio (DESIGN §1, §11).
struct AudioProcess: Equatable, Sendable {
    /// The Core Audio process object (`AudioObjectID`), used to build taps.
    let objectID: UInt32

    /// The process identifier.
    let pid: pid_t

    /// The process's bundle identifier, or `nil` when it has none.
    let bundleID: String?

    /// The executable path from `proc_pidpath`, or `nil` when it cannot be read.
    ///
    /// Used to group helper processes under their parent app (DESIGN §5).
    let executablePath: String?

    /// Whether the process is currently producing audio output
    /// (`kAudioProcessPropertyIsRunningOutput`).
    let isRunningOutput: Bool
}
