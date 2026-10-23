import Foundation
import Testing
@testable import DownloaderCore

struct LineFramerTests {
    @Test func splitUTF8IsFramedBeforeDecoding() throws {
        var framer = LineFramer(limit: 64)
        #expect(try framer.append(Data([0xF0, 0x9F])).isEmpty)
        let lines = try framer.append(Data([0x98, 0x80, 0x0A]))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["😀"])
    }

    @Test func framesCRLFEmptyAndTrailingLines() throws {
        var framer = LineFramer(limit: 4)
        #expect(try framer.append(Data("ab\r\n\nxy".utf8)) == [Data("ab".utf8), Data()])
        #expect(try framer.finish() == [Data("xy".utf8)])
        #expect(try framer.finish().isEmpty)
    }

    @Test func preservesInvalidUTF8Bytes() throws {
        var framer = LineFramer(limit: 4)
        #expect(try framer.append(Data([0xff, 0x0a])) == [Data([0xff])])
    }

    @Test func capsCompleteAndIncompleteLines() throws {
        var incomplete = LineFramer(limit: 3)
        #expect(try incomplete.append(Data("abc".utf8)).isEmpty)
        #expect(throws: ProcessFailure.self) { try incomplete.append(Data("d".utf8)) }
        var complete = LineFramer(limit: 3)
        #expect(throws: ProcessFailure.self) { try complete.append(Data("abcd\n".utf8)) }
    }

}
