import Foundation

/// Groups helper processes under the app that owns them.
///
/// Browsers, Electron apps and similar software run their audio in helper
/// processes whose executable lives inside nested bundles. Earshot shows one
/// entry per app, so such a process is resolved to the outermost `*.app`
/// directory in its executable path (DESIGN §5).
///
/// Pure logic, no Core Audio dependency, so it is fully unit-testable.
enum AppGrouping {
    /// The path of the outermost `*.app` directory component of `path`.
    ///
    /// - Parameter path: An executable path, which may point inside nested
    ///   helpers of an app bundle.
    /// - Returns: The path up to and including the first (outermost) `*.app`
    ///   component, or `nil` when the path contains none (e.g. a daemon or a
    ///   framework-only path).
    static func outermostAppBundlePath(forExecutablePath path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }

        let bundle = components[...appIndex].joined(separator: "/")
        return path.hasPrefix("/") ? "/" + bundle : bundle
    }
}
