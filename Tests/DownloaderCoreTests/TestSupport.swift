import Darwin
import Foundation
import Testing
@testable import DownloaderCore

enum TestSupport {
    static let tools = ResolvedTools(ytdlp: URL(fileURLWithPath: "/synthetic/bin/yt-dlp"),
                                     ffmpeg: URL(fileURLWithPath: "/synthetic/bin/ffmpeg"),
                                     ffprobe: URL(fileURLWithPath: "/synthetic/bin/ffprobe"),
                                     deno: URL(fileURLWithPath: "/synthetic/runtime/deno"))

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    static func fixtureCommand(_ args: [String], timeout: Duration? = .seconds(5), limit: Int = 65_536) -> ProcessCommand {
        let path = ProcessInfo.processInfo.environment["MEDIA_DOWNLOADER_FIXTURE_PATH"]
            ?? FileManager.default.currentDirectoryPath + "/.build/debug/ProcessFixture"
        return ProcessCommand(executable: URL(fileURLWithPath: path), arguments: args,
                              environment: ["PATH": "/usr/bin:/bin", "LANG": "C"],
                              timeout: timeout, maximumLineBytes: limit)
    }

    static func assertGone(_ pid: pid_t, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while kill(pid, 0) == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
}

actor TestLineSink {
    private var captured: [ProcessLine] = []
    private var streams: Set<String> = []
    func accept(_ line: ProcessLine) {
        streams.insert(line.stream == .stdout ? "stdout" : "stderr")
        if captured.count < 32 { captured.append(line) }
    }
    func streamsSeen() -> Set<String> { streams }
    func lines() -> [ProcessLine] { captured }
}

actor TestLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor PIDLatch {
    private var value: pid_t?
    func accept(_ line: ProcessLine) {
        guard let pid = Int32(String(decoding: line.bytes, as: UTF8.self)) else { return }
        value = pid
    }
    func pid() async throws -> pid_t {
        let deadline = ContinuousClock.now + .seconds(3)
        while value == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return try #require(value, "Fixture did not report a child PID")
    }
}

actor TestFlag {
    private var marked = false
    func mark() { marked = true }
    func value() -> Bool { marked }
}

actor ChildPIDBatch {
    private var pids: [Int32] = []
    func accept(_ line: ProcessLine) {
        if pids.count < 32, let pid = Int32(String(decoding: line.bytes, as: UTF8.self)) {
            pids.append(pid)
        }
    }
    func values() -> [Int32] { pids }
    func ready() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while pids.count < 32 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(pids.count == 32)
    }
}

