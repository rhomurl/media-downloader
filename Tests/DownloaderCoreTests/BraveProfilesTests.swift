import Foundation
import Testing
@testable import DownloaderCore

struct BraveProfilesTests {
    @Test func readsOnlyAllowedProfilesAndKeepsDuplicateNames() throws {
        let profiles = try BraveProfileStore.decode(TestSupport.fixture("brave-local-state"))
        #expect(profiles == [BraveProfile(id: "Default", name: "Synthetic"), BraveProfile(id: "Profile 1", name: "Synthetic"), BraveProfile(id: "Profile 2", name: "Second")])
    }

    @Test(arguments: ["{}", "[]", "{", #"{"profile":{"info_cache":[]}}"#])
    func malformedRegistryIsSafeError(_ json: String) {
        #expect(throws: AppIssue.browserAccess) { try BraveProfileStore.decode(Data(json.utf8)) }
    }

    @Test func oversizedRegistryIsSafeError() {
        #expect(throws: AppIssue.browserAccess) { try BraveProfileStore.decode(Data(repeating: 32, count: 16 * 1_024 * 1_024 + 1)) }
    }

    @Test func injectedSyntheticRegistryAndMissingFile() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try TestSupport.fixture("brave-local-state").write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        #expect(try await BraveProfileStore(registry: path).profiles().count == 3)
        do {
            _ = try await BraveProfileStore(registry: path.appendingPathComponent("missing")).profiles()
            Issue.record("Missing registry should fail")
        } catch { #expect(error as? AppIssue == .browserAccess) }
    }

    @Test func oversizedRegistryFileIsRejectedBeforeDecoding() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 32, count: 16 * 1_024 * 1_024 + 1).write(to: path)
        defer { try? FileManager.default.removeItem(at: path) }
        do {
            _ = try await BraveProfileStore(registry: path).profiles()
            Issue.record("Oversized registry should fail")
        } catch { #expect(error as? AppIssue == .browserAccess) }
    }
}
