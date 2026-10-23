import Foundation

/// Builds immutable commands only. Constructing a command never accesses browser data.
public struct YTDLPCommands: Sendable {
    private let tools: ResolvedTools

    public init(tools: ResolvedTools) { self.tools = tools }

    public func preview(_ request: PreviewRequest) throws -> ProcessCommand {
        let arguments = try common(request) + ["--dump-single-json", "--skip-download", "--flat-playlist", "--playlist-end", "1", "--", request.rawURL]
        return command(arguments, timeout: .seconds(60), lineLimit: 16 * 1_024 * 1_024)
    }

    public func download(_ request: PreviewRequest, preset: OutputPreset, staging: URL) throws -> ProcessCommand {
        guard Self.isAbsoluteFile(staging) else { throw AppIssue.destination }
        // Literal percent characters in the chosen destination must not become
        // yt-dlp placeholders. Only our fixed basename is a format template.
        let directory = staging.path.replacingOccurrences(of: "%", with: "%%")
        var arguments = try common(request) + [
            "--abort-on-unavailable-fragments", "--no-simulate", "--newline", "--progress", "--progress-delta", "0.2",
            "--progress-template", #"download:MD_DOWNLOAD:{"progress":%(progress)j,"stream_id":%(info.format_id|"")j}"#,
            "--progress-template", "postprocess:MD_POSTPROCESS:%(progress)j",
            "--print", "after_move:MD_FINAL:%(filepath)j", "--no-overwrites", "--no-post-overwrites",
            "-o", directory + "/media.%(ext)s"
        ]
        switch preset {
        case .mp4:
            var selector = "bv[vcodec~='^(avc1.*|h264)$']+ba[acodec~='^(mp4a.*|aac)$']/b[vcodec~='^(avc1.*|h264)$'][acodec~='^(mp4a.*|aac)$']"
            let host = try URLValidator.validate(request.rawURL).host?.lowercased() ?? ""
            if host == "facebook.com" || host.hasSuffix(".facebook.com")
                || host == "instagram.com" || host.hasSuffix(".instagram.com") {
                // Facebook/Instagram progressive MP4 entries may omit codec labels. This
                // candidate still requires actual H.264/AAC artifact verification.
                selector += "/b[ext=mp4][vcodec^=?avc1][acodec^=?mp4a]"
            }
            arguments += ["-f", selector,
                          "--merge-output-format", "mp4", "--remux-video", "mp4"]
        case .mp3:
            arguments += ["-f", "ba/b", "-x", "--audio-format", "mp3", "--audio-quality", "2"]
        }
        arguments += ["--", request.rawURL]
        return command(arguments, timeout: nil, lineLimit: 65_536)
    }

    private func common(_ request: PreviewRequest) throws -> [String] {
        _ = try URLValidator.validate(request.rawURL)
        guard [tools.ytdlp, tools.ffmpeg, tools.ffprobe, tools.deno].allSatisfy(Self.isAbsoluteFile) else {
            throw AppIssue.dependency
        }
        var arguments = ["--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-js-runtimes",
                         "--js-runtimes", "deno:" + tools.deno.path,
                         "--ffmpeg-location", tools.ffmpeg.deletingLastPathComponent().path,
                         "--no-playlist", "--socket-timeout", "20", "--retries", "2", "--fragment-retries", "2", "--no-colors"]
        switch request.browser {
        case .none: break
        case .chrome, .firefox:
            arguments += ["--cookies-from-browser", request.browser.rawValue]
        case .brave:
            guard let profile = request.braveProfileID else { throw AppIssue.profileRequired }
            guard BraveProfileStore.isAllowedID(profile) else { throw AppIssue.browserAccess }
            arguments += ["--cookies-from-browser", "brave:" + profile]
        }
        return arguments
    }

    private func command(_ arguments: [String], timeout: Duration?, lineLimit: Int) -> ProcessCommand {
        var directories: [String] = []
        for path in [tools.ytdlp, tools.ffmpeg, tools.ffprobe, tools.deno].map({ $0.deletingLastPathComponent().path })
            + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] where !directories.contains(path) {
            directories.append(path)
        }
        // Allowlist instead of inheriting proxy credentials, Python/plugin paths,
        // runtime/debugging overrides, or arbitrary user environment settings.
        let environment = ["PATH": directories.joined(separator: ":"),
                           "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LANG": "en_US.UTF-8"]
        return ProcessCommand(executable: tools.ytdlp, arguments: arguments, environment: environment,
                              timeout: timeout, maximumLineBytes: lineLimit)
    }

    private static func isAbsoluteFile(_ url: URL) -> Bool {
        url.isFileURL && url.host.map({ $0.isEmpty || $0 == "localhost" }) != false
            && url.path.hasPrefix("/") && !url.path.contains("\u{0}")
    }
}
