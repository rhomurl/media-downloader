import Foundation

public struct BraveProfile: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) { self.id = id; self.name = name }
}

public protocol BraveProfileProviding: Sendable {
    func profiles() async throws -> [BraveProfile]
}

/// Reads only Brave's registry when explicitly invoked by the browser picker.
/// It neither enumerates profile directories nor opens cookie databases.
public struct BraveProfileStore: BraveProfileProviding {
    private let registry: URL
    private static let limit = 16 * 1_024 * 1_024

    public init(registry: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser/Local State")) {
        self.registry = registry
    }

    public func profiles() async throws -> [BraveProfile] {
        let registry = registry
        return try await Task.detached {
            do {
                let handle = try FileHandle(forReadingFrom: registry)
                defer { try? handle.close() }
                guard try handle.seekToEnd() <= UInt64(Self.limit) else { throw AppIssue.browserAccess }
                try handle.seek(toOffset: 0)
                let bytes = try handle.read(upToCount: Self.limit) ?? Data()
                guard try handle.seekToEnd() <= UInt64(Self.limit) else { throw AppIssue.browserAccess }
                return try Self.decode(bytes)
            } catch { throw AppIssue.browserAccess }
        }.value
    }

    public static func decode(_ bytes: Data) throws -> [BraveProfile] {
        guard bytes.count <= limit else { throw AppIssue.browserAccess }
        do {
            let root = try JSONDecoder().decode(Registry.self, from: bytes)
            return root.profile.infoCache.compactMap { id, entry in
                guard isAllowedID(id), let name = entry.name,
                      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return BraveProfile(id: id, name: name)
            }.sorted { $0.id < $1.id }
        } catch { throw AppIssue.browserAccess }
    }

    static func isAllowedID(_ id: String) -> Bool {
        if id == "Default" { return true }
        guard id.hasPrefix("Profile ") else { return false }
        let digits = id.dropFirst(8)
        return !digits.isEmpty && digits.utf8.allSatisfy { (48...57).contains($0) }
    }

    private struct Registry: Decodable {
        let profile: Profiles
        struct Profiles: Decodable {
            let infoCache: [String: Entry]
            enum CodingKeys: String, CodingKey { case infoCache = "info_cache" }
        }
        struct Entry: Decodable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name }
            init(from decoder: any Decoder) throws {
                name = try? decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .name)
            }
        }
    }
}
