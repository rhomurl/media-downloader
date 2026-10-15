import Foundation
import Testing
@testable import DownloaderCore

struct DependencyResolverTests {
    @Test(arguments: ["2.3.0", "2.9.7"])
    func readyToolsRequireCapabilitiesAndCredentialFreeDiagnostic(denoVersion: String) async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        var replies = TestSupport.diagnosticsReady
        replies[3] = .init("deno " + denoVersion)
        replies[7] = .init(TestSupport.diagnostic.replacingOccurrences(of: "deno-2.9.7", with: "deno-" + denoVersion), exitCode: 2)
        let runner = ScriptedRunner(replies: replies)
        let report = await DependencyResolver(runner: runner).check(overrides: fixture.overrides)
        #expect(report.problems.isEmpty)
        #expect(report.tools?.ffprobe == fixture.overrides["ffprobe"])
        #expect(report.versions == ["yt-dlp": "2026.08.19", "ffmpeg": "6.1", "ffprobe": "6.1", "deno": denoVersion, "ejs": "0.8.0"])
        let commands = await runner.commands()
        #expect(commands.count == 8)
        #expect(commands.allSatisfy { $0.timeout == .seconds(15) && $0.maximumLineBytes == 65_536 })
        #expect(commands.allSatisfy { !$0.arguments.contains("--cookies-from-browser") })
        #expect(commands.last?.arguments == ["--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-js-runtimes", "--js-runtimes", "deno:" + fixture.overrides["deno"]!.path, "--ffmpeg-location", fixture.directory.path, "--no-colors", "--playlist-end", "1", "--verbose", "--simulate", "--"])
        #expect(commands.allSatisfy { Set($0.environment.keys) == ["PATH", "HOME", "LANG"] })
    }

    @Test func missingEJSIsNotHiddenByAnInstalledDeno() async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        let runner = ScriptedRunner(replies: TestSupport.diagnosticsWithoutEJS)
        let report = await DependencyResolver(runner: runner).check(overrides: fixture.overrides)
        #expect(report.tools == nil)
        #expect(report.problems.contains { $0.code == "missing-ejs" })
        #expect(await runner.commands().allSatisfy { !$0.arguments.contains("--cookies-from-browser") })
    }

    @Test(arguments: [false, true]) func brokenOverrideNeverFallsBack(nonExecutable: Bool) async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        let path = fixture.overrides["yt-dlp"]!
        if nonExecutable { try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path) }
        else { try FileManager.default.removeItem(at: path) }
        let runner = ScriptedRunner(replies: TestSupport.diagnosticsReady)
        let report = await DependencyResolver(runner: runner).check(overrides: fixture.overrides)
        #expect(report.tools == nil)
        #expect(report.problems.contains { $0.tool == "yt-dlp" && $0.path == path && $0.code == "not-executable" })
        #expect(await runner.commands().isEmpty)
    }

    @Test func fallbackSearchIsOrderedAndDoesNotReadTerminalPATH() async throws {
        let first = try ToolFixture(); defer { first.remove() }
        let second = try ToolFixture(); defer { second.remove() }
        try FileManager.default.removeItem(at: first.overrides["yt-dlp"]!)
        let runner = ScriptedRunner(replies: TestSupport.diagnosticsReady)
        let report = await DependencyResolver(runner: runner, searchDirectories: [first.directory, second.directory]).check(overrides: [:])
        #expect(report.tools?.ytdlp == second.overrides["yt-dlp"])
        #expect(report.tools?.ffmpeg == first.overrides["ffmpeg"])
        #expect(DependencyResolver.homebrewDirectories.map(\.path) == ["/opt/homebrew/bin", "/usr/local/bin"])
    }

    @Test func missingFFprobeBlocksReadiness() async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.overrides["ffprobe"]!)
        let runner = ScriptedRunner(replies: [])
        let report = await DependencyResolver(runner: runner, searchDirectories: [fixture.directory]).check(overrides: [:])
        #expect(report.tools == nil)
        #expect(report.problems.contains { $0.tool == "ffprobe" && $0.code == "missing" })
        #expect(await runner.commands().isEmpty)
    }

    @Test func ffprobeMustBeColocatedWithFFmpeg() async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        let other = try ToolFixture(); defer { other.remove() }
        var paths = fixture.overrides; paths["ffprobe"] = other.overrides["ffprobe"]
        let runner = ScriptedRunner(replies: [])
        let report = await DependencyResolver(runner: runner).check(overrides: paths)
        #expect(report.tools == nil)
        #expect(report.problems.contains { $0.code == "helper-directory-mismatch" })
        #expect(await runner.commands().isEmpty)
    }

    @Test func renamedHelperCannotEstablishDirectoryDiscovery() async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        let renamed = fixture.directory.appendingPathComponent("other-probe")
        try FileManager.default.moveItem(at: fixture.overrides["ffprobe"]!, to: renamed)
        var paths = fixture.overrides; paths["ffprobe"] = renamed
        let report = await DependencyResolver(runner: ScriptedRunner(replies: TestSupport.diagnosticsReady)).check(overrides: paths)
        #expect(report.tools == nil)
        #expect(report.problems.contains { $0.code == "helper-directory-mismatch" })
    }

    @Test(arguments: ["wrong-binary", "timeout", "launch", "missing-flags", "missing-mp3", "missing-mp4", "unsupported-deno", "old-deno", "diagnostic-failure", "unknown-diagnostic", "unsafe-version", "nonzero-version"])
    func incompatibleToolsFailClosed(problem: String) async throws {
        let fixture = try ToolFixture(); defer { fixture.remove() }
        var replies = TestSupport.diagnosticsReady
        switch problem {
        case "wrong-binary": replies[1] = .init("ffprobe version 6.1")
        case "unsafe-version": replies[0] = .init("2026.08.19 secret")
        case "nonzero-version": replies[0] = .init("2026.08.19", exitCode: 1)
        case "timeout": replies[0] = .init(failure: .timeout)
        case "launch": replies[0] = .init(failure: .launch)
        case "missing-flags": replies[4] = .init(TestSupport.dependencyFlags.replacingOccurrences(of: "--no-remote-components", with: "--no-remote-components-extra"))
        case "missing-mp3": replies[5] = .init(" A....D aac AAC")
        case "missing-mp4": replies[6] = .init(" D mp4 MP4")
        case "unsupported-deno": replies[7] = .init(TestSupport.diagnostic.replacingOccurrences(of: "deno-2.9.7", with: "none"), exitCode: 2)
        case "old-deno": replies[3] = .init("deno 2.2.9")
        case "diagnostic-failure": replies[7] = .init(TestSupport.diagnostic, exitCode: 1)
        default: replies[7] = .init("unknown output including secret", exitCode: 2)
        }
        let report = await DependencyResolver(runner: ScriptedRunner(replies: replies)).check(overrides: fixture.overrides)
        #expect(report.tools == nil)
        let expectedCode = ["old-deno": "unsupported-deno", "diagnostic-failure": "unknown-diagnostic",
                            "unsafe-version": "wrong-binary", "nonzero-version": "wrong-binary"][problem] ?? problem
        #expect(report.problems.contains { $0.code == expectedCode })
        #expect(!String(describing: report).contains("secret"))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEDIA_DOWNLOADER_CHECK_LOCAL_TOOLS"] == "1"))
    func localOfflineReadinessVersionsOnly() async throws {
        let report = await DependencyResolver(runner: ProcessRunner()).check(overrides: [:])
        // Only safe, parsed fields reach the test log, never verbose process output.
        print("LOCAL_TOOL_VERSIONS \(report.versions.sorted { $0.key < $1.key })")
        print("LOCAL_TOOL_PROBLEM_CODES \(report.problems.map(\.code))")
        #expect(report.tools != nil)
        #expect(report.problems.isEmpty)
    }
}
