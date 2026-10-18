import Foundation
import Testing
@testable import Earshot

struct AppGroupingTests {
    @Test func groupsChromeHelperUnderOutermostApp() {
        let path = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/131/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"

        #expect(AppGrouping.outermostAppBundlePath(forExecutablePath: path) == "/Applications/Google Chrome.app")
    }

    @Test func plainAppExecutableResolvesToTheAppBundle() {
        #expect(AppGrouping.outermostAppBundlePath(forExecutablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify") == "/Applications/Spotify.app")
    }

    @Test func nonAppExecutableHasNoBundlePath() {
        #expect(AppGrouping.outermostAppBundlePath(forExecutablePath: "/usr/libexec/coreaudiod") == nil)
    }

    @Test func nestedHelpersInUserApplicationsGroupUnderOutermostApp() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/Applications/Foo.app/Contents/Frameworks/Bar Helper.app/Contents/MacOS/Bar Helper"

        #expect(AppGrouping.outermostAppBundlePath(forExecutablePath: path) == "\(home)/Applications/Foo.app")
    }

    @Test func appExtensionOrFrameworkOnlyPathHasNoAppBundle() {
        #expect(AppGrouping.outermostAppBundlePath(forExecutablePath: "/Applications/Foo.appex/Contents/MacOS/Foo") == nil)
        #expect(AppGrouping.outermostAppBundlePath(forExecutablePath: "/Library/Frameworks/Foo.framework/Versions/A/Foo") == nil)
    }
}
