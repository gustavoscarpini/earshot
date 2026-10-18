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

/// What the single global tap (software master, DESIGN §9) should look like.
struct GlobalTapSpec: Equatable, Sendable {
    /// The Core Audio process objects left out of the tap, sorted ascending:
    /// individually tapped apps (so gain is never applied twice) and Earshot
    /// itself.
    let excludedProcessObjectIDs: [UInt32]

    /// The linear gain applied to the captured audio, `0...1`.
    let gain: Float

    init(excludedProcessObjectIDs: [UInt32], gain: Float) {
        self.excludedProcessObjectIDs = excludedProcessObjectIDs.sorted()
        self.gain = gain
    }
}

/// The one step needed to move the active global tap to the desired one.
enum GlobalTapChange: Equatable, Sendable {
    /// No global tap exists yet.
    case create(GlobalTapSpec)
    /// The exclusion list changed, so the tap must be torn down and built again.
    case recreate(GlobalTapSpec)
    /// Only the gain changed; the tap stays in place.
    case updateGain(Float)
    /// The global tap is no longer needed.
    case destroy
}

extension TapReconciler {
    /// The change that turns the `current` global tap into the `desired` one.
    ///
    /// - Returns: The change to make, or `nil` when there is nothing to do.
    static func globalChange(current: GlobalTapSpec?, desired: GlobalTapSpec?) -> GlobalTapChange? {
        switch (current, desired) {
        case (nil, nil):
            return nil
        case (nil, let desired?):
            return .create(desired)
        case (_?, nil):
            return .destroy
        case (let current?, let desired?):
            if current.excludedProcessObjectIDs != desired.excludedProcessObjectIDs { return .recreate(desired) }
            if current.gain != desired.gain { return .updateGain(desired.gain) }
            return nil
        }
    }
}
