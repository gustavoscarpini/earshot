import Foundation

/// Which side of the hardware an audio device list or control refers to.
enum AudioDirection: Sendable {
    /// Capture devices (microphones).
    case input

    /// Playback devices (speakers, headphones, displays).
    case output
}

/// One audio device, as shown in the output or input picker.
///
/// A plain snapshot decoupled from `AudioObjectID`, so the pure core and the
/// UI never import Core Audio (DESIGN §2, §3).
struct AudioDevice: Equatable, Identifiable, Sendable {
    /// The device's persistent Core Audio UID.
    let uid: String

    /// The user-visible device name.
    let name: String

    var id: String { uid }
}
