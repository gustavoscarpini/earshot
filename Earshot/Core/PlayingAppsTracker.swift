import Foundation

/// One app shown in the "Apps" section of the panel.
///
/// An app that stops playing stays in the list for a short while, dimmed,
/// before disappearing, so controls do not vanish under the cursor on pause
/// (DESIGN §4).
struct PlayingApp: Equatable, Identifiable, Sendable {
    /// The grouping key: the parent app bundle path, else the bundle
    /// identifier, else `"pid:<pid>"` (DESIGN §5).
    let id: String

    /// The user-visible app name.
    var name: String

    /// Whether the app is producing audio right now. `false` means it is
    /// lingering (shown dimmed) after it stopped.
    var isPlaying: Bool

    /// When the app was last seen producing audio.
    var lastPlayedAt: Date
}

/// Tracks which apps are playing, applying the 10-second linger rule.
///
/// Pure value type, no Core Audio dependency, so it is fully unit-testable.
/// The UI drives it with `update` on a one-second timer; an app that is no
/// longer in `playing` is kept, dimmed, for `lingerDuration` after it stopped
/// and then removed (DESIGN §4).
struct PlayingAppsTracker {
    /// How long a stopped app lingers in the list before being removed.
    static let lingerDuration: TimeInterval = 10

    /// The tracked apps, sorted by name, case-insensitively.
    private(set) var apps: [PlayingApp] = []

    /// Reconciles the tracked apps with the apps playing right now.
    ///
    /// Apps in `playing` are marked playing with `lastPlayedAt = now` (and
    /// added when new); apps that were tracked but are absent are marked not
    /// playing and removed once they have lingered for `lingerDuration`.
    /// Calling this with the same `playing` and a later `now` still prunes
    /// entries whose linger window has expired.
    ///
    /// - Parameters:
    ///   - playing: Apps whose output is running right now, already grouped so
    ///     there is one entry per id.
    ///   - now: The current time.
    mutating func update(playing: [(id: String, name: String)], now: Date) {
        let playingByName = Dictionary(
            playing.map { ($0.id, $0.name) },
            uniquingKeysWith: { _, latest in latest }
        )
        let trackedIDs = Set(apps.map(\.id))

        var updated = apps.map { app -> PlayingApp in
            var app = app
            if let name = playingByName[app.id] {
                app.name = name
                app.isPlaying = true
                app.lastPlayedAt = now
            } else {
                app.isPlaying = false
            }
            return app
        }

        for entry in playing where !trackedIDs.contains(entry.id) {
            updated.append(PlayingApp(id: entry.id, name: entry.name, isPlaying: true, lastPlayedAt: now))
        }

        updated.removeAll { app in
            !app.isPlaying && now.timeIntervalSince(app.lastPlayedAt) >= Self.lingerDuration
        }
        updated.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        apps = updated
    }
}
