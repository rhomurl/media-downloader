import Foundation

public enum URLValidator {
    public static func validate(_ raw: String) throws -> URL {
        guard !raw.isEmpty,
              raw.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { throw AppIssue.invalidURL }
        return url
    }
}
