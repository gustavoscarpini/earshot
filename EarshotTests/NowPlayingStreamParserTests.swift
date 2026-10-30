import Foundation
import Testing
@testable import Earshot

struct NowPlayingStreamParserTests {
    private func line(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func full(_ payload: String) -> Data {
        line(#"{"type":"data","diff":false,"payload":\#(payload)}"#)
    }

    private func diff(_ payload: String) -> Data {
        line(#"{"type":"data","diff":true,"payload":\#(payload)}"#)
    }

    private let spotify = #"{"bundleIdentifier":"com.spotify.client","title":"Xote","artist":"Triii","album":"Album","playing":true}"#

    @Test func fullPayloadProducesInfo() {
        var parser = NowPlayingStreamParser()
        let update = parser.consume(line: full(spotify))

        #expect(update == .state(NowPlayingInfo(
            bundleID: "com.spotify.client",
            title: "Xote",
            artist: "Triii",
            album: "Album",
            isPlaying: true
        )))
    }

    @Test func parentBundleIDIsRead() {
        var parser = NowPlayingStreamParser()
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","title":"T","playing":false}"#
        ))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.parentBundleID == "com.apple.Safari")
        #expect(!info.isPlaying)
    }

    @Test func emptyFullPayloadMeansNothingPlaying() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))

        #expect(parser.consume(line: full("{}")) == .state(nil))
    }

    @Test func diffUpdatesPlayingAndKeepsTheRest() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))
        let update = parser.consume(line: diff(#"{"playing":false}"#))

        #expect(update == .state(NowPlayingInfo(
            bundleID: "com.spotify.client",
            title: "Xote",
            artist: "Triii",
            album: "Album",
            isPlaying: false
        )))
    }

    @Test func diffWithNullRemovesAKey() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))
        let update = parser.consume(line: diff(#"{"artist":null}"#))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.artist == nil)
        #expect(info.title == "Xote")
    }

    @Test func diffWithNewTitle() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))
        let update = parser.consume(line: diff(#"{"title":"Other"}"#))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.title == "Other")
        #expect(info.artist == "Triii")
    }

    @Test func missingMandatoryKeyMeansNothingPlaying() {
        var parser = NowPlayingStreamParser()
        #expect(parser.consume(line: full(#"{"title":"T","playing":true}"#)) == .state(nil))
        #expect(parser.consume(line: full(#"{"bundleIdentifier":"a","playing":true}"#)) == .state(nil))
        #expect(parser.consume(line: full(#"{"bundleIdentifier":"a","title":"T"}"#)) == .state(nil))

        _ = parser.consume(line: full(spotify))
        #expect(parser.consume(line: diff(#"{"title":null}"#)) == .state(nil))
    }

    @Test func invalidJSONLeavesStateUnchanged() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))

        #expect(parser.consume(line: line("not json")) == .ignored)
        #expect(parser.consume(line: line("[1,2]")) == .ignored)

        // The state survived: a diff still applies on top of it.
        let update = parser.consume(line: diff(#"{"playing":false}"#))
        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.title == "Xote")
    }

    @Test func nonDataTypeLeavesStateUnchanged() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))

        #expect(parser.consume(line: line(#"{"type":"error","diff":false,"payload":{}}"#)) == .ignored)

        let update = parser.consume(line: diff(#"{"playing":false}"#))
        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.title == "Xote")
    }

    @Test func artworkIsDecodedFromBase64() {
        var parser = NowPlayingStreamParser()
        let bytes = Data([1, 2, 3, 4])
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"a","title":"T","playing":true,"artworkData":"\#(bytes.base64EncodedString())"}"#
        ))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.artworkData == bytes)

        // A diff that does not touch the artwork keeps it.
        let next = parser.consume(line: diff(#"{"playing":false}"#))
        guard case .state(let kept?) = next else {
            Issue.record("expected info")
            return
        }
        #expect(kept.artworkData == bytes)
    }

    @Test func emptyArtistBecomesNil() {
        var parser = NowPlayingStreamParser()
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"a","title":"T","playing":true,"artist":"","album":""}"#
        ))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.artist == nil)
        #expect(info.album == nil)
    }

    @Test func freshFullPayloadReplacesPreviousState() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(spotify))
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"b","title":"New","playing":true}"#
        ))

        #expect(update == .state(NowPlayingInfo(bundleID: "b", title: "New", isPlaying: true)))
    }

    // MARK: Progress

    @Test func progressKeysAreParsed() {
        var parser = NowPlayingStreamParser()
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"a","title":"T","playing":true,"duration":215.5,"elapsedTime":42,"timestamp":"2026-10-30T00:14:23Z","playbackRate":1.5}"#
        ))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.duration == 215.5)
        #expect(info.elapsedTime == 42)
        #expect(info.playbackRate == 1.5)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_793_319_263))
    }

    @Test func timestampAcceptsFractionalSeconds() {
        var parser = NowPlayingStreamParser()
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"a","title":"T","playing":true,"timestamp":"2026-10-30T00:14:23.250Z"}"#
        ))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_793_319_263.25))
    }

    @Test func missingOrInvalidProgressKeysAreNil() {
        var parser = NowPlayingStreamParser()
        let update = parser.consume(line: full(
            #"{"bundleIdentifier":"a","title":"T","playing":true,"timestamp":"yesterday"}"#
        ))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.duration == nil)
        #expect(info.elapsedTime == nil)
        #expect(info.timestamp == nil)
        #expect(info.playbackRate == nil)
    }

    @Test func diffUpdatesElapsedAndTimestamp() {
        var parser = NowPlayingStreamParser()
        _ = parser.consume(line: full(
            #"{"bundleIdentifier":"a","title":"T","playing":true,"duration":100,"elapsedTime":1,"timestamp":"2026-10-30T00:14:23Z"}"#
        ))
        let update = parser.consume(line: diff(#"{"elapsedTime":30,"timestamp":"2026-10-30T00:14:52Z"}"#))

        guard case .state(let info?) = update else {
            Issue.record("expected info")
            return
        }
        #expect(info.duration == 100)
        #expect(info.elapsedTime == 30)
        #expect(info.timestamp == Date(timeIntervalSince1970: 1_793_319_292))
    }
}
