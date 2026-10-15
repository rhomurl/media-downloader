import Foundation

public enum MetadataDecoder {
    public static func decode(_ bytes: Data) throws -> VideoMetadata {
        guard bytes.count <= 16 * 1_024 * 1_024 else { throw AppIssue.unknown }
        let root: Metadata
        do { root = try JSONDecoder().decode(Metadata.self, from: bytes) }
        catch { throw AppIssue.unknown }
        if ["playlist", "multi_video"].contains(root.type) || root.hasEntries { throw AppIssue.collection }
        guard root.type == "video" || root.type.isEmpty else { throw AppIssue.unsupported }
        if root.isLive || ["is_live", "is_upcoming"].contains(root.liveStatus) { throw AppIssue.unsupported }
        guard let id = root.id, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let title = root.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppIssue.unknown }
        let duration = root.duration.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let thumbnail = root.thumbnail.flatMap { try? URLValidator.validate($0) }
        return VideoMetadata(id: id, title: title, duration: duration, thumbnail: thumbnail)
    }

    private struct Metadata: Decodable {
        let id: String?
        let title: String?
        let type: String
        let hasEntries: Bool
        let duration: Double?
        let thumbnail: String?
        let isLive: Bool
        let liveStatus: String
        enum CodingKeys: String, CodingKey {
            case id, title, duration, thumbnail, entries
            case type = "_type", isLive = "is_live", liveStatus = "live_status"
        }
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try? c.decode(String.self, forKey: .id)
            title = try? c.decode(String.self, forKey: .title)
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
            hasEntries = c.contains(.entries)
            duration = try? c.decode(Double.self, forKey: .duration)
            thumbnail = try? c.decode(String.self, forKey: .thumbnail)
            isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
            liveStatus = try c.decodeIfPresent(String.self, forKey: .liveStatus) ?? ""
        }
    }
}
