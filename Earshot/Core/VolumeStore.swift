import Foundation

/// Remembers per-app volumes across launches, keyed by bundle identifier
/// (DESIGN §5). Mute state is deliberately not stored.
@MainActor
protocol VolumeStore: AnyObject {
    /// The stored volume for `bundleID`, or `nil` when the app was never adjusted.
    func volume(forBundleID bundleID: String) -> Float?

    /// Stores `volume` for `bundleID`. Storing `1.0` forgets the entry, since
    /// unadjusted apps start at 100% anyway.
    func setVolume(_ volume: Float, forBundleID bundleID: String)
}

/// `VolumeStore` backed by `UserDefaults`.
@MainActor
final class UserDefaultsVolumeStore: VolumeStore {
    private static let key = "appVolumes"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func volume(forBundleID bundleID: String) -> Float? {
        (defaults.dictionary(forKey: Self.key)?[bundleID] as? Double).map(Float.init)
    }

    func setVolume(_ volume: Float, forBundleID bundleID: String) {
        var volumes = defaults.dictionary(forKey: Self.key) ?? [:]
        volumes[bundleID] = volume == 1 ? nil : Double(volume)
        defaults.set(volumes, forKey: Self.key)
    }
}
