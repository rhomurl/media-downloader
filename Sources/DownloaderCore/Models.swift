import Foundation

public enum CookieBrowser: String, CaseIterable, Sendable {
    case none, chrome, brave, firefox
}

public enum OutputPreset: String, CaseIterable, Sendable {
    case mp4, mp3
}

public struct PreviewRequest: Equatable, Sendable {
    public let rawURL: String
    public let browser: CookieBrowser

    public init(rawURL: String, browser: CookieBrowser) {
        self.rawURL = rawURL
        self.browser = browser
    }
}

public struct VideoMetadata: Equatable, Sendable {
    public let id: String
    public let title: String
    public let duration: Double?
    public let thumbnail: URL?

    public init(id: String, title: String, duration: Double?, thumbnail: URL?) {
        self.id = id
        self.title = title
        self.duration = duration
        self.thumbnail = thumbnail
    }
}

public struct ResolvedTools: Equatable, Sendable {
    public let ytdlp: URL
    public let ffmpeg: URL
    public let ffprobe: URL
    public let deno: URL

    public init(ytdlp: URL, ffmpeg: URL, ffprobe: URL, deno: URL) {
        self.ytdlp = ytdlp
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.deno = deno
    }
}

public struct TransferProgress: Equatable, Sendable {
    public let downloadedBytes: Double?
    public let totalBytes: Double?
    public let totalIsEstimate: Bool
    public let speed: Double?
    public let eta: Double?
    public let streamID: String?

    public init(downloadedBytes: Double?, totalBytes: Double?, totalIsEstimate: Bool, speed: Double?, eta: Double?, streamID: String?) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        self.totalIsEstimate = totalIsEstimate
        self.speed = speed
        self.eta = eta
        self.streamID = streamID
    }
}

public enum JobPhase: Equatable, Sendable {
    case checkingDependencies, idle, previewing, ready, downloading, processing
    case validating, publishing, cancelling, succeeded, failed, cancelled
}

public enum AppIssue: Error, Equatable, Sendable {
    case dependency, invalidURL, unsupported, collection, browserAccess, loginRequired
    case unavailable, formatUnavailable, network, destination, processing, timeout, unknown
}

public struct JobSnapshot: Equatable, Sendable {
    public let operationID: UUID?
    public let phase: JobPhase
    public let metadata: VideoMetadata?
    public let progress: TransferProgress?
    public let output: URL?
    public let issue: AppIssue?
    public let notice: String?

    public init(operationID: UUID?, phase: JobPhase, metadata: VideoMetadata?, progress: TransferProgress?, output: URL?, issue: AppIssue?, notice: String?) {
        self.operationID = operationID
        self.phase = phase
        self.metadata = metadata
        self.progress = progress
        self.output = output
        self.issue = issue
        self.notice = notice
    }
}
