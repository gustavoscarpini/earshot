import Foundation

/// One audio output device, as shown in the output picker.
///
/// A plain snapshot decoupled from `AudioObjectID`, so the pure core and the
/// UI never import Core Audio (DESIGN §3).
struct OutputDevice: Equatable, Identifiable, Sendable {
    /// The device's persistent Core Audio UID.
    let uid: String

    /// The user-visible device name.
    let name: String

    var id: String { uid }
}
