import Foundation

public enum YTDLPEvent: Equatable, Sendable {
    case download(TransferProgress)
    case postprocess
    case finalPath(String)
    case malformed
}

public enum YTDLPEventDecoder {
    /// Decode download controls only; preview metadata uses MetadataDecoder.
    /// Ordinary human diagnostics never become control events.
    public static func decode(_ line: ProcessLine) -> YTDLPEvent? {
        let appPrefix = Data("MD_".utf8)
        guard line.bytes.starts(with: appPrefix) else { return nil }
        guard line.bytes.count <= 65_536, let text = String(data: line.bytes, encoding: .utf8),
              let separator = text.firstIndex(of: ":") else { return .malformed }
        let prefix = String(text[..<separator])
        let payload = Data(text[text.index(after: separator)...].utf8)
        do {
            switch prefix {
            case "MD_DOWNLOAD":
                let envelope = try JSONDecoder().decode(Envelope.self, from: payload)
                let progress = envelope.progress
                let exact = positive(progress.totalBytes)
                let estimate = positive(progress.estimatedBytes)
                return .download(TransferProgress(downloadedBytes: nonnegative(progress.downloadedBytes),
                    totalBytes: exact ?? estimate, totalIsEstimate: exact == nil && estimate != nil,
                    speed: nonnegative(progress.speed), eta: nonnegative(progress.eta), streamID: envelope.streamID))
            case "MD_POSTPROCESS":
                _ = try JSONDecoder().decode(Progress.self, from: payload)
                return .postprocess
            case "MD_FINAL":
                let path = try JSONDecoder().decode(String.self, from: payload)
                guard !path.isEmpty, !path.contains("\u{0}") else { return .malformed }
                return .finalPath(path)
            default: return .malformed
            }
        } catch { return .malformed }
    }

    private static func nonnegative(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    private static func positive(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private struct Envelope: Decodable {
        let progress: Progress
        let streamID: String?
        enum CodingKeys: String, CodingKey { case progress, streamID = "stream_id" }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            progress = try c.decode(Progress.self, forKey: .progress)
            let id = try? c.decode(String.self, forKey: .streamID)
            streamID = id.flatMap { $0.isEmpty || $0 == "NA" ? nil : $0 }
        }
    }

    private struct Progress: Decodable {
        let downloadedBytes: Double?
        let totalBytes: Double?
        let estimatedBytes: Double?
        let speed: Double?
        let eta: Double?
        enum CodingKeys: String, CodingKey {
            case downloadedBytes = "downloaded_bytes", totalBytes = "total_bytes", estimatedBytes = "total_bytes_estimate", speed, eta
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            downloadedBytes = try? c.decode(Double.self, forKey: .downloadedBytes)
            totalBytes = try? c.decode(Double.self, forKey: .totalBytes)
            estimatedBytes = try? c.decode(Double.self, forKey: .estimatedBytes)
            speed = try? c.decode(Double.self, forKey: .speed)
            eta = try? c.decode(Double.self, forKey: .eta)
        }
    }
}
