import Foundation

/// What a meter-only tap should look like: a read-only tap on an app that has
/// no volume tap, used only to measure its level (DESIGN §14).
struct MeterSpec: Equatable, Sendable {
    /// The Core Audio process objects mixed into the tap, sorted ascending.
    let processObjectIDs: [UInt32]

    init(processObjectIDs: [UInt32]) {
        self.processObjectIDs = processObjectIDs.sorted()
    }
}

/// One step needed to move the active meter taps to the desired ones.
enum MeterChange: Equatable, Sendable {
    /// No meter tap exists for the app yet.
    case create(id: String, spec: MeterSpec)
    /// The app's process set changed, so the meter tap is rebuilt.
    case recreate(id: String, spec: MeterSpec)
    /// The app no longer needs a meter tap.
    case destroy(id: String)
}

/// Decides which apps need a meter-only tap (DESIGN §14).
///
/// Pure logic, no Core Audio dependency.
enum MeterPlanner {
    /// The meter taps that should exist.
    ///
    /// An app gets one only while the panel is visible, it is playing, it has
    /// no volume tap (those are measured by their own IO proc) and it has at
    /// least one process object.
    ///
    /// - Parameters:
    ///   - apps: The apps shown, with the process objects that may be tapped
    ///     (Earshot's own are already left out by the caller).
    ///   - playingIDs: Ids of the apps producing audio right now.
    ///   - volumeTapIDs: Ids that have a per-app volume tap.
    ///   - panelVisible: Whether the panel is on screen.
    static func plan(
        apps: [TapPlanInput],
        playingIDs: Set<String>,
        volumeTapIDs: Set<String>,
        panelVisible: Bool
    ) -> [String: MeterSpec] {
        guard panelVisible else { return [:] }
        var result: [String: MeterSpec] = [:]
        for app in apps
        where playingIDs.contains(app.id) && !volumeTapIDs.contains(app.id) && !app.processObjectIDs.isEmpty {
            result[app.id] = MeterSpec(processObjectIDs: app.processObjectIDs)
        }
        return result
    }
}

extension TapReconciler {
    /// The changes that turn the `current` meter taps into the `desired` ones,
    /// destroys first, each group ordered by app id.
    static func meterChanges(current: [String: MeterSpec], desired: [String: MeterSpec]) -> [MeterChange] {
        let destroys = current.keys.filter { desired[$0] == nil }.sorted().map { MeterChange.destroy(id: $0) }
        let others = desired.keys.sorted().compactMap { id -> MeterChange? in
            let spec = desired[id]!
            guard let active = current[id] else { return .create(id: id, spec: spec) }
            return active == spec ? nil : .recreate(id: id, spec: spec)
        }
        return destroys + others
    }
}
