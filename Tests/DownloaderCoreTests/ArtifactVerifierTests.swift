import Darwin
import Foundation
import Testing
@testable import DownloaderCore

@Suite struct ArtifactVerifierTests {
    @Test(arguments: [OutputPreset.mp4, .mp3])
    func verifiesCompatibleMediaAndUsesBoundedProbe(preset: OutputPreset) async throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("media." + preset.rawValue); try Data([1]).write(to: file)
        let fixture = try TestSupport.fixture(preset == .mp4 ? "probe-h264-aac" : "probe-mp3")
        let runner = ScriptedRunner(replies: [.init(String(decoding: fixture, as: UTF8.self))])
        try await ArtifactVerifier(runner: runner, tools: TestSupport.tools).verify(file, preset: preset)
        let command = try #require(await runner.commands().first)
        #expect(command.executable == TestSupport.tools.ffprobe)
        #expect(command.arguments == ["-v", "error", "-show_format", "-show_streams", "-of", "json", file.path])
        #expect(command.timeout == .seconds(15))
        #expect(command.maximumLineBytes <= 1_048_576)
        #expect(command.environment["FFREPORT"] == nil)
    }

    @Test(arguments: ["hevc", "missing-audio", "extra-audio", "extra-video", "wrong-container", "empty-streams", "missing-codec", "mp3-missing-audio", "mp3-video", "mp3-wrong-container", "invalid-json", "empty-output", "nonzero", "oversized", "oversized-stderr", "stderr-only"])
    func rejectsIncompatibleOrInvalidProbe(kind: String) async throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let preset: OutputPreset = kind.hasPrefix("mp3-") ? .mp3 : .mp4
        let file = folder.appendingPathComponent("media." + preset.rawValue); try Data([1]).write(to: file)
        var object = try #require(JSONSerialization.jsonObject(with: TestSupport.fixture(preset == .mp4 ? "probe-h264-aac" : "probe-mp3")) as? [String: Any])
        switch kind {
        case "missing-audio": object["streams"] = [["codec_type": "video", "codec_name": "h264"]]
        case "extra-audio": object["streams"] = [["codec_type": "video", "codec_name": "h264"], ["codec_type": "audio", "codec_name": "aac"], ["codec_type": "audio", "codec_name": "opus"]]
        case "extra-video": object["streams"] = [["codec_type": "video", "codec_name": "h264"], ["codec_type": "audio", "codec_name": "aac"], ["codec_type": "video", "codec_name": "hevc"]]
        case "wrong-container", "mp3-wrong-container": object["format"] = ["format_name": "matroska,webm"]
        case "empty-streams", "mp3-missing-audio": object["streams"] = []
        case "missing-codec": object["streams"] = [["codec_type": "video"], ["codec_type": "audio", "codec_name": "aac"]]
        case "mp3-video": object["streams"] = [["codec_type": "audio", "codec_name": "mp3"], ["codec_type": "video", "codec_name": "mjpeg"]]
        default: break
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        if kind == "hevc" { data = try TestSupport.fixture("probe-wrong-codec") }
        if kind == "invalid-json" { data = Data("{".utf8) }
        if kind == "empty-output" { data = Data() }
        let reply: ScriptedReply
        if kind == "oversized" || kind == "oversized-stderr" {
            // Valid JSON padded with legal whitespace: without the aggregate cap
            // this would pass, even though every individual line is small.
            let padding = (0..<1_100).map { _ in ProcessLine(stream: kind == "oversized" ? .stdout : .stderr, bytes: Data(repeating: 32, count: 1_024)) }
            reply = .init(lines: padding + [ProcessLine(stream: .stdout, bytes: data)])
        }
        else { reply = .init(String(decoding: data, as: UTF8.self), exitCode: kind == "nonzero" ? 1 : 0, stream: kind == "stderr-only" ? .stderr : .stdout) }
        let verifier = ArtifactVerifier(runner: ScriptedRunner(replies: [reply]), tools: TestSupport.tools)
        await #expect(throws: (any Error).self) { try await verifier.verify(file, preset: preset) }
    }

    @Test(arguments: ["missing", "empty", "symlink", "directory", "wrong-extension"])
    func refusesInvalidFilesBeforeLaunchingProbe(kind: String) async throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent(kind == "wrong-extension" ? "media.mkv" : "media.mp4")
        switch kind {
        case "empty": try Data().write(to: file)
        case "symlink":
            let target = folder.appendingPathComponent("target"); try Data([1]).write(to: target)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        case "directory": try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        case "wrong-extension": try Data([1]).write(to: file)
        default: break
        }
        let runner = ScriptedRunner(replies: [.init(String(decoding: try TestSupport.fixture("probe-h264-aac"), as: UTF8.self))])
        await #expect(throws: (any Error).self) { try await ArtifactVerifier(runner: runner, tools: TestSupport.tools).verify(file, preset: .mp4) }
        #expect(await runner.commands().isEmpty)
    }

    @Test(arguments: [ScriptedFailure.timeout, .launch, .cancellation, .shutdownUnconfirmed(ETIMEDOUT)])
    func propagatesRunnerFailuresIncludingUnsafeShutdown(failure: ScriptedFailure) async throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("media.mp4"); try Data([1]).write(to: file)
        let runner = ScriptedRunner(replies: [.init(failure: failure)])
        do {
            try await ArtifactVerifier(runner: runner, tools: TestSupport.tools).verify(file, preset: .mp4)
            Issue.record("Probe failure was accepted")
        } catch {
            switch (failure, error) {
            case (.timeout, ProcessFailure.timeout), (.launch, ProcessFailure.launch), (.cancellation, is CancellationError): break
            case (.shutdownUnconfirmed(let expected), ProcessFailure.shutdownUnconfirmed(let actual)): #expect(actual == expected)
            default: Issue.record("Runner failure type was lost")
            }
        }
        #expect(try Data(contentsOf: file) == Data([1]))
    }
}
