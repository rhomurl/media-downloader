import Foundation

/// Parses only allowlisted fields as lines arrive. Raw verbose output never
/// becomes part of a report or a retained diagnostic buffer.
actor DependencyDiagnostics {
    enum Kind: Sendable { case version(String), help, encoders, muxers, readiness }
    struct Fields: Sendable {
        var version: String?
        var flags: Set<String> = []
        var mp3 = false
        var mp4 = false
        var ejsVersion: String?
        var denoVersion: String?
        var missingURL = false
        var unexpectedError = false
    }

    private let kind: Kind
    private var fields = Fields()
    init(_ kind: Kind) { self.kind = kind }
    func snapshot() -> Fields { fields }

    func accept(_ line: ProcessLine) {
        guard line.bytes.count <= 65_536, let text = String(data: line.bytes, encoding: .utf8) else { return }
        let textLine = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .version(let tool):
            let tokens = textLine.split(whereSeparator: \.isWhitespace).map(String.init)
            let token: String?
            switch tool {
            case "yt-dlp": token = tokens.count == 1 ? tokens.first : nil
            case "ffmpeg", "ffprobe": token = tokens.count >= 3 && tokens[0] == tool && tokens[1] == "version" ? tokens[2] : nil
            case "deno": token = tokens.count >= 2 && tokens[0] == "deno" ? tokens[1] : nil
            default: token = nil
            }
            if let token, Self.isVersion(token) { fields.version = token }
        case .help:
            let pattern = #"--[a-z][a-z0-9-]*"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(textLine.startIndex..., in: textLine)
                for match in regex.matches(in: textLine, range: range) {
                    if let swiftRange = Range(match.range, in: textLine) {
                        let flag = String(textLine[swiftRange])
                        if DependencyResolver.requiredFlags.contains(flag) { fields.flags.insert(flag) }
                    }
                }
            }
        case .encoders:
            let tokens = textLine.split(whereSeparator: \.isWhitespace)
            if tokens.count >= 2, tokens[0].count == 6, tokens[0].first == "A",
               tokens[1] == "libmp3lame" { fields.mp3 = true }
        case .muxers:
            let tokens = textLine.split(whereSeparator: \.isWhitespace)
            if tokens.count >= 2, ["E", "DE"].contains(tokens[0]), tokens[1].split(separator: ",").contains("mp4") {
                fields.mp4 = true
            }
        case .readiness:
            let optionalPrefix = "[debug] Optional libraries: "
            let runtimePrefix = "[debug] JS runtimes: "
            if textLine.hasPrefix(optionalPrefix) {
                for item in textLine.dropFirst(optionalPrefix.count).components(separatedBy: ", ") {
                    if item.hasPrefix("yt_dlp_ejs-") {
                        let value = String(item.dropFirst("yt_dlp_ejs-".count))
                        if Self.isVersion(value) { fields.ejsVersion = value }
                    }
                }
            } else if textLine.hasPrefix(runtimePrefix) {
                for item in textLine.dropFirst(runtimePrefix.count).components(separatedBy: ", ") {
                    if item.hasPrefix("deno-") {
                        let value = String(item.dropFirst("deno-".count))
                        if Self.isVersion(value) { fields.denoVersion = value }
                    }
                }
            } else if textLine == "yt-dlp: error: You must provide at least one URL." {
                fields.missingURL = true
            } else if textLine.hasPrefix("ERROR:") || textLine.hasPrefix("yt-dlp: error:") {
                fields.unexpectedError = true
            }
        }
    }

    static func isVersion(_ value: String) -> Bool {
        value.utf8.count <= 48 && value.range(of: #"^[0-9]+(?:\.[0-9]+){0,3}(?:_[0-9]+)?$"#, options: .regularExpression) != nil
    }

    static func supportedDeno(_ version: String) -> Bool {
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        return parts[0] > 2 || (parts[0] == 2 && parts[1] >= 3)
    }
}
