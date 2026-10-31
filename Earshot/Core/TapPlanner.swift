import Foundation

/// One app as the planner sees it.
struct TapPlanInput: Equatable, Sendable {
    /// The app id (same key as `PlayingApp.id`).
    let id: String

    /// The per-app volume, `0...1`.
    let volume: Float

    /// Whether the app is muted.
    let muted: Bool

    /// Every Core Audio process object of the app.
    let processObjectIDs: [UInt32]
}

/// Every tap that should exist: one per adjusted app plus, optionally, the
/// single global tap.
struct TapPlan: Equatable, Sendable {
    /// The per-app taps, keyed by app id.
    let perApp: [String: TapSpec]

    /// The global tap for the software master, or `nil` when none is needed.
    let global: GlobalTapSpec?

    /// The meter-only taps (DESIGN §14), keyed by app id.
    let meters: [String: MeterSpec]

    init(perApp: [String: TapSpec], global: GlobalTapSpec?, meters: [String: MeterSpec] = [:]) {
        self.perApp = perApp
        self.global = global
        self.meters = meters
    }
}

/// Decides every tap in one place (DESIGN §9).
///
/// Pure logic, no Core Audio dependency, so it is fully unit-testable.
enum TapPlanner {
    /// Builds the tap plan.
    ///
    /// An app is tapped when `TapPolicy.needsTap` says so and it has at least
    /// one process object; its gain is `app * softwareMaster`, or `0` when muted.
    /// The global tap exists only when `softwareMaster < 1`, carries that gain,
    /// and excludes every process object of the per-app taps so gain is never
    /// applied twice. Earshot's own process object is added by the tap
    /// controller, not here.
    ///
    /// - Parameters:
    ///   - apps: The apps currently shown.
    ///   - softwareMaster: The software master gain, `0...1`. It is `1` when the
    ///     output has hardware volume (the hardware handles the master then). A
    ///     software mute is expressed as `0`.
    static func plan(apps: [TapPlanInput], softwareMaster: Float) -> TapPlan {
        var perApp: [String: TapSpec] = [:]
        for app in apps {
            guard TapPolicy.needsTap(volume: app.volume, muted: app.muted),
                  !app.processObjectIDs.isEmpty else {
                continue
            }
            perApp[app.id] = TapSpec(
                processObjectIDs: app.processObjectIDs,
                gain: GainCalculator.effectiveGain(app: app.volume, master: softwareMaster, muted: app.muted)
            )
        }

        let global: GlobalTapSpec? = softwareMaster < 1
            ? GlobalTapSpec(
                excludedProcessObjectIDs: Array(Set(perApp.values.flatMap(\.processObjectIDs))),
                gain: softwareMaster
            )
            : nil

        return TapPlan(perApp: perApp, global: global)
    }
}
