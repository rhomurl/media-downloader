import Foundation

public enum ArtifactVerificationFailure: Error, Equatable, Sendable {
    case invalidProbe, incompatibleMedia, probeExit(Int32)
}

public struct ArtifactVerifier: Sendable {
    private let runner: any ProcessRunning
    private let tools: ResolvedTools
    public init(runner: any ProcessRunning, tools: ResolvedTools) { self.runner = runner; self.tools = tools }

    public func verify(_ file: URL, preset: OutputPreset) async throws {
        try Task.checkCancellation()
        try FileSafety.nonemptyRegularFile(file, preset: preset)
        guard FileSafety.absoluteFileURL(tools.ffprobe) else { throw AppIssue.dependency }
        let output = ProbeOutput()
        let command = ProcessCommand(executable: tools.ffprobe,
            arguments: ["-v", "error", "-show_format", "-show_streams", "-of", "json", file.path],
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"],
            timeout: .seconds(15), maximumLineBytes: 1_048_576)
        // Deliberately propagate runner errors unchanged, especially shutdownUnconfirmed.
        // That case takes precedence over cancellation and forbids coordinator cleanup.
        let result = try await runner.run(command) { await output.accept($0) }
        try Task.checkCancellation()
        guard result.exitCode == 0 else { throw ArtifactVerificationFailure.probeExit(result.exitCode) }
        let data = try await output.data()
        let probe: Probe
        do { probe = try JSONDecoder().decode(Probe.self, from: data) }
        catch { throw ArtifactVerificationFailure.invalidProbe }
        let audio = probe.streams.filter { $0.codec_type == "audio" }
        let video = probe.streams.filter { $0.codec_type == "video" }
        let formats = Set(probe.format.format_name.split(separator: ",").map(String.init))
        let compatible: Bool
        switch preset {
        case .mp4:
            let family: Set<String> = ["mov", "mp4", "m4a", "3gp", "3g2", "mj2"]
            compatible = !formats.isEmpty && formats.isSubset(of: family) && !video.isEmpty && !audio.isEmpty
                && video.allSatisfy { $0.codec_name == "h264" } && audio.allSatisfy { $0.codec_name == "aac" }
        case .mp3:
            compatible = formats == ["mp3"] && video.isEmpty && !audio.isEmpty && audio.allSatisfy { $0.codec_name == "mp3" }
        }
        guard compatible else { throw ArtifactVerificationFailure.incompatibleMedia }
        // Do not accept a removed, replaced-by-symlink, or truncated artifact after probe.
        try FileSafety.nonemptyRegularFile(file, preset: preset)
    }
}

private struct Probe: Decodable {
    struct Format: Decodable { let format_name: String }
    struct Stream: Decodable { let codec_type: String; let codec_name: String? }
    let format: Format
    let streams: [Stream]
}

private actor ProbeOutput {
    private var bytes = Data()
    private var total = 0
    private var overflow = false
    func accept(_ line: ProcessLine) {
        guard !overflow else { return }
        let available = 1_048_576 - total
        guard line.bytes.count < available else { overflow = true; bytes.removeAll(); return }
        total += line.bytes.count + 1
        if line.stream == .stdout { bytes.append(line.bytes); bytes.append(10) }
    }
    func data() throws -> Data {
        guard !overflow, !bytes.isEmpty else { throw ArtifactVerificationFailure.invalidProbe }
        return bytes
    }
}
