import Foundation

/// Which side of the hardware an audio device list or control refers to.
enum AudioDirection: Sendable {
    /// Capture devices (microphones).
    case input

    /// Playback devices (speakers, headphones, displays).
    case output
}

/// How an audio device is connected to the Mac.
///
/// A plain mirror of Core Audio's transport types, decoupled from the HAL's
/// four-character codes so the pure core and the UI never import Core Audio.
enum AudioTransport: Equatable, Sendable {
    /// Built into the Mac (speakers, internal microphone).
    case builtIn

    /// Connected over USB.
    case usb

    /// Classic Bluetooth.
    case bluetooth

    /// Bluetooth Low Energy.
    case bluetoothLE

    /// An HDMI display or receiver.
    case hdmi

    /// A DisplayPort display.
    case displayPort

    /// An AirPlay receiver.
    case airPlay

    /// Connected over Thunderbolt.
    case thunderbolt

    /// A software device, such as a loopback driver.
    case virtual

    /// An aggregate or multi-output device.
    case aggregate

    /// Any other or unknown transport.
    case other
}

/// One audio device, as shown in the output or input device cards.
///
/// A plain snapshot decoupled from `AudioObjectID`, so the pure core and the
/// UI never import Core Audio (DESIGN §2, §3).
struct AudioDevice: Equatable, Identifiable, Sendable {
    /// The device's persistent Core Audio UID.
    let uid: String

    /// The user-visible device name.
    let name: String

    /// How the device is connected.
    let transport: AudioTransport

    var id: String { uid }

    /// The String Catalog key of the transport label shown under the name
    /// ("Built-in", "USB", "Bluetooth", ...).
    var subtitleKey: String {
        switch transport {
        case .builtIn: "Built-in"
        case .usb: "USB"
        case .bluetooth, .bluetoothLE: "Bluetooth"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .airPlay: "AirPlay"
        case .thunderbolt: "Thunderbolt"
        case .virtual: "Virtual"
        case .aggregate: "Aggregate"
        case .other: "Other"
        }
    }

    /// The SF Symbol shown on the device's card.
    ///
    /// - Parameter direction: Whether the device is listed as an output or an
    ///   input; displays only make sense as outputs.
    func symbolName(for direction: AudioDirection) -> String {
        let isOutput = direction == .output
        if transport == .builtIn {
            return isOutput ? "laptopcomputer" : "mic"
        }
        if name.localizedCaseInsensitiveContains("AirPods") {
            return "airpodspro"
        }
        if name.localizedCaseInsensitiveContains("iPhone") {
            return "iphone"
        }
        switch transport {
        case .bluetooth, .bluetoothLE:
            return "headphones"
        case .usb:
            return "cable.connector"
        case .hdmi, .displayPort, .thunderbolt:
            return isOutput ? "display" : "mic"
        case .airPlay:
            return "airplayaudio"
        case .virtual, .aggregate:
            return "waveform.circle"
        case .builtIn, .other:
            return isOutput ? "speaker.wave.2" : "mic"
        }
    }
}
