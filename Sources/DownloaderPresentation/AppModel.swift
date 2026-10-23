import AppKit
import Foundation
import Observation
import DownloaderCore

public protocol JobCoordinating: Sendable {
    func updates() async -> AsyncStream<JobSnapshot>
    func preview(_ request: PreviewRequest, operationID: UUID) async -> Bool
    func invalidatePreview() async
    func download(preset: OutputPreset, destination: URL, previewOperationID: UUID?, operationID: UUID) async -> Bool
    func download(_ request: PreviewRequest, preset: OutputPreset, destination: URL, operationID: UUID) async -> Bool
    func cancel() async
    func shutdown() async -> JobSnapshot
}
extension JobCoordinator: JobCoordinating {}

@MainActor public protocol PreferenceStoring {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}
@MainActor public final class UserDefaultsPreferences: PreferenceStoring {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func set(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
}

@MainActor @Observable public final class AppModel {
    public var rawURL = "" { didSet { if rawURL != oldValue { inputChanged() } } }
    public var browser = CookieBrowser.none {
        didSet {
            guard browser != oldValue else { return }
            profileEpoch += 1; braveProfiles = []; braveProfileID = nil; profileIssue = nil; isLoadingProfiles = false
            inputChanged()
            if browser == .brave { Task { [weak self] in await self?.refreshBraveProfiles() } }
        }
    }
    public private(set) var braveProfiles: [BraveProfile] = []
    public var braveProfileID: String? { didSet { if braveProfileID != oldValue { inputChanged() } } }
    public var preset: OutputPreset { didSet { preferences.set(preset.rawValue, forKey: "outputPreset") } }
    public private(set) var destination: URL
    public private(set) var snapshot = AppModel.empty(.idle)
    public private(set) var dependencyReport: DependencyReport?
    public private(set) var isCheckingDependencies = false
    public private(set) var isLoadingProfiles = false
    public private(set) var profileIssue: AppIssue?
    public private(set) var isSessionBlocked = false
    public private(set) var toolOverrides: [String: URL] = [:]
    public static let toolNames = ["ytdlp", "ffmpeg", "ffprobe", "deno"]
    private let preferences: any PreferenceStoring
    private let profiles: any BraveProfileProviding
    private let check: @MainActor ([String: URL]) async -> DependencyReport
    private let makeCoordinator: @MainActor (ResolvedTools) -> any JobCoordinating
    private let folderPicker: @MainActor () -> URL?
    private let reveal: @MainActor (URL) -> Void
    private var coordinator: (any JobCoordinating)?
    private var observation: Task<Void, Never>?
    private var invalidation: Task<Void, Never>?
    private var dependencyTask: Task<DependencyReport, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var operationID: UUID?
    private var previewIdentity: (UUID, PreviewRequest)?
    private var inputEpoch = 0
    private var profileEpoch = 0
    private var downloadActive = false
    private var closed = false

    public init(preferences: any PreferenceStoring, profiles: any BraveProfileProviding,
                check: @escaping @MainActor ([String: URL]) async -> DependencyReport,
                makeCoordinator: @escaping @MainActor (ResolvedTools) -> any JobCoordinating,
                folderPicker: @escaping @MainActor () -> URL?, reveal: @escaping @MainActor (URL) -> Void) {
        self.preferences = preferences; self.profiles = profiles; self.check = check
        self.makeCoordinator = makeCoordinator; self.folderPicker = folderPicker; self.reveal = reveal
        preset = preferences.string(forKey: "outputPreset").flatMap(OutputPreset.init(rawValue:)) ?? .mp4
        let saved = preferences.string(forKey: "destinationPath")
        destination = saved.flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        for name in Self.toolNames {
            if let path = preferences.string(forKey: "toolPath." + name), path.hasPrefix("/") {
                toolOverrides[name] = URL(fileURLWithPath: path)
            }
        }
    }

    public static func live() -> AppModel {
        let runner = ProcessRunner()
        return AppModel(preferences: UserDefaultsPreferences(), profiles: BraveProfileStore(),
                        check: { await DependencyResolver(runner: runner).check(overrides: $0) },
                        makeCoordinator: { JobCoordinator(runner: runner, tools: $0) }, folderPicker: {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.allowsMultipleSelection = false; panel.prompt = "Choose Destination"
            return panel.runModal() == .OK ? panel.url : nil
        }, reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })
    }