struct ToolFixture {
    let directory: URL
    let overrides: [String: URL]
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("md-tools-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var paths: [String: URL] = [:]
        for name in ["yt-dlp", "ffmpeg", "ffprobe", "deno"] {
            let path = directory.appendingPathComponent(name)
            try Data("fixture".utf8).write(to: path)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
            paths[name] = path
        }
        overrides = paths
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

extension TestSupport {
    static let dependencyFlags = """
    --ignore-config --no-plugin-dirs --no-remote-components --no-js-runtimes --js-runtimes
    --ffmpeg-location --verbose --simulate --no-playlist --socket-timeout --retries
    --fragment-retries --abort-on-unavailable-fragments --color --dump-single-json --skip-download --flat-playlist
    --playlist-items --no-simulate --newline --progress --progress-delta --progress-template
    --print --no-overwrites --no-post-overwrites --output --format --merge-output-format
    --remux-video --extract-audio --audio-format --audio-quality --cookies-from-browser
    """
    static let diagnostic = """
    [debug] Optional libraries: certifi-2026.1.1, yt_dlp_ejs-0.8.0
    [debug] JS runtimes: deno-2.9.7
    yt-dlp: error: You must provide at least one URL.
    """
    static var diagnosticsReady: [ScriptedReply] {
        [.init("2026.08.19"), .init("ffmpeg version 6.1 Copyright synthetic"),
         .init("ffprobe version 6.1 Copyright synthetic"), .init("deno 2.9.7 (stable, release, aarch64-apple-darwin)"),
         .init(dependencyFlags), .init(" A....D libmp3lame libmp3lame MP3 (MPEG audio layer 3)"),
         .init("  E mp4             MP4 (MPEG-4 Part 14)"), .init(diagnostic, exitCode: 2, stream: .stderr)]
    }
    static var diagnosticsWithoutEJS: [ScriptedReply] {
        var replies = diagnosticsReady
        replies[7] = .init("[debug] Optional libraries: certifi-2026.1.1\n[debug] JS runtimes: deno-2.9.7\nyt-dlp: error: You must provide at least one URL.", exitCode: 2, stream: .stderr)
        return replies
    }
}

extension TestSupport {
    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("md-test-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

struct CoordinatorHarness: Sendable {
    let runner: ScriptedRunner
    let coordinator: JobCoordinator
    let destination: URL
    static let request = PreviewRequest(rawURL: "https://video.example.test/watch/synthetic", browser: .none)

    init(runner: ScriptedRunner = ScriptedRunner(), files: JobFiles = JobFiles()) throws {
        self.runner = runner
        self.coordinator = JobCoordinator(runner: runner, tools: TestSupport.tools, files: files)
        self.destination = try TestSupport.temporaryDirectory()
    }
    static func readyVideo(request: PreviewRequest = request, files: JobFiles = JobFiles()) async throws -> CoordinatorHarness {
        let harness = try CoordinatorHarness(files: files)
        await harness.coordinator.preview(request)
        _ = try await harness.runner.waitForCommand(at: 0)
        await harness.runner.resume(.init(lines: [ProcessLine(stream: .stdout, bytes: try TestSupport.fixture("single-video"))]), at: 0)
        _ = try await harness.waitForPhase(.ready)
        return harness
    }
    func candidate(for command: ProcessCommand, preset: OutputPreset = .mp4) throws -> URL {
        let index = try #require(command.arguments.firstIndex(of: "-o"))
        let template = command.arguments[index + 1].replacingOccurrences(of: "%%", with: "%")
        return URL(fileURLWithPath: template.replacingOccurrences(of: "%(ext)s", with: preset.rawValue))
    }
    func finalPathLine(for command: ProcessCommand, preset: OutputPreset = .mp4) throws -> ProcessLine {
        let path = try candidate(for: command, preset: preset)
        // Synthetic bytes, not valid media. FFprobe fixture establishes the validation boundary.
        try Data("synthetic staged artifact".utf8).write(to: path)
        var bytes = Data("MD_FINAL:".utf8)
        bytes.append(try JSONEncoder().encode(path.path))
        return ProcessLine(stream: .stdout, bytes: bytes)
    }
    func waitForPhase(_ phase: JobPhase) async throws -> JobSnapshot {
        try await waitForSnapshot { $0.phase == phase }
    }
    func waitForTerminal() async throws -> JobSnapshot {
        try await waitForSnapshot { [.succeeded, .failed, .cancelled].contains($0.phase) }
    }
    func waitForSnapshot(_ predicate: @escaping @Sendable (JobSnapshot) -> Bool) async throws -> JobSnapshot {
        let stream = await coordinator.updates()
        return try await withThrowingTaskGroup(of: JobSnapshot.self) { group in
            group.addTask {
                for await snapshot in stream where predicate(snapshot) { return snapshot }
                throw ScriptedWaitFailure.deadline
            }
            group.addTask { try await Task.sleep(for: .seconds(5)); throw ScriptedWaitFailure.deadline }
            defer { group.cancelAll() }
            let next = try await group.next()
            return try #require(next)
        }
    }
    func completedFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".media-downloader-") }
    }
    func remove() { try? FileManager.default.removeItem(at: destination) }
    func finishDownload(preset: OutputPreset = .mp4) async throws -> JobSnapshot {
        await coordinator.download(preset: preset, destination: destination)
        let command = try await runner.waitForCommand(at: 1)
        await runner.resume(.init(lines: [try finalPathLine(for: command, preset: preset)]), at: 1)
        _ = try await runner.waitForCommand(at: 2)
        let probe = preset == .mp4 ? "probe-h264-aac" : "probe-mp3"
        await runner.resume(.init(lines: [ProcessLine(stream: .stdout, bytes: try TestSupport.fixture(probe))]), at: 2)
        return try await waitForTerminal()
    }
}
