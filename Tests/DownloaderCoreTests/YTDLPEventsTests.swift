import Foundation
import Testing
@testable import DownloaderCore

struct YTDLPEventsTests {
    @Test(arguments: [ProcessStream.stdout, .stderr])
    func estimatedProgressOnEitherStream(_ stream: ProcessStream) throws {
        let event = YTDLPEventDecoder.decode(ProcessLine(stream: stream, bytes: Data(#"MD_DOWNLOAD:{"progress":{"status":"downloading","downloaded_bytes":50,"total_bytes_estimate":100},"stream_id":"137"}"#.utf8)))
        guard case .download(let progress) = event else { Issue.record("Expected progress"); return }
        #expect(progress.totalIsEstimate)
        #expect(progress.totalBytes == 100)
        #expect(progress.fractionCompleted == 0.5)
        #expect(progress.streamID == "137")
    }

    @Test func streamCompletionIsOnlyTransferAndIDsChange() {
        for id in ["137", "140"] {
            let data = Data("MD_DOWNLOAD:{\"progress\":{\"status\":\"finished\",\"downloaded_bytes\":120,\"total_bytes\":100},\"stream_id\":\"\(id)\"}".utf8)
            guard case .download(let progress) = YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: data)) else { Issue.record("Expected transfer"); return }
            #expect(progress.fractionCompleted == 1)
            #expect(progress.streamID == id)
        }
    }

    @Test(arguments: ["null", "0", "-1"])
    func unusableTotalRemainsIndeterminate(_ total: String) {
        let data = Data("MD_DOWNLOAD:{\"progress\":{\"downloaded_bytes\":50,\"total_bytes\":\(total)},\"stream_id\":null}".utf8)
        guard case .download(let value) = YTDLPEventDecoder.decode(ProcessLine(stream: .stderr, bytes: data)) else { Issue.record("Expected transfer"); return }
        #expect(value.totalBytes == nil)
        #expect(value.fractionCompleted == nil)
    }

    @Test func invalidOptionalNumbersAreAbsent() {
        let data = Data(#"MD_DOWNLOAD:{"progress":{"downloaded_bytes":-1,"total_bytes":"invalid","speed":-3,"eta":null},"stream_id":"NA"}"#.utf8)
        guard case .download(let value) = YTDLPEventDecoder.decode(ProcessLine(stream: .stderr, bytes: data)) else { Issue.record("Expected transfer"); return }
        #expect(value.downloadedBytes == nil)
        #expect(value.totalBytes == nil)
        #expect(value.speed == nil)
        #expect(value.eta == nil)
        #expect(value.streamID == nil)
    }

    @Test func nonfiniteNumericValuesRemainIndeterminate() {
        let bytes = Data(#"MD_DOWNLOAD:{"progress":{"downloaded_bytes":1e999,"total_bytes":1e999,"speed":"Infinity","eta":"NaN"},"stream_id":null}"#.utf8)
        guard case .download(let value) = YTDLPEventDecoder.decode(ProcessLine(stream: .stderr, bytes: bytes)) else { Issue.record("Expected transfer"); return }
        #expect(value.downloadedBytes == nil)
        #expect(value.totalBytes == nil)
        #expect(value.speed == nil)
        #expect(value.eta == nil)
        #expect(value.fractionCompleted == nil)
    }

    @Test(arguments: [#"{"progress":{}}"#, #"{"progress":{},"stream_id":null}"#, #"{"progress":{},"stream_id":"NA"}"#, #"{"progress":{},"stream_id":""}"#])
    func absentStreamIDStaysIndeterminate(_ json: String) {
        guard case .download(let value) = YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: Data(("MD_DOWNLOAD:" + json).utf8))) else { Issue.record("Expected transfer"); return }
        #expect(value.streamID == nil)
        #expect(value.totalBytes == nil)
    }

    @Test func exactTotalWinsOverEstimate() {
        let bytes = Data(#"MD_DOWNLOAD:{"progress":{"downloaded_bytes":25,"total_bytes":50,"total_bytes_estimate":100},"stream_id":"synthetic"}"#.utf8)
        guard case .download(let value) = YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: bytes)) else { Issue.record("Expected transfer"); return }
        #expect(value.totalBytes == 50)
        #expect(!value.totalIsEstimate)
        #expect(value.fractionCompleted == 0.5)
    }

    @Test func oversizedAndInvalidUTF8ControlIsMalformed() {
        var bytes = Data("MD_DOWNLOAD:".utf8)
        bytes.append(0xff)
        #expect(YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: bytes)) == .malformed)
        let oversized = Data(("MD_FINAL:\"" + String(repeating: "a", count: 65_536) + "\"").utf8)
        #expect(YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: oversized)) == .malformed)
    }

    @Test func escapedFinalPathAndPostprocess() {
        #expect(YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: Data(#"MD_FINAL:"/tmp/synthetic \"file\"/media.mp4""#.utf8))) == .finalPath("/tmp/synthetic \"file\"/media.mp4"))
        #expect(YTDLPEventDecoder.decode(ProcessLine(stream: .stderr, bytes: Data(#"MD_POSTPROCESS:{"status":"started"}"#.utf8))) == .postprocess)
    }

    @Test(arguments: ["MD_DOWNLOAD:{", "MD_FINAL:{}", "MD_FINAL:\"\"", "MD_FINAL:\"a\\u0000b\"", "MD_DOWNLOAD:[]", "MD_DOWNLOAD:{\"total_bytes\":NaN}", "MD_POSTPROCESS:null", "MD_UNKNOWN:{}"])
    func malformedControlFailsSafely(_ raw: String) {
        #expect(YTDLPEventDecoder.decode(ProcessLine(stream: .stdout, bytes: Data(raw.utf8))) == .malformed)
    }

    @Test func humanWarningsAndMetadataAreNotControlEvents() {
        for raw in ["WARNING: synthetic warning", "{\"id\":\"synthetic\",\"title\":\"Example\"}"] {
            #expect(YTDLPEventDecoder.decode(ProcessLine(stream: .stderr, bytes: Data(raw.utf8))) == nil)
        }
    }
}