    private var request: PreviewRequest {
        .init(rawURL: rawURL, browser: browser, braveProfileID: browser == .brave ? braveProfileID : nil)
    }
    public var isBusy: Bool {
        isCheckingDependencies || downloadActive || [.previewing, .downloading, .processing, .validating, .publishing, .cancelling].contains(snapshot.phase)
    }
    public var canCheckDependencies: Bool { !closed && !isSessionBlocked && !isBusy }
    public var canPreview: Bool {
        !closed && !isSessionBlocked && !isBusy && coordinator != nil && dependencyReport?.tools != nil
            && (try? URLValidator.validate(rawURL)) != nil
            && (browser != .brave || (!isLoadingProfiles && braveProfiles.contains { $0.id == braveProfileID }))
    }
    public var canDownload: Bool {
        canPreview
    }
    public var canCancel: Bool { !closed && !isSessionBlocked && isBusy && snapshot.phase != .publishing && !isCheckingDependencies && snapshot.phase != .cancelling }
    public var busyLabel: String {
        if isCheckingDependencies { return "Checking required tools" }
        switch snapshot.phase {
        case .previewing: return downloadActive ? "Preparing download" : "Loading preview"
        case .downloading: return "Downloading media"
        case .processing: return "Processing media"
        case .validating: return "Verifying downloaded file"
        case .publishing: return "Saving verified file"
        case .cancelling: return "Stopping tools safely"
        default: return ""
        }
    }
    public var statusText: String {
        if isSessionBlocked { return AppIssueClassifier.message(for: .shutdownUnconfirmed) }
        if let issue = snapshot.issue { return AppIssueClassifier.message(for: issue) }
        if isBusy { return busyLabel }
        switch snapshot.phase {
        case .succeeded: return "Download complete."
        case .cancelled: return "Cancelled."
        case .ready: return "Preview ready. Choose an output and download."
        default: return "Paste a single recorded video URL and choose Download. Preview is optional."
        }
    }
    /// Notices are fixed core copy, never arbitrary diagnostics from an adapter.
    public var safeNotice: String? {
        guard snapshot.notice != nil else { return nil }
        if isSessionBlocked { return AppIssueClassifier.message(for: .shutdownUnconfirmed) }
        return "Some temporary files could not be removed. Review them manually after quitting the app."
    }
    public var durationText: String? {
        guard let seconds = snapshot.metadata?.duration, seconds.isFinite,
              seconds >= 0, seconds < Double(Int64.max) else { return nil }
        let whole = Int64(seconds)
        let hours = whole / 3600; let minutes = (whole % 3600) / 60; let remainder = whole % 60
        func padded(_ value: Int64) -> String { value < 10 ? "0\(value)" : "\(value)" }
        return hours > 0 ? "\(hours):\(padded(minutes)):\(padded(remainder))" : "\(minutes):\(padded(remainder))"
    }
    public var validatedThumbnail: URL? {
        guard let url = snapshot.metadata?.thumbnail, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    public func checkDependencies() async {
        guard canCheckDependencies else { return }
        isCheckingDependencies = true; inputEpoch += 1; operationID = nil; previewIdentity = nil; snapshot = Self.empty(.checkingDependencies)
        if let coordinator {
            let final = await coordinator.shutdown()
            if final.issue == .shutdownUnconfirmed { latchBlock() }
        }
        observation?.cancel(); observation = nil; coordinator = nil
        guard !closed, !isSessionBlocked else { isCheckingDependencies = false; return }
        let overrides = Dictionary(uniqueKeysWithValues: toolOverrides.map { ($0.key == "ytdlp" ? "yt-dlp" : $0.key, $0.value) })
        let task = Task { await check(overrides) }; dependencyTask = task
        let report = await task.value
        dependencyTask = nil; dependencyReport = report; isCheckingDependencies = false
        if report.problems.contains(where: { $0.code == "shutdown-unconfirmed" }) { latchBlock() }
        guard !closed, !isSessionBlocked else { return }
        snapshot = Self.empty(.idle)
        guard report.problems.isEmpty, let tools = report.tools else { return }
        let core = makeCoordinator(tools); coordinator = core
        observation = Task { [weak self] in
            let updates = await core.updates()
            for await value in updates {
                guard !Task.isCancelled else { return }
                self?.receive(value)
            }
        }
    }

    public func refreshBraveProfiles() async {
        guard !closed, browser == .brave, !isLoadingProfiles else { return }
        profileEpoch += 1; let epoch = profileEpoch
        isLoadingProfiles = true; profileIssue = nil
        do {
            let values = try await profiles.profiles()
            guard !closed, browser == .brave, profileEpoch == epoch else { return }
            braveProfiles = values
            if !values.contains(where: { $0.id == braveProfileID }) { braveProfileID = nil }
        } catch {
            guard !closed, browser == .brave, profileEpoch == epoch else { return }
            braveProfiles = []; braveProfileID = nil; profileIssue = .browserAccess
        }
        if profileEpoch == epoch { isLoadingProfiles = false }
    }

    private func inputChanged() {
        // Programmatic edits are possible even while controls are disabled. They
        // must not cancel or substitute the immutable click-time download inputs.
        guard !downloadActive, !closed, !isSessionBlocked else { return }
        inputEpoch += 1; previewIdentity = nil
        operationID = nil; snapshot = Self.empty(.idle)
        let previous = invalidation; let core = coordinator
        invalidation = Task { await previous?.value; await core?.invalidatePreview() }
    }
    public func preview() async {
        guard canPreview, let coordinator else { return }
        let epoch = inputEpoch; let captured = request
        previewIdentity = nil; operationID = nil; snapshot = Self.empty(.previewing)
        await invalidation?.value
        guard !closed, !isSessionBlocked, inputEpoch == epoch else { return }
        let id = UUID(); operationID = id; previewIdentity = (id, captured)
        let accepted = await coordinator.preview(captured, operationID: id)
        if !accepted, operationID == id, !isSessionBlocked {
            operationID = nil; previewIdentity = nil; snapshot = Self.empty(.cancelled)
        }
    }
    public func download() async {
        guard canDownload, let coordinator else { return }
        let captured = request; let output = preset; let folder = destination; let epoch = inputEpoch
        let readyID = snapshot.phase == .ready && previewIdentity?.0 == operationID && previewIdentity?.1 == captured
            ? previewIdentity?.0 : nil
        let id = UUID()
        operationID = id; downloadActive = true
        snapshot = Self.empty(readyID == nil ? .previewing : .downloading)
        await invalidation?.value
        guard !closed, !isSessionBlocked, operationID == id, inputEpoch == epoch else {
            if !closed, !isSessionBlocked, operationID == id {
                downloadActive = false; previewIdentity = nil; snapshot = Self.empty(.cancelled)
            }
            return
        }
        let accepted: Bool
        if let readyID {
            accepted = await coordinator.download(preset: output, destination: folder, previewOperationID: readyID, operationID: id)
        } else {
            accepted = await coordinator.download(captured, preset: output, destination: folder, operationID: id)
        }
        if !accepted, operationID == id, !isSessionBlocked {
            downloadActive = false; operationID = nil; previewIdentity = nil; snapshot = Self.empty(.idle)
        }
    }
    public func cancel() async {
        guard canCancel else { return }
        inputEpoch += 1; previewIdentity = nil
        snapshot = .init(operationID: operationID, phase: .cancelling, metadata: snapshot.metadata, progress: snapshot.progress, output: nil, issue: nil, notice: nil)
        await coordinator?.cancel()
        await invalidation?.value
        if snapshot.phase == .cancelling { downloadActive = false; snapshot = Self.empty(.cancelled) }
    }
    public func selectDestination() {
        guard !closed, !downloadActive, let selected = folderPicker(), selected.isFileURL else { return }
        destination = selected; preferences.set(selected.path, forKey: "destinationPath")
    }
    public func revealOutput() {
        guard snapshot.phase == .succeeded, let output = snapshot.output, output.isFileURL else { return }
        reveal(output)
    }
    public func setToolOverride(_ name: String, url: URL?) {
        guard Self.toolNames.contains(name), canCheckDependencies else { return }
        if let url { guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\u{0}") else { return } }
        toolOverrides[name] = url; preferences.set(url?.path, forKey: "toolPath." + name)
        // Invalidate readiness synchronously before a settings-triggered check can queue.
        dependencyReport = nil; inputEpoch += 1; previewIdentity = nil; operationID = nil; snapshot = Self.empty(.idle)
    }
    public func shutdown() async {
        if let shutdownTask { await shutdownTask.value; return }
        closed = true; inputEpoch += 1; profileEpoch += 1
        let task = Task { [self] in
            dependencyTask?.cancel()
            if let report = await dependencyTask?.value,
               report.problems.contains(where: { $0.code == "shutdown-unconfirmed" }) { latchBlock() }
            if let final = await coordinator?.shutdown(), final.issue == .shutdownUnconfirmed { latchBlock() }
            await invalidation?.value
            observation?.cancel(); observation = nil
        }
        shutdownTask = task; await task.value
    }
    private func receive(_ value: JobSnapshot) {
        if value.issue == .shutdownUnconfirmed { latchBlock(); return }
        guard !closed, !isSessionBlocked, let operationID, value.operationID == operationID else { return }
        if value.phase == .ready, previewIdentity?.1 != request { return }
        snapshot = value
        if [.succeeded, .failed, .cancelled].contains(value.phase) { downloadActive = false; previewIdentity = nil }
    }
    private func latchBlock() {
        isSessionBlocked = true; previewIdentity = nil; operationID = nil
        snapshot = .init(operationID: nil, phase: .failed, metadata: nil, progress: nil, output: nil, issue: .shutdownUnconfirmed, notice: nil)
    }
    private static func empty(_ phase: JobPhase) -> JobSnapshot {
        .init(operationID: nil, phase: phase, metadata: nil, progress: nil, output: nil, issue: nil, notice: nil)
    }
}
