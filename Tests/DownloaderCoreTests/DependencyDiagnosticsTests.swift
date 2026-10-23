import Foundation
import Testing
@testable import DownloaderCore

struct DependencyDiagnosticsTests {
    @Test func unknownLegacyAliasExitTwoCannotPassReadiness() async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        var replies = TestSupport.diagnosticsReady
        replies[7] = .init("Usage: yt-dlp [OPTIONS] URL [URL...]\nyt-dlp: error: no such option: --playlist-end", exitCode: 2, stream: .stderr)
        let report = await DependencyResolver(runner: ScriptedRunner(replies: replies)).check(overrides: fixture.overrides)
        #expect(report.tools == nil)
        #expect(report.problems.contains { $0.code == "unknown-diagnostic" })
    }

    @Test(arguments: [0, 1, 3]) func readinessRequiresExpectedExit(exit: Int32) async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        var replies = TestSupport.diagnosticsReady
        replies[7] = .init(TestSupport.diagnostic, exitCode: exit)
        let report = await DependencyResolver(runner: ScriptedRunner(replies: replies)).check(overrides: fixture.overrides)
        #expect(report.tools == nil)
    }

    @Test(arguments: ["missing-url", "runtime-mismatch", "unbounded-version", "forged-prefix"])
    func readinessMarkersAreStrictAndDoNotLeakOutput(mutation: String) async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        var diagnostic = TestSupport.diagnostic
        switch mutation {
        case "missing-url": diagnostic = diagnostic.replacingOccurrences(of: "yt-dlp: error: You must provide at least one URL.", with: "ERROR: proxy secret")
        case "runtime-mismatch": diagnostic = diagnostic.replacingOccurrences(of: "deno-2.9.7", with: "deno-2.9.6")
        case "unbounded-version": diagnostic = diagnostic.replacingOccurrences(of: "yt_dlp_ejs-0.8.0", with: "yt_dlp_ejs-secret/credentials")
        default: diagnostic = diagnostic.replacingOccurrences(of: "[debug]", with: "unknown secret [debug]")
        }
        var replies = TestSupport.diagnosticsReady
        replies[7] = .init(diagnostic, exitCode: 2)
        let report = await DependencyResolver(runner: ScriptedRunner(replies: replies)).check(overrides: fixture.overrides)
        #expect(report.tools == nil)
        #expect(!String(describing: report).contains("secret"))
        #expect(!String(describing: report).contains("credentials"))
    }
}
