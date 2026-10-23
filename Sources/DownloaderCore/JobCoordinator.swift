import Foundation

/// Owns one operation task and its process/reader shutdown barrier. All publication
/// work is synchronous actor-isolated work, after verification and a final cancel check.
public actor JobCoordinator {
    private enum Kind { case preview, download }
    private let runner: any ProcessRunning
    private let commands: YTDLPCommands
    private let verifier: ArtifactVerifier
    private let files: JobFiles
    private var task: Task<Void, Never>?
    private var generation: UUID?
    private var kind: Kind?
    private var cancellationRequested = false
    private var closed = false
    private var ready: (request: PreviewRequest, metadata: VideoMetadata)?
    private var snapshot = JobSnapshot(operationID: nil, phase: .idle, metadata: nil, progress: nil, output: nil, issue: nil, notice: nil)
    private var subscribers: [UUID: AsyncStream<JobSnapshot>.Continuation] = [:]
    private var previewBytes: Data?
    private var previewLines = 0
    private var diagnostic = Data()
    private var finalPath: String?
    private var finalCount = 0
    private var malformed = false
    private var processing = false

    public init(runner: any ProcessRunning, tools: ResolvedTools, files: JobFiles = JobFiles()) {
        self.runner = runner; self.commands = YTDLPCommands(tools: tools)
        self.verifier = ArtifactVerifier(runner: runner, tools: tools); self.files = files
    }

    /// Every subscription starts with the latest value. Only UI snapshots may be dropped.
    public func updates() -> AsyncStream<JobSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<JobSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(snapshot)
        continuation.onTermination = { [weak self] _ in Task { await self?.unsubscribe(id) } }
        return stream
    }
    private func unsubscribe(_ id: UUID) { subscribers[id] = nil }

    /// Supply a fresh operation ID to establish UI identity before suspension.
    /// False means this request was rejected, cancelled, or superseded before launch.
    @discardableResult
    public func preview(_ request: PreviewRequest, operationID: UUID = UUID()) async -> Bool {
        guard !closed, kind != .download else { return false }
        let id = operationID
        generation = id; cancellationRequested = false; kind = .preview; ready = nil
        resetCapture()
        set(id, .previewing)
        // Keep the previous task tracked across the suspension: concurrent replacements
        // must all await this same shutdown, and only the newest generation may launch.
        let previous = task
        previous?.cancel()
        await previous?.value
        guard generation == id, !closed else { return false }
        guard !cancellationRequested else { finish(id, .cancelled); return false }
        task = Task { await self.runPreview(request, id: id) }
        return true
    }

    public func invalidatePreview() async {
        guard !closed, kind != .download else { return }
        let id = UUID()
        generation = id; ready = nil; cancellationRequested = true; kind = .preview
        set(nil, .idle)
        let previous = task
        previous?.cancel()
        await previous?.value
        guard generation == id else { return }
        task = nil; kind = nil
    }

    /// The expected preview ID is checked atomically before capturing ready input.
    /// Rejection returns false without launching a job; it need not emit a snapshot.
    @discardableResult
    public func download(preset: OutputPreset, destination: URL, previewOperationID: UUID? = nil, operationID: UUID = UUID()) async -> Bool {
        guard !closed, kind == nil else { return false }
        if let previewOperationID, generation != previewOperationID { return false }
        guard let ready else {
            let id = UUID(); generation = id
            set(id, .failed, issue: .invalidURL)
            return false
        }
        startDownload(ready.request, metadata: ready.metadata, preset: preset, destination: destination, id: operationID)
        return true
    }

    /// One owned task spans preparation and transfer. A matching preview avoids a
    /// second metadata command; no intermediate ready state permits another launch.
    @discardableResult
    public func download(_ request: PreviewRequest, preset: OutputPreset, destination: URL, operationID: UUID) async -> Bool {
        guard !closed, kind == nil else { return false }
        let metadata = snapshot.phase == .ready && ready?.request == request ? ready?.metadata : nil
        ready = nil
        startDownload(request, metadata: metadata, preset: preset, destination: destination, id: operationID)
        return true
    }

    private func startDownload(_ request: PreviewRequest, metadata: VideoMetadata?, preset: OutputPreset, destination: URL, id: UUID) {
        generation = id; cancellationRequested = false; kind = .download
        resetCapture()
        set(id, metadata == nil ? .previewing : .downloading, metadata: metadata)
        task = Task { await self.prepareAndDownload(request, metadata: metadata, preset: preset, destination: destination, id: id) }
    }

    private func prepareAndDownload(_ request: PreviewRequest, metadata: VideoMetadata?, preset: OutputPreset, destination: URL, id: UUID) async {
        do {
            let validated: VideoMetadata
            if let metadata { validated = metadata }
            else { validated = try await extractMetadata(request, id: id) }
            try checkCurrent(id)
            resetCapture()
            set(id, .downloading, metadata: validated)
            await runDownload(request, metadata: validated, preset: preset, destination: destination, id: id)
        } catch { fail(id, error: error, defaultIssue: .unknown) }
    }

    public func cancel() async {
        guard kind != nil else { return }
        let id = generation
        cancellationRequested = true
        set(id, .cancelling, metadata: snapshot.metadata, progress: snapshot.progress)
        let active = task
        active?.cancel()
        await active?.value
        // A pending replacement has no task of its own yet. Its suspended launch
        // also checks cancellationRequested before it can start.
        if generation == id, kind != nil { finish(id, .cancelled) }
    }

    /// Returns the final safe state after the shutdown barrier, including uncertainty.
    @discardableResult
    public func shutdown() async -> JobSnapshot {
        closed = true
        await cancel()
        return snapshot
    }

    private func runPreview(_ request: PreviewRequest, id: UUID) async {
        do {
            let metadata = try await extractMetadata(request, id: id)
            try checkCurrent(id)
            ready = (request, metadata)
            finish(id, .ready, metadata: metadata)
        } catch { fail(id, error: error, defaultIssue: .unknown) }
    }

    /// Runner return includes descendant/readers shutdown. Both entry paths use
    /// this same bounded extraction, classifier and single-recorded-video decoder.
    private func extractMetadata(_ request: PreviewRequest, id: UUID) async throws -> VideoMetadata {
        try checkCurrent(id)
        let command = try commands.preview(request)
        let result = try await runner.run(command) { [weak self] line in await self?.acceptPreview(line, id: id) }
        try checkCurrent(id)
        guard result.exitCode == 0 else { throw AppIssueClassifier.classify(exitCode: result.exitCode, diagnostic: diagnostic) }
        guard previewLines == 1, let previewBytes else { throw AppIssue.unknown }
        return try MetadataDecoder.decode(previewBytes)
    }

    private func runDownload(_ request: PreviewRequest, metadata: VideoMetadata, preset: OutputPreset, destination: URL, id: UUID) async {
        var staged: StagedJob?
        var defaultIssue = AppIssue.destination
        do {
            try checkCurrent(id)
            let job = try files.create(id: id, destination: destination)
            staged = job
            let command = try commands.download(request, preset: preset, staging: job.directory)
            defaultIssue = .unknown
            let result = try await runner.run(command) { [weak self] line in await self?.acceptDownload(line, id: id) }
            try checkCurrent(id)
            guard result.exitCode == 0 else { throw AppIssueClassifier.classify(exitCode: result.exitCode, diagnostic: diagnostic) }
            defaultIssue = .processing
            guard !malformed, finalCount == 1, let finalPath else { throw AppIssue.processing }
            let candidate = try files.candidate(finalPath: finalPath, job: job, preset: preset)
            set(id, .validating, metadata: metadata)
            try await verifier.verify(candidate, preset: preset)
            try checkCurrent(id)
            // No suspension from final ownership/cancellation check through publication
            // and success. A queued Cancel observes the completed result unchanged.
            set(id, .publishing, metadata: metadata)
            defaultIssue = .destination
            let output = try files.publish(candidate: candidate, job: job, title: metadata.title, preset: preset)
            let notice = cleanup(job)
            finish(id, .succeeded, metadata: metadata, output: output, notice: notice)
        } catch {
            // An unsafe shutdown error takes precedence over cancellation and timeout,
            // including errors propagated by FFprobe. Never clean staging in this case.
            let unsafe = Self.isUnsafeShutdown(error)
            let notice = unsafe ? Self.retainedNotice : staged.flatMap { cleanup($0) }
            fail(id, error: error, defaultIssue: defaultIssue, notice: notice)
        }
    }

    private func acceptPreview(_ line: ProcessLine, id: UUID) {
        guard generation == id, !cancellationRequested else { return }
        if line.stream == .stdout {
            previewLines = min(2, previewLines + 1)
            if previewLines == 1 && line.bytes.count <= 16 * 1_024 * 1_024 { previewBytes = line.bytes }
            else { previewBytes = nil }
        } else { appendDiagnostic(line.bytes) }
    }
    private func acceptDownload(_ line: ProcessLine, id: UUID) {
        guard generation == id, !cancellationRequested else { return }
        switch YTDLPEventDecoder.decode(line) {
        case .download(let progress):
            if !processing { set(id, .downloading, metadata: snapshot.metadata, progress: progress) }
        case .postprocess:
            processing = true
            set(id, .processing, metadata: snapshot.metadata)
        case .finalPath(let path):
            finalCount = min(2, finalCount + 1)
            if finalCount == 1 { finalPath = path }
            processing = true
            set(id, .processing, metadata: snapshot.metadata)
        case .malformed: malformed = true
        case nil: appendDiagnostic(line.bytes)
        }
    }
    private func appendDiagnostic(_ bytes: Data) {
        // Bound both the stored tail and temporary append even for metadata-sized lines.
        let tail = bytes.suffix(65_535)
        let keep = max(0, 65_536 - tail.count - 1)
        diagnostic = Data(diagnostic.suffix(keep))
        diagnostic.append(tail); diagnostic.append(10)
    }
    private func resetCapture() {
        previewBytes = nil; previewLines = 0; diagnostic = Data()
        finalPath = nil; finalCount = 0; malformed = false; processing = false
    }
    private func checkCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard generation == id, !cancellationRequested, !closed else { throw CancellationError() }
    }
    private static func isUnsafeShutdown(_ error: any Error) -> Bool {
        if case ProcessFailure.shutdownUnconfirmed = error { return true }
        return false
    }
    private static let retainedNotice = "Temporary files were retained because process shutdown could not be confirmed. Quit the app and check that the tools have stopped before reviewing them or reopening."
    private func cleanup(_ job: StagedJob) -> String? {
        do { try files.cleanup(job); return nil }
        catch { return "Some temporary files could not be removed. Review them manually after quitting the app." }
    }
    private func fail(_ id: UUID, error: any Error, defaultIssue: AppIssue, notice: String? = nil) {
        // Shutdown uncertainty is a process-control result, not a stale UI callback.
        // Even an old preview can block a newer generation waiting for its shutdown.
        if Self.isUnsafeShutdown(error) {
            closed = true; ready = nil; cancellationRequested = true
            finish(generation, .failed, metadata: snapshot.metadata, issue: .shutdownUnconfirmed, notice: notice ?? Self.retainedNotice)
            return
        }
        guard generation == id else { return }
        if error is CancellationError || cancellationRequested || Task.isCancelled {
            finish(id, .cancelled, metadata: snapshot.metadata, notice: notice)
        } else {
            let issue: AppIssue
            if let safe = error as? AppIssue { issue = safe }
            else if case ArtifactVerificationFailure.incompatibleMedia = error { issue = .formatUnavailable }
            else if case ProcessFailure.timeout = error { issue = .timeout }
            else if case ProcessFailure.launch = error { issue = .dependency }
            else { issue = defaultIssue }
            finish(id, .failed, metadata: snapshot.metadata, issue: issue, notice: notice)
        }
    }
    private func finish(_ id: UUID?, _ phase: JobPhase, metadata: VideoMetadata? = nil, output: URL? = nil, issue: AppIssue? = nil, notice: String? = nil) {
        guard generation == id else { return }
        task = nil; kind = nil
        previewBytes = nil; diagnostic = Data(); finalPath = nil
        set(id, phase, metadata: metadata, output: output, issue: issue, notice: notice)
    }
    private func set(_ id: UUID?, _ phase: JobPhase, metadata: VideoMetadata? = nil, progress: TransferProgress? = nil, output: URL? = nil, issue: AppIssue? = nil, notice: String? = nil) {
        snapshot = JobSnapshot(operationID: id, phase: phase, metadata: metadata, progress: progress, output: output, issue: issue, notice: notice)
        for subscriber in subscribers.values { subscriber.yield(snapshot) }
    }
}
