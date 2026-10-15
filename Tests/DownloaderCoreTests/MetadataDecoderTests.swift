import Foundation
import Testing
@testable import DownloaderCore

struct MetadataDecoderTests {
    @Test func readsSingleVideoWithoutInterpretingTitle() throws {
        let value = try MetadataDecoder.decode(TestSupport.fixture("single-video"))
        #expect(value.id == "synthetic-1")
        #expect(value.title == "%(title)s / \"Synthetic\" 🎬")
        #expect(value.duration == 12.5)
        #expect(value.thumbnail?.absoluteString == "https://example.com/thumbnail.jpg")
    }

    @Test func missingOrInvalidOptionalsRemainAbsent() throws {
        #expect(try MetadataDecoder.decode(TestSupport.fixture("metadata-missing-optionals")).duration == nil)
        let value = try MetadataDecoder.decode(Data(#"{"id":"one","title":"Example","duration":"bad","thumbnail":"file:///tmp/picture"}"#.utf8))
        #expect(value.duration == nil)
        #expect(value.thumbnail == nil)
    }

    @Test func collectionIsRejectedEvenWithOneEntry() throws {
        #expect(throws: AppIssue.collection) { try MetadataDecoder.decode(TestSupport.fixture("collection")) }
        #expect(throws: AppIssue.collection) { try MetadataDecoder.decode(Data(#"{"_type":"multi_video","id":"one","title":"Example","entries":[]}"#.utf8)) }
    }

    @Test(arguments: [#"{"id":"one","title":"Live","is_live":true}"#, #"{"id":"one","title":"Soon","live_status":"is_upcoming"}"#, #"{"id":"one","title":"Live","live_status":"is_live"}"#])
    func rejectsLive(_ json: String) {
        #expect(throws: AppIssue.unsupported) { try MetadataDecoder.decode(Data(json.utf8)) }
    }

    @Test(arguments: ["[]", "{}", #"{"id":"","title":"Example"}"#, #"{"id":"one","title":" "}"#, #"{"id":5,"title":"Example"}"#, "MD_FINAL:\"/tmp/a\""])
    func rejectsInvalidRoot(_ json: String) {
        #expect(throws: AppIssue.unknown) { try MetadataDecoder.decode(Data(json.utf8)) }
    }

    @Test(arguments: [#"{"id":"one","title":"Example","_type":3}"#, #"{"id":"one","title":"Example","is_live":"true"}"#, #"{"id":"one","title":"Example","live_status":3}"#])
    func malformedMediaKindFailsSafely(_ json: String) {
        #expect(throws: AppIssue.unknown) { try MetadataDecoder.decode(Data(json.utf8)) }
    }

    @Test func rejectsOversizedAndDeepInput() {
        #expect(throws: AppIssue.unknown) { try MetadataDecoder.decode(Data(repeating: 32, count: 16 * 1_024 * 1_024 + 1)) }
        #expect(throws: AppIssue.unknown) { try MetadataDecoder.decode(Data((String(repeating: "[", count: 1_024) + "0" + String(repeating: "]", count: 1_024)).utf8)) }
        let deep = #"{"id":"one","title":"Example","extra":"# + String(repeating: "[", count: 1_024) + "0" + String(repeating: "]", count: 1_024) + "}"
        #expect(throws: AppIssue.unknown) { try MetadataDecoder.decode(Data(deep.utf8)) }
    }
}
