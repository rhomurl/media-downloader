import Foundation
import Testing
@testable import DownloaderCore

struct AppIssueClassifierTests {
    @Test(arguments: [
        ("could not copy chrome cookie database: permission denied; login required", AppIssue.browserAccess),
        ("failed to decrypt cookies; HTTP Error 403", .browserAccess),
        ("Sign in to confirm your age", .loginRequired),
        ("This video is private", .unavailable),
        ("Requested format is not available", .formatUnavailable),
        ("HTTP Error 429: Too Many Requests", .network),
        ("Unsupported URL", .unsupported),
        ("ffmpeg exited with code 1", .processing),
        ("No space left on device", .destination),
        ("Unable to extract video data", .unknown)
    ])
    func specificCategories(input: String, expected: AppIssue) {
        #expect(AppIssueClassifier.classify(exitCode: 1, diagnostic: Data(input.utf8)) == expected)
    }
    @Test func allMessagesAreFixedAndUnknownSecretsStayPrivate() {
        let secret = "https://private.example.test/video?token=SECRET auth=BearerABC /secret/Profile 2 titleSensitive"
        #expect(AppIssueClassifier.classify(exitCode: 1, diagnostic: Data(secret.utf8)) == .unknown)
        for issue in [AppIssue.dependency, .invalidURL, .unsupported, .collection, .browserAccess, .loginRequired,
                      .unavailable, .formatUnavailable, .network, .destination, .processing, .timeout, .unknown, .profileRequired, .shutdownUnconfirmed] {
            let message = AppIssueClassifier.message(for: issue)
            #expect(!message.isEmpty)
            for token in ["SECRET", "BearerABC", "example.test", "/secret", "titleSensitive"] { #expect(!message.contains(token)) }
        }
    }
    @Test func onlyBoundedTailIsInspected() {
        let bytes = Data(("login required" + String(repeating: "x", count: 65_536)).utf8)
        #expect(AppIssueClassifier.classify(exitCode: 1, diagnostic: bytes) == .unknown)
    }
}
