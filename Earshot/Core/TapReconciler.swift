import Foundation

/// What a single app's tap should look like.
struct TapSpec: Equatable, Sendable {
    /// The Core Audio process objects mixed into the tap, sorted ascending.
    let processObjectIDs: [UInt32]

    /// The linear gain applied to the tapped audio, `0...1`.
    let gain: Float

    init(processObjectIDs: [UInt32], gain: Float) {
        self.processObjectIDs = processObjectIDs.sorted()
        self.gain = gain
    }
}

/// One step needed to move the active taps to the desired ones.
enum TapChange: Equatable, Sendable {
    /// No tap exists for the app yet.
    case create(id: String, spec: TapSpec)
    /// The app's process set changed (e.g. a new helper started), so its tap
    /// must be torn down and built again.
    case recreate(id: String, spec: TapSpec)
    /// Only the gain changed; the tap stays in place.
    case updateGain(id: String, gain: Float)
    /// The app no longer needs a tap.
    case destroy(id: String)
}

/// Diffs the active taps against the desired ones.
///
/// Pure logic, no Core Audio dependency, so it is fully unit-testable. The Core
/// Audio tap controller executes the returned changes (DESIGN §9).
enum TapReconciler {
    /// The changes that turn `current` into `desired`, destroys first, then the
    /// rest, each group ordered by app id so the result is deterministic.
    static func changes(current: [String: TapSpec], desired: [String: TapSpec]) -> [TapChange] {
        let destroys = current.keys
            .filter { desired[$0] == nil }
            .sorted()
            .map { TapChange.destroy(id: $0) }

        let others = desired.keys.sorted().compactMap { id -> TapChange? in
            let spec = desired[id]!
            guard let active = current[id] else { return .create(id: id, spec: spec) }
            if active.processObjectIDs != spec.processObjectIDs { return .recreate(id: id, spec: spec) }
            if active.gain != spec.gain { return .updateGain(id: id, gain: spec.gain) }
            return nil
        }

        return destroys + others
    }
}
