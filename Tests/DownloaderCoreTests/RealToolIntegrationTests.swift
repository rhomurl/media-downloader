import Foundation
import Testing
@testable import DownloaderCore

private let integrationEnvironment = ProcessInfo.processInfo.environment
private let integrationEnabled = integrationEnvironment["MEDIA_DOWNLOADER_INTEGRATION_URL"] != nil
    && ["YTDLP", "FFMPEG", "FFPROBE", "DENO"].allSatisfy {
        integrationEnvironment["MEDIA_DOWNLOADER_\($0)_PATH"]?.hasPrefix("/") == true
    }

@Suite(.enabled(if: integrationEnabled,
    "Opt-in loopback integration requires MEDIA_DOWNLOADER_INTEGRATION_URL and absolute YTDLP/FFMPEG/FFPROBE/DENO tool paths; run bash scripts/verify.sh --integration."))
struct RealToolIntegrationTests {
    @Test(arguments: [OutputPreset.mp4, .mp3])
    func realCoordinatorPublishesVerifiedOutput(preset: OutputPreset) async throws {
        try await withRealIntegrationHarness { h in
            await h.coordinator.preview(.init(rawURL: h.url("master.m3u8"), browser: .none))
            #expect(try await h.waitFor([.ready, .failed]).phase == .ready)
            await h.coordinator.download(preset: preset, destination: h.destination)
            let result = try await h.waitFor([.succeeded, .failed, .cancelled])
            #expect(result.phase == .succeeded)
            let output = try #require(result.output)
            #expect(output.pathExtension == preset.rawValue)
            let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            #expect(size > 1_024)
            // This is the same real FFprobe contract used before publication. Check it
            // again at the returned final path to cover publication and its extension.
            try await ArtifactVerifier(runner: ProcessRunner(), tools: h.tools).verify(output, preset: preset)
            let actualPaths = try h.contents().map { $0.resolvingSymlinksInPath().path }
            #expect(actualPaths == [output.resolvingSymlinksInPath().path])
            #expect(result.notice == nil)
        }
    }

    @Test func directMP4UnknownCodecsFollowFormatUnavailablePolicy() async throws {
        try await withRealIntegrationHarness { h in
            await h.coordinator.preview(.init(rawURL: h.url("direct.mp4"), browser: .none))
            #expect(try await h.waitFor([.ready, .failed]).phase == .ready)
            await h.coordinator.download(preset: .mp4, destination: h.destination)
            let result = try await h.waitFor([.succeeded, .failed, .cancelled])
            #expect(result.phase == .failed)
            #expect(result.issue == .formatUnavailable)
            #expect(result.output == nil)
            #expect(try h.contents().isEmpty)
        }
    }

    @Test(arguments: SocialLoopbackRunner.sources, [true, false])
    func socialUnknownCodecPortraitCandidateRequiresArtifactValidation(source: String, compatible: Bool) async throws {
        let path = compatible ? "portrait-compatible.mp4" : "portrait-incompatible.mp4"
        try await withRealIntegrationHarness(mappedCandidate: (source, path)) { h in
            // Reserved synthetic input is never fetched: only the test runner
            // maps it to loopback, after the production builder selects policy.
            await h.coordinator.preview(.init(rawURL: source, browser: .none))
            #expect(try await h.waitFor([.ready, .failed]).phase == .ready)
            #expect(await h.mappingRunner?.previewHadUnlabelledMP4 == true)
            await h.coordinator.download(preset: .mp4, destination: h.destination)
            let result = try await h.waitFor([.succeeded, .failed, .cancelled])
            // Proves both variants reached the real FFprobe, rather than the
            // incompatible case merely failing source format selection.
            #expect(await h.mappingRunner?.completedProbes == 1)
            #expect(result.notice == nil)
            if compatible {
                #expect(result.phase == .succeeded && result.issue == nil)
                let output = try #require(result.output)
                try await ArtifactVerifier(runner: ProcessRunner(), tools: h.tools).verify(output, preset: .mp4)
                #expect(try h.contents().map { $0.resolvingSymlinksInPath().path }
                    == [output.resolvingSymlinksInPath().path])
            } else {
                #expect(result.phase == .failed && result.issue == .formatUnavailable)
                #expect(result.output == nil)
                #expect(try h.contents().isEmpty)
            }
        }
    }

    @Test(arguments: ["missing.m3u8", "metadata-unavailable.html"])
    func previewFailuresNeverPublish(path: String) async throws {
        try await withRealIntegrationHarness { h in
            await h.coordinator.preview(.init(rawURL: h.url(path), browser: .none))
            let result = try await h.waitFor([.ready, .failed])
            #expect(result.phase == .failed)
            #expect(result.issue != nil && result.output == nil)
            #expect(try h.contents().isEmpty)
        }
    }

    @Test func unsupportedPresetNeverPublishes() async throws {
        try await withRealIntegrationHarness { h in
            await h.coordinator.preview(.init(rawURL: h.url("audio-master.m3u8"), browser: .none))
            #expect(try await h.waitFor([.ready, .failed]).phase == .ready)
            await h.coordinator.download(preset: .mp4, destination: h.destination)
            let result = try await h.waitFor([.succeeded, .failed, .cancelled])
            #expect(result.phase == .failed && result.issue == .formatUnavailable)
            #expect(result.output == nil)
            #expect(try h.contents().isEmpty)
        }
    }

    @Test(arguments: ["interrupted-master.m3u8", "missing-fragment-master.m3u8"], [OutputPreset.mp4, .mp3])
    func interruptedStreamNeverPublishesPartialMedia(path: String, preset: OutputPreset) async throws {
        try await withRealIntegrationHarness { h in
            await h.coordinator.preview(.init(rawURL: h.url(path), browser: .none))
            #expect(try await h.waitFor([.ready, .failed]).phase == .ready)
            await h.coordinator.download(preset: preset, destination: h.destination)
            let result = try await h.waitFor([.succeeded, .failed, .cancelled])
            #expect(result.phase == .failed)
            #expect(result.issue != nil && result.output == nil)
            #expect(try h.contents().isEmpty)
        }
    }
}

