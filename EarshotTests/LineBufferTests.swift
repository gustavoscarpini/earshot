import Foundation
import Testing
@testable import Earshot

struct LineBufferTests {
    private func strings(_ lines: [Data]) -> [String] {
        lines.map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func singleLine() {
        var buffer = LineBuffer()
        #expect(strings(buffer.append(Data("hello\n".utf8))) == ["hello"])
    }

    @Test func multipleLinesInOneChunk() {
        var buffer = LineBuffer()
        #expect(strings(buffer.append(Data("a\nb\nc\n".utf8))) == ["a", "b", "c"])
    }

    @Test func lineSplitAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("hel".utf8)).isEmpty)
        #expect(strings(buffer.append(Data("lo\n".utf8))) == ["hello"])
    }

    @Test func trailingPartialIsKept() {
        var buffer = LineBuffer()
        #expect(strings(buffer.append(Data("one\ntw".utf8))) == ["one"])
        #expect(strings(buffer.append(Data("o\nthr".utf8))) == ["two"])
        #expect(strings(buffer.append(Data("ee\n".utf8))) == ["three"])
    }

    @Test func emptyLinesAreSkipped() {
        var buffer = LineBuffer()
        #expect(strings(buffer.append(Data("\n\na\n\nb\n".utf8))) == ["a", "b"])
    }
}
