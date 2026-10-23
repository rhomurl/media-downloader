import Foundation

/// Best-effort categories from a bounded transient tail. UI copy never includes diagnostics.
public enum AppIssueClassifier {
    public static func classify(exitCode: Int32, diagnostic: Data) -> AppIssue {
        let text = String(decoding: diagnostic.suffix(65_536), as: UTF8.self).lowercased()
        func contains(_ markers: [String]) -> Bool { markers.contains { text.contains($0) } }
        // Cookie-specific failures precede broad authentication and HTTP errors.
        if contains(["failed to decrypt", "could not decrypt", "failed to load cookies", "could not copy", "cannot copy"])
            && contains(["cookie", "keychain"]) { return .browserAccess }
        if contains(["cookie", "keychain"]) && contains(["permission denied", "operation not permitted", "access denied", "decrypt"]) { return .browserAccess }
        if contains(["no space left", "disk quota exceeded", "read-only file system", "permission denied", "unable to open for writing"]) { return .destination }
        if contains(["requested format is not available", "no video formats found", "no suitable formats"]) { return .formatUnavailable }
        if contains(["sign in", "login required", "log in", "authentication required", "use --cookies"]) { return .loginRequired }
        if contains(["video is private", "private video", "video unavailable", "video has been removed", "not available in your country", "members-only"]) { return .unavailable }
        if contains(["unsupported url", "no suitable extractor"]) { return .unsupported }
        if contains(["ffmpeg exited", "postprocessing:", "conversion failed"]) { return .processing }
        if contains(["timed out", "connection reset", "connection refused", "unable to download", "http error 429", "too many requests", "http error 503", "temporary failure in name resolution"]) { return .network }
        return .unknown
    }

    public static func message(for issue: AppIssue) -> String {
        switch issue {
        case .dependency: "Required tools are missing or could not run. Check setup and try again."
        case .invalidURL: "Enter a valid HTTP or HTTPS video URL."
        case .unsupported: "This URL or live video is not supported. Choose a single recorded video."
        case .collection: "Collections and playlists are not supported. Choose a single video."
        case .browserAccess: "Browser cookies could not be accessed or decrypted. Check browser permissions and try again."
        case .loginRequired: "This video requires authentication. Select the browser where you are signed in and try again."
        case .unavailable: "This video is unavailable or access is restricted."
        case .formatUnavailable: "The requested output format is unavailable for this video."
        case .network: "A network or rate-limit error interrupted the operation. Try again later."
        case .destination: "The output could not be saved. Check the destination, free space, and permissions."
        case .processing: "The downloaded file could not be processed or verified. Try again."
        case .timeout: "The operation timed out. Check the connection and try again."
        case .unknown: "The operation failed. Check your input and setup, then try again."
        case .shutdownUnconfirmed: "Process shutdown could not be confirmed. Quit the app and check that the tools have stopped before reopening."
        case .profileRequired: "Select a Brave profile before previewing or downloading."
        }
    }
}
