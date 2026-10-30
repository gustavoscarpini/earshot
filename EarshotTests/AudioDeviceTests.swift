import Testing
@testable import Earshot

struct AudioDeviceTests {
    private func device(_ name: String, _ transport: AudioTransport) -> AudioDevice {
        AudioDevice(uid: name, name: name, transport: transport)
    }

    @Test(arguments: [
        (AudioTransport.builtIn, "Built-in"),
        (.usb, "USB"),
        (.bluetooth, "Bluetooth"),
        (.bluetoothLE, "Bluetooth"),
        (.hdmi, "HDMI"),
        (.displayPort, "DisplayPort"),
        (.airPlay, "AirPlay"),
        (.thunderbolt, "Thunderbolt"),
        (.virtual, "Virtual"),
        (.aggregate, "Aggregate"),
        (.other, "Other")
    ])
    func subtitleKeyPerTransport(transport: AudioTransport, key: String) {
        #expect(device("Device", transport).subtitleKey == key)
    }

    @Test func builtInSymbolDependsOnDirection() {
        let builtIn = device("MacBook Pro Speakers", .builtIn)
        #expect(builtIn.symbolName(for: .output) == "laptopcomputer")
        #expect(builtIn.symbolName(for: .input) == "mic")
    }

    @Test func airPodsNameWinsOverTheBluetoothHeadphones() {
        #expect(device("Alex's AirPods Pro", .bluetooth).symbolName(for: .output) == "airpodspro")
        #expect(device("Alex's AirPods Pro", .bluetoothLE).symbolName(for: .input) == "airpodspro")
        #expect(device("WH-1000XM5", .bluetooth).symbolName(for: .output) == "headphones")
        #expect(device("WH-1000XM5", .bluetoothLE).symbolName(for: .input) == "headphones")
    }

    @Test func iPhoneNameGetsThePhoneSymbol() {
        #expect(device("Alex's iPhone Microphone", .other).symbolName(for: .input) == "iphone")
    }

    @Test func usbSymbol() {
        #expect(device("DAC", .usb).symbolName(for: .output) == "cable.connector")
        #expect(device("Mic", .usb).symbolName(for: .input) == "cable.connector")
    }

    @Test(arguments: [AudioTransport.hdmi, .displayPort, .thunderbolt])
    func displayTransportsAreDisplaysOnlyAsOutputs(transport: AudioTransport) {
        #expect(device("Monitor", transport).symbolName(for: .output) == "display")
        #expect(device("Monitor", transport).symbolName(for: .input) == "mic")
    }

    @Test func airPlaySymbol() {
        #expect(device("HomePod", .airPlay).symbolName(for: .output) == "airplayaudio")
    }

    @Test func virtualAndAggregateSymbol() {
        #expect(device("Loopback", .virtual).symbolName(for: .output) == "waveform.circle")
        #expect(device("Combo", .aggregate).symbolName(for: .input) == "waveform.circle")
    }

    @Test func otherSymbolDependsOnDirection() {
        #expect(device("Thing", .other).symbolName(for: .output) == "speaker.wave.2")
        #expect(device("Thing", .other).symbolName(for: .input) == "mic")
    }
}