// Even a timeout or failed #require must join owned subprocesses/readers before
// deleting this test's destination. Preserve staging on uncertain shutdown.
private func withRealIntegrationHarness(mappedCandidate: (source: String, path: String)? = nil, _ body: (RealIntegrationHarness) async throws -> Void) async throws {
    let harness = try RealIntegrationHarness(mappedCandidate: mappedCandidate)
    do {
        try await body(harness)
    } catch {
        let final = await harness.coordinator.shutdown()
        if final.issue != .shutdownUnconfirmed { harness.remove() }
        throw error
    }
    let final = await harness.coordinator.shutdown()
    #expect(final.issue != .shutdownUnconfirmed)
    if final.issue != .shutdownUnconfirmed { harness.remove() }
}

private struct RealIntegrationHarness {
    let tools: ResolvedTools
    let coordinator: JobCoordinator
    let destination: URL
    private let base: URL
    let mappingRunner: SocialLoopbackRunner?
    init(mappedCandidate: (source: String, path: String)? = nil) throws {
        let supplied = try #require(integrationEnvironment["MEDIA_DOWNLOADER_INTEGRATION_URL"])
        let parsed = try #require(URL(string: supplied))
        guard parsed.scheme == "http", parsed.host == "127.0.0.1", parsed.port != nil,
              parsed.user == nil, parsed.password == nil else { throw AppIssue.invalidURL }
        base = parsed.deletingLastPathComponent()
        func tool(_ key: String) throws -> URL {
            let path = try #require(integrationEnvironment["MEDIA_DOWNLOADER_\(key)_PATH"])
            guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { throw AppIssue.dependency }
            return URL(fileURLWithPath: path)
        }
        tools = try .init(ytdlp: tool("YTDLP"), ffmpeg: tool("FFMPEG"), ffprobe: tool("FFPROBE"), deno: tool("DENO"))
        if let mappedCandidate {
            let mapping = SocialLoopbackRunner(tools: tools, source: mappedCandidate.source,
                loopback: base.appendingPathComponent(mappedCandidate.path).absoluteString)
            mappingRunner = mapping
            coordinator = JobCoordinator(runner: mapping, tools: tools)
        } else {
            mappingRunner = nil
            coordinator = JobCoordinator(runner: ProcessRunner(), tools: tools)
        }
        destination = try TestSupport.temporaryDirectory()
    }
    func url(_ path: String) -> String { base.appendingPathComponent(path).absoluteString }
    func contents() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
    }
    func remove() { try? FileManager.default.removeItem(at: destination) }
    func waitFor(_ phases: [JobPhase]) async throws -> JobSnapshot {
        let stream = await coordinator.updates()
        return try await withThrowingTaskGroup(of: JobSnapshot.self) { group in
            group.addTask {
                for await snapshot in stream where phases.contains(snapshot.phase) { return snapshot }
                throw ScriptedWaitFailure.deadline
            }
            group.addTask { try await Task.sleep(for: .seconds(90)); throw ScriptedWaitFailure.deadline }
            defer { group.cancelAll() }
            return try #require(try await group.next())
        }
    }
}

// Test-only source mapping keeps the coordinator, command builder, yt-dlp format
// selector, process supervision, files and FFprobe real. No production test hooks.
private actor SocialLoopbackRunner: ProcessRunning {
    static let sources = ["https://media-downloader-fixture.facebook.com/reel/synthetic",
                          "https://media-downloader-fixture.instagram.com/reel/synthetic"]
    let source: String
    let tools: ResolvedTools
    let loopback: String
    let runner = ProcessRunner()
    var completedProbes = 0
    var previewHadUnlabelledMP4 = false

    init(tools: ResolvedTools, source: String, loopback: String) {
        self.tools = tools; self.source = source; self.loopback = loopback
    }

    func run(_ command: ProcessCommand,
             onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult {
        var arguments = command.arguments
        if command.executable == tools.ytdlp {
            // Fail before launching for any request outside this exact fixture.
            guard Self.sources.contains(source), Array(arguments.suffix(2)) == ["--", source],
                  !arguments.contains("--cookies-from-browser") else { throw AppIssue.invalidURL }
            arguments[arguments.count - 1] = loopback
        }
        let mapped = ProcessCommand(executable: command.executable, arguments: arguments,
            environment: command.environment, timeout: command.timeout, maximumLineBytes: command.maximumLineBytes)
        let preview = arguments.contains("--dump-single-json")
        let result = try await runner.run(mapped) { line in
            if preview { await self.inspectPreview(line) }
            await onLine(line)
        }
        if command.executable == tools.ffprobe { completedProbes += 1 }
        return result
    }

    private func inspectPreview(_ line: ProcessLine) {
        guard line.stream == .stdout,
              let object = try? JSONSerialization.jsonObject(with: line.bytes) as? [String: Any],
              let formats = object["formats"] as? [[String: Any]] else { return }
        previewHadUnlabelledMP4 = formats.contains {
            $0["ext"] as? String == "mp4"
                && ($0["vcodec"] == nil || $0["vcodec"] is NSNull)
                && ($0["acodec"] == nil || $0["acodec"] is NSNull)
        }
    }
}
