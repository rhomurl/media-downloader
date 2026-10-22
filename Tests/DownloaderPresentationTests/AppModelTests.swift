import Foundation
import Testing
import DownloaderCore
@testable import DownloaderPresentation

@MainActor struct AppModelTests {
    @Test func preferencesLoadWithoutBrowserAccess() async throws {
        let suite = "Task7-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("/tmp/synthetic-destination", forKey: "destinationPath")
        defaults.set("mp3", forKey: "outputPreset")
        defaults.set("brave", forKey: "browser")
        let profiles = SyntheticProfiles()
        let h = Harness(preferences: UserDefaultsPreferences(defaults), profiles: profiles)
        #expect(h.model.destination.path == "/tmp/synthetic-destination")
        #expect(h.model.preset == .mp3)
        #expect(h.model.browser == .none && h.model.braveProfileID == nil)
        #expect(await profiles.calls == 0)
        await h.model.checkDependencies()
        #expect(await profiles.calls == 0)
        #expect(await h.core.requests.isEmpty)
        await h.model.shutdown()
    }
    @Test func cancellingFolderPickerPreservesDestination() {
        let h = Harness(folderChoice: nil)
        let before = h.model.destination
        h.model.selectDestination()
        #expect(h.model.destination == before && h.model.browser == .none)
    }
    @Test func selectedFolderAndPresetAreTheOnlyRequestPreferencesSaved() {
        let preferences = MemoryPreferences()
        let h = Harness(preferences: preferences, folderChoice: URL(fileURLWithPath: "/tmp/chosen"))
        h.model.selectDestination(); h.model.preset = .mp3
        h.model.rawURL = "https://video.example.test/private"; h.model.browser = .chrome
        #expect(preferences.values == ["destinationPath": "/tmp/chosen", "outputPreset": "mp3"])
    }
    @Test func explicitBraveSelectionRequiresAndCapturesExactProfile() async throws {
        let h = Harness(); await h.model.checkDependencies()
        h.model.rawURL = "https://video.example.test/one"; h.model.browser = .brave
        await eventually { h.model.braveProfiles.count == 2 }
        #expect(!h.model.canPreview && h.model.braveProfileID == nil)
        #expect(h.model.braveProfiles.map(\.name) == ["Personal synthetic", "Work synthetic"])
        h.model.braveProfileID = "Profile 4"
        await h.model.preview(); await eventually { h.model.canDownload }
        let captured = try #require(await h.core.requests.last)
        #expect(captured.browser == .brave && captured.braveProfileID == "Profile 4")
        await h.model.download()
        #expect(await h.core.downloadedRequest == captured)
        await h.model.shutdown()
    }
    @Test func staleProfileLoadCannotReselectAfterSwitchingAway() async {
        let profiles = SyntheticProfiles(); let h = Harness(profiles: profiles)
        h.model.browser = .brave
        await eventually { h.model.braveProfiles.count == 2 && !h.model.isLoadingProfiles }
        h.model.braveProfileID = "Profile 4"
        await profiles.holdNextRefresh()
        let refresh = Task { await h.model.refreshBraveProfiles() }
        await profiles.waitForHeldRefresh()
        h.model.browser = .none
        await profiles.release()
        await refresh.value
        #expect(h.model.braveProfiles.isEmpty && h.model.braveProfileID == nil)
        await h.model.shutdown()
    }
    @Test(arguments: ["url", "browser", "profile"])
    func editsAndQueuedOldReadyCannotEnableDownload(change: String) async throws {
        let h = Harness(); await h.readyBrave()
        let old = try #require(await h.core.lastID)
        await h.core.holdInvalidation()
        if change == "url" { h.model.rawURL = "https://video.example.test/two" }
        if change == "browser" { h.model.browser = .chrome }
        if change == "profile" { h.model.braveProfileID = "Default" }
        #expect(!h.model.canDownload)
        await h.core.emit(.ready, id: old)
        await Task.yield()
        #expect(!h.model.canDownload && h.model.snapshot.metadata == nil)
        let replacement = Task { await h.model.preview() }
        await Task.yield()
        #expect(!h.model.canDownload)
        await h.core.releaseInvalidation()
        await replacement.value; await eventually { h.model.canDownload }
        #expect(await h.core.lastID != old)
        await h.model.shutdown()
    }
    @Test func queuedOldReadyAfterReplacementAcceptanceCannotAuthorizeNewInput() async throws {
        let h = Harness(); await h.readyBrave()
        let oldID = try #require(await h.core.lastID)
        await h.core.pauseReady()
        h.model.rawURL = "https://video.example.test/replacement"
        await h.model.preview()
        let newID = try #require(await h.core.lastID)
        #expect(newID != oldID)
        await h.core.emit(.ready, id: oldID)
        // Yield the MainActor repeatedly so its snapshot observer drains the queued value.
        for _ in 0..<40 { await Task.yield() }
        #expect(!h.model.canDownload && h.model.snapshot.phase == .previewing)
        await h.core.emit(.ready, id: newID)
        await eventually { h.model.canDownload }
        await h.model.shutdown()
    }
    @Test func outputPreferenceDoesNotInvalidateMetadataAndActiveDownloadKeepsInput() async {
        let h = Harness(); await h.readyBrave()
        h.model.preset = .mp3
        #expect(h.model.canDownload)
        await h.model.download()
        h.model.rawURL = "https://video.example.test/edited"; h.model.browser = .none
        h.model.preset = .mp4
        #expect(await h.core.downloadedRequest?.braveProfileID == "Profile 4")
        #expect(await h.core.downloadedRequest?.rawURL == "https://video.example.test/one")
        #expect(await h.core.downloadedPreset == .mp3)
        await h.model.shutdown()
    }
    @Test func revealOnlyUsesSucceededOutputAndErrorsUseSafeCoreCopy() async throws {
        let h = Harness(); await h.readyBrave()
        h.model.revealOutput(); #expect(h.revealed.isEmpty)
        await h.model.download()
        let id = try #require(await h.core.lastID)
        await h.core.emit(.failed, id: id, issue: .unknown, notice: "unsafe injected text")
        await eventually { h.model.snapshot.phase == .failed }
        #expect(h.model.statusText == AppIssueClassifier.message(for: .unknown))
        #expect(!h.model.statusText.contains("unsafe"))
        h.model.revealOutput(); #expect(h.revealed.isEmpty)
        await h.model.preview(); await eventually { h.model.canDownload }; await h.model.download()
        let next = try #require(await h.core.lastID)
        let output = URL(fileURLWithPath: "/tmp/verified-synthetic.mp4")
        await h.core.emit(.succeeded, id: next, output: output)
        await eventually { h.model.snapshot.phase == .succeeded }
        h.model.revealOutput(); #expect(h.revealed == [output])
        await h.model.shutdown()
    }
    @Test(arguments: [JobPhase.previewing, .downloading, .processing, .validating, .publishing])
    func busyLabelsAndCancellation(phase: JobPhase) async throws {
        let h = Harness(); await h.readyBrave()
        if phase != .previewing { await h.model.download() }
        let id = try #require(await h.core.lastID)
        await h.core.emit(phase, id: id)
        await eventually { h.model.snapshot.phase == phase }
        #expect(h.model.isBusy && !h.model.canCheckDependencies && !h.model.canDownload)
        #expect(h.model.canCancel == (phase != .publishing))
        #expect(!h.model.busyLabel.isEmpty)
        await h.model.cancel(); await h.model.shutdown()
    }
    @Test func staleShutdownIssueLatchesAcrossInputsAndDependencyRechecks() async {
        let h = Harness(); await h.readyBrave()
        await h.core.emit(.failed, id: UUID(), issue: .shutdownUnconfirmed)
        await eventually { h.model.isSessionBlocked }
        h.model.browser = .none; h.model.rawURL = "https://video.example.test/new"
        h.model.preset = .mp3
        await h.model.checkDependencies(); await h.model.preview(); await h.model.download()
        #expect(h.checks == 1 && !h.model.canCheckDependencies && !h.model.canPreview)
        #expect(h.model.statusText == AppIssueClassifier.message(for: .shutdownUnconfirmed))
        await h.model.shutdown(); #expect(await h.core.shutdownCalls == 1)
    }
    @Test func dependencyShutdownFailureLatchesAndOverridesCannotBypass() async {
        let h = Harness(report: .init(tools: nil, versions: [:], problems: [.init(code: "shutdown-unconfirmed", tool: "yt-dlp", path: nil)]))
        await h.model.checkDependencies()
        h.model.setToolOverride("ytdlp", url: URL(fileURLWithPath: "/tmp/yt-dlp"))
        await h.model.checkDependencies(); await h.model.preview()
        #expect(h.model.isSessionBlocked && h.checks == 1)
        await h.model.shutdown()
    }
    @Test func untrustedDurationCannotOverflowPresentation() async throws {
        let h = Harness(); await h.readyBrave()
        let id = try #require(await h.core.lastID)
        await h.core.emit(.ready, id: id, duration: 3661)
        await eventually { h.model.snapshot.metadata?.duration == 3661 }
        #expect(h.model.durationText == "1:01:01")
        await h.core.emit(.ready, id: id, duration: Double.greatestFiniteMagnitude)
        await eventually { h.model.snapshot.metadata?.duration == Double.greatestFiniteMagnitude }
        #expect(h.model.durationText == nil)
        await h.model.shutdown()
    }
    @Test func rejectedPreviewRestoresControlsInsteadOfStickingBusy() async {
        let h = Harness(); await h.model.checkDependencies()
        h.model.rawURL = "https://video.example.test/synthetic"
        await h.core.rejectPreviews()
        await h.model.preview()
        #expect(!h.model.isBusy && h.model.canPreview && !h.model.canDownload)
        await h.model.shutdown()
    }
    @Test func rejectedReadyIdentityRestoresControlsInsteadOfStickingBusy() async {
        let h = Harness(); await h.readyBrave(); await h.core.rejectDownload()
        await h.model.download()
        #expect(!h.model.isBusy && !h.model.canDownload)
        #expect(h.model.canPreview)
        await h.model.shutdown()
    }
    @Test func cancelWhilePreviewWaitsForInvalidationPreventsQueuedLaunch() async {
        let h = Harness(); await h.readyBrave()
        await h.core.holdInvalidation()
        h.model.rawURL = "https://video.example.test/new"
        let preview = Task { await h.model.preview() }
        await eventually { h.model.snapshot.phase == .previewing }
        let cancel = Task { await h.model.cancel() }
        await eventually { h.model.snapshot.phase == .cancelling }
        await h.core.releaseInvalidation()
        await preview.value; await cancel.value
        #expect(await h.core.requests.count == 1)
        #expect(!h.model.isBusy && h.model.canPreview && !h.model.canDownload)
        await h.model.shutdown()
    }
    @Test func dependencyRecheckDuringDownloadCannotReplaceTheCore() async {
        let h = Harness(); await h.readyBrave(); await h.model.download()
        await h.model.checkDependencies()
        #expect(h.checks == 1 && h.model.isBusy)
        await h.model.shutdown()
    }
    @Test func shutdownWaitsForInFlightDependencyBarrierAndLatchesItsFailure() async {
        let gate = DependencyGate()
        let h = Harness(checkOverride: { await gate.run() })
        let checking = Task { await h.model.checkDependencies() }
        await eventually { await gate.entered }
        var finished = false
        let quitting = Task { await h.model.shutdown(); finished = true }
        await Task.yield()
        #expect(!finished)
        await h.model.checkDependencies()
        #expect(h.checks == 1)
        await gate.release()
        await checking.value; await quitting.value
        #expect(finished && h.model.isSessionBlocked && !h.model.canCheckDependencies)
        #expect(await h.core.requests.isEmpty)
    }
    @Test func recheckConsumesFinalUnsafeCoordinatorSnapshotBeforeReplacement() async {
        let h = Harness(); await h.readyBrave()
        await h.core.failShutdown()
        await h.model.checkDependencies()
        #expect(h.model.isSessionBlocked && h.checks == 1)
        await h.model.shutdown()
    }
    @Test func unknownProfileCannotStartPreviewAndProfileFailureHasSafeCopy() async {
        let h = Harness(profiles: FailingProfiles()); await h.model.checkDependencies()
        h.model.rawURL = "https://video.example.test/synthetic"; h.model.browser = .brave
        await eventually { h.model.profileIssue != nil }
        h.model.braveProfileID = "Profile 999"
        await h.model.preview()
        #expect(!h.model.canPreview && h.model.profileIssue == .browserAccess)
        #expect(await h.core.requests.isEmpty)
        await h.model.shutdown()
    }
    @Test func toolOverridesUseNamedKeysAndInvalidateReadyBeforeRecheck() async {
        let preferences = MemoryPreferences(); let h = Harness(preferences: preferences)
        await h.readyBrave()
        h.model.setToolOverride("arbitrary", url: URL(fileURLWithPath: "/tmp/no"))
        #expect(h.model.canDownload)
        h.model.setToolOverride("ytdlp", url: URL(fileURLWithPath: "/tmp/synthetic-yt-dlp"))
        #expect(!h.model.canPreview && !h.model.canDownload)
        await h.model.checkDependencies()
        #expect(h.lastOverrides["yt-dlp"]?.path == "/tmp/synthetic-yt-dlp")
        #expect(preferences.values["toolPath.ytdlp"] == "/tmp/synthetic-yt-dlp")
        await h.model.shutdown()
    }
    @Test func shutdownBeforeQueuedStartupPreventsChecksAndIsIdempotent() async {
        let h = Harness()
        await h.model.shutdown(); await h.model.checkDependencies(); await h.model.shutdown()
        #expect(h.checks == 0 && !h.model.canPreview && !h.model.canCheckDependencies)
    }
}

