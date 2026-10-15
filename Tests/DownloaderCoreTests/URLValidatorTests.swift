import Foundation
import Testing
@testable import DownloaderCore

struct URLValidatorTests {
    @Test(arguments: ["file:///tmp/a", "https:///", "https://user:secret@example.com/a", "https://user@example.com",
                      "https://example.com/a\n", "https://example.com/\u{0}", "--help", "example.com/a", " https://example.com", "https://example.com/a b"])
    func rejectsUnsafeInput(_ raw: String) {
        #expect(throws: AppIssue.invalidURL) { try URLValidator.validate(raw) }
    }

    @Test func preservesQuery() throws {
        let raw = "https://example.com/watch?v=1&x=$(touch%20bad)#fragment"
        #expect(try URLValidator.validate(raw).absoluteString == raw)
    }
}
