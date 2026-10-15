import Foundation

/// Fixed safe codes, tool names and selected paths only; never process output.
public struct DependencyProblem: Equatable, Sendable {
    public let code: String
    public let tool: String
    public let path: URL?
    public init(code: String, tool: String, path: URL?) {
        self.code = code; self.tool = tool; self.path = path
    }
}

public struct DependencyReport: Equatable, Sendable {
    public let tools: ResolvedTools?
    public let versions: [String: String]
    public let problems: [DependencyProblem]
    public init(tools: ResolvedTools?, versions: [String: String], problems: [DependencyProblem]) {
        self.tools = tools; self.versions = versions; self.problems = problems
    }
}

public struct DependencyResolver: Sendable {
    static let homebrewDirectories = [URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
                                      URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)]
    static let requiredFlags: Set<String> = [
        "--ignore-config", "--no-plugin-dirs", "--no-remote-components", "--no-js-runtimes", "--js-runtimes",
        "--ffmpeg-location", "--verbose", "--simulate", "--no-playlist", "--socket-timeout", "--retries",
        "--fragment-retries", "--color", "--dump-single-json", "--skip-download", "--flat-playlist",
        "--playlist-items", "--no-simulate", "--newline", "--progress", "--progress-delta", "--progress-template",
        "--print", "--no-overwrites", "--no-post-overwrites", "--output", "--format", "--merge-output-format",
        "--remux-video", "--extract-audio", "--audio-format", "--audio-quality", "--cookies-from-browser"
    ]
    private let runner: any ProcessRunning
    private let searchDirectories: [URL]

    public init(runner: any ProcessRunning) {
        self.init(runner: runner, searchDirectories: Self.homebrewDirectories)
    }

    // Inject the filesystem search roots without replacing real executable checks.
    init(runner: any ProcessRunning, searchDirectories: [URL]) {
        self.runner = runner; self.searchDirectories = searchDirectories
    }

    public func check(overrides: [String: URL]) async -> DependencyReport {
        var paths: [String: URL] = [:]
        var problems: [DependencyProblem] = []
        var versions: [String: String] = [:]
        let names = ["yt-dlp", "ffmpeg", "ffprobe", "deno"]
        for name in names {
            if let override = overrides[name] {
                if Self.isExecutable(override) { paths[name] = override.standardizedFileURL }
                else { problems.append(.init(code: "not-executable", tool: name, path: override)) }
            } else if let found = searchDirectories.map({ $0.appendingPathComponent(name) }).first(where: Self.isExecutable) {
                paths[name] = found.standardizedFileURL
            } else { problems.append(.init(code: "missing", tool: name, path: nil)) }
        }
        guard problems.isEmpty, let ytdlp = paths["yt-dlp"], let ffmpeg = paths["ffmpeg"],
              let ffprobe = paths["ffprobe"], let deno = paths["deno"] else {
            return .init(tools: nil, versions: versions, problems: problems)
        }
        // yt-dlp receives a directory and searches these exact helper names there.
        guard ffmpeg.deletingLastPathComponent() == ffprobe.deletingLastPathComponent(),
              ffmpeg.lastPathComponent == "ffmpeg", ffprobe.lastPathComponent == "ffprobe" else {
            return .init(tools: nil, versions: versions,
                         problems: [.init(code: "helper-directory-mismatch", tool: "ffprobe", path: ffprobe)])
        }
        let tools = ResolvedTools(ytdlp: ytdlp, ffmpeg: ffmpeg, ffprobe: ffprobe, deno: deno)
        let isolated = ["--ignore-config", "--no-plugin-dirs", "--no-remote-components"]
        var directories: [String] = []
        for url in [ytdlp, ffmpeg, ffprobe, deno] {
            let parent = url.deletingLastPathComponent().path
            if !directories.contains(parent) { directories.append(parent) }
        }
        let environment = ["PATH": (directories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]).joined(separator: ":"),
                           "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "LANG": "en_US.UTF-8"]

        func execute(_ name: String, _ arguments: [String], kind: DependencyDiagnostics.Kind) async -> (Int32, DependencyDiagnostics.Fields)? {
            let parser = DependencyDiagnostics(kind)
            let command = ProcessCommand(executable: paths[name]!, arguments: arguments, environment: environment,
                                         timeout: .seconds(15), maximumLineBytes: 65_536)
            do {
                let result = try await runner.run(command) { await parser.accept($0) }
                return (result.exitCode, await parser.snapshot())
            } catch {
                let code: String
                switch error {
                case ProcessFailure.timeout: code = "timeout"
                case ProcessFailure.launch: code = "launch"
                case is CancellationError: code = "cancelled"
                case ProcessFailure.shutdownUnconfirmed: code = "shutdown-unconfirmed"
                default: code = "diagnostic-failure"
                }
                problems.append(.init(code: code, tool: name, path: paths[name]))
                return nil
            }
        }
        for name in names {
            let args = name == "yt-dlp" ? isolated + ["--version"] : [(name == "ffmpeg" || name == "ffprobe") ? "-version" : "--version"]
            guard let (exit, fields) = await execute(name, args, kind: .version(name)) else {
                return .init(tools: nil, versions: versions, problems: problems)
            }
            guard exit == 0, let version = fields.version else {
                return .init(tools: nil, versions: versions, problems: [.init(code: "wrong-binary", tool: name, path: paths[name])])
            }
            versions[name] = version
        }
        guard DependencyDiagnostics.supportedDeno(versions["deno"]!) else {
            return .init(tools: nil, versions: versions, problems: [.init(code: "unsupported-deno", tool: "deno", path: deno)])
        }
        let checks: [(String, [String], DependencyDiagnostics.Kind, String)] = [
            ("yt-dlp", isolated + ["--help"], .help, "missing-flags"),
            ("ffmpeg", ["-hide_banner", "-encoders"], .encoders, "missing-mp3"),
            ("ffmpeg", ["-hide_banner", "-muxers"], .muxers, "missing-mp4")
        ]
        for (name, arguments, kind, code) in checks {
            guard let (exit, fields) = await execute(name, arguments, kind: kind) else {
                return .init(tools: nil, versions: versions, problems: problems)
            }
            let capable: Bool
            switch kind {
            case .help: capable = fields.flags == Self.requiredFlags
            case .encoders: capable = fields.mp3
            case .muxers: capable = fields.mp4
            default: capable = false
            }
            guard exit == 0, capable else {
                return .init(tools: nil, versions: versions, problems: [.init(code: code, tool: name, path: paths[name])])
            }
        }
        // These accepted legacy aliases are hidden from current help; proving
        // initialization reaches the expected no-URL error also tests their parser support.
        let diagnostic = isolated + ["--no-js-runtimes", "--js-runtimes", "deno:" + deno.path,
                                      "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path, "--no-colors", "--playlist-end", "1",
                                      "--verbose", "--simulate", "--"]
        guard let (exit, fields) = await execute("yt-dlp", diagnostic, kind: .readiness) else {
            return .init(tools: nil, versions: versions, problems: problems)
        }
        if let ejs = fields.ejsVersion { versions["ejs"] = ejs }
        else { problems.append(.init(code: "missing-ejs", tool: "yt-dlp", path: ytdlp)) }
        if fields.denoVersion != versions["deno"] {
            problems.append(.init(code: "unsupported-deno", tool: "deno", path: deno))
        }
        if exit != 2 || !fields.missingURL || fields.unexpectedError {
            problems.append(.init(code: "unknown-diagnostic", tool: "yt-dlp", path: ytdlp))
        }
        return .init(tools: problems.isEmpty ? tools : nil, versions: versions, problems: problems)
    }

    private static func isExecutable(_ url: URL) -> Bool {
        guard url.isFileURL, url.host.map({ $0.isEmpty || $0 == "localhost" }) != false,
              url.path.hasPrefix("/"), !url.path.contains("\u{0}") else { return false }
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