@MainActor private func eventually(_ predicate: () async -> Bool) async {
    for _ in 0..<500 { if await predicate() { return }; try? await Task.sleep(for: .milliseconds(2)) }
    Issue.record("Timed out waiting for model behavior")
}
@MainActor final class MemoryPreferences: PreferenceStoring {
    var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String?, forKey key: String) { values[key] = value }
}
private actor SyntheticProfiles: BraveProfileProviding {
    var calls = 0; var hold: Bool; var continuation: CheckedContinuation<Void, Never>?
    private var heldRefreshWaiter: CheckedContinuation<Void, Never>?
    init(hold: Bool = false) { self.hold = hold }
    func profiles() async throws -> [BraveProfile] {
        calls += 1
        if hold {
            await withCheckedContinuation {
                continuation = $0
                heldRefreshWaiter?.resume(); heldRefreshWaiter = nil
            }
        }
        return [.init(id: "Default", name: "Personal synthetic"), .init(id: "Profile 4", name: "Work synthetic")]
    }
    func holdNextRefresh() { hold = true }
    func waitForHeldRefresh() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { heldRefreshWaiter = $0 }
    }
    func release() { hold = false; continuation?.resume(); continuation = nil }
}
private actor ScriptedCore: JobCoordinating {
    let stream: AsyncStream<JobSnapshot>; let continuation: AsyncStream<JobSnapshot>.Continuation
    var requests: [PreviewRequest] = []; var lastID: UUID?; var readyID: UUID?
    var downloadedRequest: PreviewRequest?; var downloadedPreset: OutputPreset?; var shutdownCalls = 0
    var acceptsPreview = true
    var autoReady = true
    var shutdownIssue: AppIssue?
    var hold = false; var waiters: [CheckedContinuation<Void, Never>] = []; var reject = false
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func updates() async -> AsyncStream<JobSnapshot> { stream }
    func preview(_ request: PreviewRequest, operationID: UUID) async -> Bool {
        guard acceptsPreview else { return false }
        requests.append(request); lastID = operationID; readyID = operationID; if autoReady { emit(.ready, id: operationID) }; return true
    }
    func invalidatePreview() async {
        readyID = nil
        if hold { await withCheckedContinuation { waiters.append($0) } }
    }
    func download(preset: OutputPreset, destination: URL, previewOperationID: UUID?, operationID: UUID) async -> Bool {
        guard !reject, readyID == previewOperationID else { return false }
        downloadedRequest = requests.last; downloadedPreset = preset; lastID = operationID
        emit(.downloading, id: operationID); return true
    }
    func cancel() async { emit(.cancelled, id: lastID) }
    func shutdown() async -> JobSnapshot { shutdownCalls += 1; continuation.finish(); return .init(operationID: nil, phase: .cancelled, metadata: nil, progress: nil, output: nil, issue: shutdownIssue, notice: nil) }
    func failShutdown() { shutdownIssue = .shutdownUnconfirmed }
    func holdInvalidation() { hold = true }
    func releaseInvalidation() { hold = false; for w in waiters { w.resume() }; waiters = [] }
    func rejectDownload() { reject = true }
    func pauseReady() { autoReady = false }
    func rejectPreviews() { acceptsPreview = false }
    func emit(_ phase: JobPhase, id: UUID?, issue: AppIssue? = nil, output: URL? = nil, notice: String? = nil, duration: Double? = nil) {
        continuation.yield(.init(operationID: id, phase: phase, metadata: phase == .ready ? .init(id: "synthetic", title: "Synthetic %s / 🎬", duration: duration, thumbnail: nil) : nil, progress: nil, output: output, issue: issue, notice: notice))
    }
}
@MainActor private final class Harness {
    let core = ScriptedCore(); var checks = 0; var revealed: [URL] = []; var lastOverrides: [String: URL] = [:]
    var model: AppModel!
    init(preferences: any PreferenceStoring = MemoryPreferences(), profiles: any BraveProfileProviding = SyntheticProfiles(), folderChoice: URL? = nil, report: DependencyReport? = nil, checkOverride: (@MainActor () async -> DependencyReport)? = nil) {
        let tools = ResolvedTools(ytdlp: URL(fileURLWithPath: "/tmp/yt-dlp"), ffmpeg: URL(fileURLWithPath: "/tmp/ffmpeg"), ffprobe: URL(fileURLWithPath: "/tmp/ffprobe"), deno: URL(fileURLWithPath: "/tmp/deno"))
        model = AppModel(preferences: preferences, profiles: profiles, check: { [weak self] overrides in
            self?.checks += 1; self?.lastOverrides = overrides
            if let checkOverride { return await checkOverride() }
            return report ?? .init(tools: tools, versions: [:], problems: [])
        }, makeCoordinator: { [core] _ in core }, folderPicker: { folderChoice }, reveal: { [weak self] in self?.revealed.append($0) })
    }
    func readyBrave() async {
        await model.checkDependencies(); model.rawURL = "https://video.example.test/one"; model.browser = .brave
        await eventually { self.model.braveProfiles.count == 2 }
        model.braveProfileID = "Profile 4"; await model.preview(); await eventually { self.model.canDownload }
    }
}

private struct FailingProfiles: BraveProfileProviding {
    struct UnsafeFailure: Error {}
    func profiles() async throws -> [BraveProfile] { throw UnsafeFailure() }
}
private actor DependencyGate {
    var entered = false
    var waiter: CheckedContinuation<DependencyReport, Never>?
    func run() async -> DependencyReport {
        entered = true
        return await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        waiter?.resume(returning: .init(tools: nil, versions: [:], problems: [.init(code: "shutdown-unconfirmed", tool: "yt-dlp", path: nil)]))
        waiter = nil
    }
}
