import Darwin
import Foundation
import Testing
import ProcessFixtureSupport
@testable import DownloaderCore

struct JobCoordinatorTests {
    @Test func validPreviewEmitsLatestSnapshotOnEverySubscription() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        for _ in 0..<2 {
            var iterator = await h.coordinator.updates().makeAsyncIterator()
            let value = try #require(await iterator.next())
            #expect(value.phase == .ready && value.operationID != nil)
            #expect(value.metadata?.title == "%(title)s / \"Synthetic\" 🎬")
        }
    }
    @Test(arguments: ["metadata-missing-optionals", "collection", "malformed", "live", "timeout"])
    func previewValidation(fixture: String) async throws {
        let h = try CoordinatorHarness(); defer { h.remove() }
        await h.coordinator.preview(CoordinatorHarness.request)
        _ = try await h.runner.waitForCommand(at: 0)
        let reply: ScriptedReply
        switch fixture {
        case "malformed": reply = .init("{broken")
        case "live": reply = .init(#"{"id":"test","title":"synthetic","is_live":true}"#)
        case "timeout": reply = .init(failure: .timeout)
        default: reply = .init(lines: [.init(stream: .stdout, bytes: try TestSupport.fixture(fixture))])
        }
        await h.runner.resume(reply, at: 0)
        if fixture == "metadata-missing-optionals" {
            let value = try await h.waitForPhase(.ready)
            #expect(value.metadata?.duration == nil && value.metadata?.thumbnail == nil)
        } else {
            let value = try await h.waitForTerminal()
            let expected: AppIssue = fixture == "collection" ? .collection : fixture == "live" ? .unsupported : fixture == "timeout" ? .timeout : .unknown
            #expect(value.phase == .failed && value.issue == expected)
        }
    }
    @Test func downloadRequiresReadyPreview() async throws {
        let h = try CoordinatorHarness(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        #expect(await h.runner.commands().isEmpty)
        #expect(try await h.waitForTerminal().issue == .invalidURL)
    }
    @Test func invalidationClearsMetadataAndPreventsDownload() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.invalidatePreview()
        let idle = try await h.waitForPhase(.idle)
        #expect(idle.metadata == nil)
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        #expect(await h.runner.commands().count == 1)
    }
    @Test func exactBraveProfileIsCapturedInBothCommands() async throws {
        let request = PreviewRequest(rawURL: CoordinatorHarness.request.rawURL, browser: .brave, braveProfileID: "Profile 4")
        let h = try await CoordinatorHarness.readyVideo(request: request); defer { h.remove() }
        let result = try await h.finishDownload()
        #expect(result.phase == .succeeded)
        for command in await h.runner.commands().prefix(2) {
            let index = try #require(command.arguments.firstIndex(of: "--cookies-from-browser"))
            #expect(command.arguments[index + 1] == "brave:Profile 4")
        }
    }
    @Test func missingBraveProfileDoesNotLaunch() async throws {
        let h = try CoordinatorHarness(); defer { h.remove() }
        await h.coordinator.preview(.init(rawURL: CoordinatorHarness.request.rawURL, browser: .brave))
        #expect(try await h.waitForTerminal().issue == .profileRequired)
        #expect(await h.runner.commands().isEmpty)
    }
    @Test(arguments: ["URL", "browser", "profile"])
    func replacementWaitsForOldReadersAndOnlyNewestStarts(change: String) async throws {
        let h = try CoordinatorHarness(); defer { h.remove() }
        await h.runner.holdCancellation(at: 0)
        await h.coordinator.preview(CoordinatorHarness.request)
        _ = try await h.runner.waitForCommand(at: 0)
        let replacement = PreviewRequest(rawURL: change == "URL" ? "https://video.example.test/new" : CoordinatorHarness.request.rawURL,
                                         browser: change == "browser" ? .chrome : .brave, braveProfileID: "Profile 4")
        let replace = Task { await h.coordinator.preview(replacement) }
        try await h.runner.waitForCancellation(at: 0)
        // A third preview overtakes the suspended replacement, exercising actor reentrancy.
        let latest = PreviewRequest(rawURL: "https://video.example.test/latest", browser: .brave, braveProfileID: "Profile 5")
        let replacingID = try await h.waitForPhase(.previewing).operationID
        let newest = Task { await h.coordinator.preview(latest) }
        _ = try await h.waitForSnapshot { $0.phase == .previewing && $0.operationID != replacingID }
        #expect(await h.runner.commands().count == 1)
        await h.runner.resume(.init(#"{"id":"old","title":"stale"}"#), at: 0)
        await replace.value; await newest.value
        let command = try await h.runner.waitForCommand(at: 1)
        #expect(command.arguments.last == latest.rawURL)
        #expect(command.arguments.contains("brave:Profile 5"))
        await h.runner.resume(.init(#"{"id":"new","title":"current"}"#), at: 1)
        let ready = try await h.waitForPhase(.ready)
        #expect(ready.metadata?.id == "new")
        #expect(await h.runner.commands().count == 2)
    }
    @Test(arguments: [0, 1])
    func cancelOrInvalidateWhileReplacementWaitsNeverStartsIt(action: Int) async throws {
        let h = try CoordinatorHarness(); defer { h.remove() }
        await h.runner.holdCancellation(at: 0)
        await h.coordinator.preview(CoordinatorHarness.request)
        _ = try await h.runner.waitForCommand(at: 0)
        let replacement = Task { await h.coordinator.preview(CoordinatorHarness.request) }
        try await h.runner.waitForCancellation(at: 0)
        let control = Task {
            if action == 0 { await h.coordinator.cancel() } else { await h.coordinator.invalidatePreview() }
        }
        _ = try await h.waitForPhase(action == 0 ? .cancelling : .idle)
        await h.runner.resume(.init(), at: 0)
        await replacement.value; await control.value
        #expect(await h.runner.commands().count == 1)
    }
    @Test func finalEventWithFailedExitCannotSucceed() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        await h.runner.resume(.init(lines: [try h.finalPathLine(for: command)], exitCode: 1), at: 1)
        let terminal = try await h.waitForTerminal()
        #expect(terminal.phase == .failed && terminal.output == nil)
        #expect(try h.completedFiles().isEmpty)
        #expect(await h.runner.commands().count == 2)
    }
    @Test(arguments: ["duplicate", "missing", "forged", "malformed", "ffmpeg"])
    func invalidDownloadCannotPublish(kind: String) async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        let final = try h.finalPathLine(for: command)
        let reply: ScriptedReply
        switch kind {
        case "duplicate": reply = .init(lines: [final, final])
        case "missing": reply = .init()
        case "forged": reply = .init("MD_FINAL:\"/synthetic/unowned.mp4\"")
        case "malformed": reply = .init("MD_FINAL:{broken")
        default: reply = .init("ffmpeg exited with code 1", exitCode: 1, stream: .stderr)
        }
        await h.runner.resume(reply, at: 1)
        let result = try await h.waitForTerminal()
        #expect(result.phase == .failed && result.issue == .processing && result.output == nil)
        #expect(try h.completedFiles().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.destination.path).isEmpty)
    }
    @Test func progressIsPerStreamAndProcessingIsNotSuccess() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        _ = try await h.runner.waitForCommand(at: 1)
        await h.runner.emit(.init(stream: .stderr, bytes: Data(#"MD_DOWNLOAD:{"progress":{"downloaded_bytes":100,"total_bytes":100},"stream_id":"video"}"#.utf8)), at: 1)
        let video = try await h.waitForPhase(.downloading)
        #expect(video.progress?.fractionCompleted == 1 && video.output == nil)
        await h.runner.emit(.init(stream: .stdout, bytes: Data(#"MD_DOWNLOAD:{"progress":{"downloaded_bytes":1},"stream_id":"audio"}"#.utf8)), at: 1)
        let audio = try await h.waitForPhase(.downloading)
        #expect(audio.progress?.streamID == "audio" && audio.progress?.totalBytes == nil)
        await h.runner.emit(.init(stream: .stderr, bytes: Data("MD_POSTPROCESS:{}".utf8)), at: 1)
        let processing = try await h.waitForPhase(.processing)
        #expect(processing.output == nil)
        await h.coordinator.cancel()
        #expect(try await h.waitForTerminal().phase == .cancelled)
    }
    @Test(arguments: ["reject", "exit", "timeout"])
    func probeFailureCannotPublish(kind: String) async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        await h.runner.resume(.init(lines: [try h.finalPathLine(for: command)]), at: 1)
        _ = try await h.runner.waitForCommand(at: 2)
        let data = try TestSupport.fixture(kind == "reject" ? "probe-wrong-codec" : "probe-h264-aac")
        await h.runner.resume(.init(lines: [.init(stream: .stdout, bytes: data)], exitCode: kind == "exit" ? 1 : 0,
                                    failure: kind == "timeout" ? .timeout : nil), at: 2)
        let result = try await h.waitForTerminal()
        #expect(result.phase == .failed && result.issue == (kind == "timeout" ? .timeout : .processing))
        #expect(try h.completedFiles().isEmpty)
    }
    @Test(arguments: [OutputPreset.mp4, .mp3])
    func cleanSuccessRequiresProbeAndPublishesVerifiedFile(preset: OutputPreset) async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        let result = try await h.finishDownload(preset: preset)
        let output = try #require(result.output)
        #expect(result.phase == .succeeded && result.issue == nil)
        #expect(output.pathExtension == preset.rawValue)
        #expect(try Data(contentsOf: output) == Data("synthetic staged artifact".utf8))
        let completedNames = try h.completedFiles().map(\.lastPathComponent)
        #expect(completedNames == [output.lastPathComponent])
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.destination.path).count == 1)
    }
    @Test func activeDownloadRefusesPreviewDownloadAndInvalidation() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        _ = try await h.runner.waitForCommand(at: 1)
        let before = try await h.waitForPhase(.downloading)
        await h.coordinator.preview(.init(rawURL: "https://video.example.test/new", browser: .chrome))
        await h.coordinator.download(preset: .mp3, destination: h.destination)
        await h.coordinator.invalidatePreview()
        let after = try await h.waitForPhase(.downloading)
        #expect(before.operationID == after.operationID && after.metadata == before.metadata)
        #expect(await h.runner.commands().count == 2)
        await h.coordinator.cancel()
    }
    @Test(arguments: [0, 1, 2])
    func cancellationWaitsForRunnerBeforeCleanup(phase: Int) async throws {
        let h = phase == 0 ? try CoordinatorHarness() : try await CoordinatorHarness.readyVideo()
        defer { h.remove() }
        await h.runner.holdCancellation(at: phase)
        if phase == 0 { await h.coordinator.preview(CoordinatorHarness.request) }
        else {
            await h.coordinator.download(preset: .mp4, destination: h.destination)
            let command = try await h.runner.waitForCommand(at: 1)
            if phase == 2 { await h.runner.resume(.init(lines: [try h.finalPathLine(for: command)]), at: 1) }
        }
        let command = try await h.runner.waitForCommand(at: phase)
        let cancel = Task { await h.coordinator.cancel() }
        try await h.runner.waitForCancellation(at: phase)
        #expect(try await h.waitForPhase(.cancelling).phase == .cancelling)
        if phase > 0 {
            let staging = phase == 1 ? try h.candidate(for: command).deletingLastPathComponent() : URL(fileURLWithPath: try #require(command.arguments.last)).deletingLastPathComponent()
            #expect(FileManager.default.fileExists(atPath: staging.path))
        }
        await h.runner.resume(.init(), at: phase)
        await cancel.value
        #expect(try await h.waitForTerminal().phase == .cancelled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: h.destination.path).isEmpty)
    }
    @Test(arguments: [1, 2])
    func unsafeShutdownOverridesCancellationAndPreservesStaging(origin: Int) async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.runner.holdCancellation(at: origin)
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        let path = try h.candidate(for: command)
        let final = try h.finalPathLine(for: command)
        if origin == 2 { await h.runner.resume(.init(lines: [final]), at: 1) }
        _ = try await h.runner.waitForCommand(at: origin)
        let cancel = Task { await h.coordinator.cancel() }
        try await h.runner.waitForCancellation(at: origin)
        await h.runner.resume(.init(failure: .shutdownUnconfirmed(13)), at: origin)
        await cancel.value
        let result = try await h.waitForTerminal()
        #expect(result.phase == .failed && result.output == nil && result.notice != nil)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }
    @Test func retryUsesFreshGeneration() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        _ = try await h.runner.waitForCommand(at: 1)
        await h.runner.resume(.init(failure: .timeout), at: 1)
        let failed = try await h.waitForTerminal()
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 2)
        let next = try await h.waitForPhase(.downloading)
        #expect(failed.operationID != next.operationID)
        #expect(try h.candidate(for: command).path.contains(try #require(next.operationID).uuidString))
        await h.coordinator.cancel()
    }
    @Test func publicationFailureIsDestinationAndCleanupFailureDoesNotLoseSuccess() async throws {
        for mode in [PublicationMode.diskFull, .cleanupFailure] {
            let h = try await CoordinatorHarness.readyVideo(files: JobFiles(publisher: TestPublisher(mode: mode)))
            defer { h.remove() }
            let value = try await h.finishDownload()
            if mode == .diskFull {
                #expect(value.phase == .failed && value.issue == .destination && value.output == nil)
            } else {
                #expect(value.phase == .succeeded && value.notice != nil)
                #expect(FileManager.default.fileExists(atPath: try #require(value.output).path))
            }
        }
    }
    @Test func shutdownStopsActiveJobAndPreventsRestart() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        _ = try await h.runner.waitForCommand(at: 1)
        await h.coordinator.shutdown()
        await h.coordinator.preview(CoordinatorHarness.request)
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        #expect(await h.runner.commands().count == 2)
        #expect(try await h.waitForTerminal().phase == .cancelled)
    }
}

private enum PublicationMode { case diskFull, cleanupFailure }
private struct TestPublisher: FilePublishing {
    let mode: PublicationMode
    func moveExclusively(from: URL, to: URL) throws {
        if mode == .diskFull { throw JobFileFailure.filesystem(ENOSPC) }
        try DarwinFilePublisher().moveExclusively(from: from, to: to)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: from.deletingLastPathComponent().path)
    }
}

extension JobCoordinatorTests {
    @Test func cancellationWhileProcessingCleansOnlyAfterReaderBarrier() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.runner.holdCancellation(at: 1)
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        let candidate = try h.candidate(for: command)
        _ = try h.finalPathLine(for: command)
        await h.runner.emit(.init(stream: .stderr, bytes: Data("MD_POSTPROCESS:{}".utf8)), at: 1)
        _ = try await h.waitForPhase(.processing)
        let cancel = Task { await h.coordinator.cancel() }
        try await h.runner.waitForCancellation(at: 1)
        #expect(FileManager.default.fileExists(atPath: candidate.path))
        await h.runner.resume(.init(), at: 1)
        await cancel.value
        #expect(try await h.waitForTerminal().phase == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: candidate.deletingLastPathComponent().path))
    }

    @Test func newestOnlySnapshotsDoNotDropDuplicateControlEvents() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        let stream = await h.coordinator.updates()
        let final = try h.finalPathLine(for: command)
        await h.runner.emit(final, at: 1)
        for index in 0..<40 {
            await h.runner.emit(.init(stream: .stderr, bytes: Data("MD_POSTPROCESS:{\"eta\":\(index)}".utf8)), at: 1)
        }
        await h.runner.emit(final, at: 1)
        await h.runner.resume(.init(), at: 1)
        _ = try await h.waitForTerminal()
        var iterator = stream.makeAsyncIterator()
        let latest = try #require(await iterator.next())
        #expect(latest.phase == .failed && latest.issue == .processing)
        #expect(try h.completedFiles().isEmpty)
    }

    @Test func publicationIsAtomicWithRespectToQueuedCancellation() async throws {
        let gate = PublicationGate()
        let h = try await CoordinatorHarness.readyVideo(files: JobFiles(publisher: BlockingPublisher(gate: gate)))
        defer { h.remove(); gate.release() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        await h.runner.resume(.init(lines: [try h.finalPathLine(for: command)]), at: 1)
        _ = try await h.runner.waitForCommand(at: 2)
        // A dedicated thread waits for entry to the synchronous publisher. It queues
        // Cancel while publication owns the actor, then releases that syscall gate.
        let queued = OneShotSignal()
        let cancellation = Task.detached {
            try await gate.entered.wait()
            let cancel = Task { await h.coordinator.cancel() }
            await queued.signal()
            gate.release()
            await cancel.value
        }
        await h.runner.resume(.init(lines: [.init(stream: .stdout, bytes: try TestSupport.fixture("probe-h264-aac"))]), at: 2)
        try await queued.wait()
        try await cancellation.value
        let value = try await h.waitForTerminal()
        #expect(value.phase == .succeeded)
        #expect(FileManager.default.fileExists(atPath: try #require(value.output).path))
    }

    @Test func missingDestinationIsSafeAndDoesNotStartDownloadProcess() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination.appendingPathComponent("missing"))
        let value = try await h.waitForTerminal()
        #expect(value.phase == .failed && value.issue == .destination)
        #expect(await h.runner.commands().count == 1)
    }

    @Test func cleanupFailureAfterCancellationIsSecondary() async throws {
        let h = try await CoordinatorHarness.readyVideo(); defer { h.remove() }
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        let command = try await h.runner.waitForCommand(at: 1)
        let path = try h.candidate(for: command).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        await h.coordinator.cancel()
        let value = try await h.waitForTerminal()
        #expect(value.phase == .cancelled && value.issue == nil && value.notice != nil)
        #expect(FileManager.default.fileExists(atPath: path.path))
    }

    @Test(arguments: ["fork-hold", "orphan-hold"])
    func quitWaitsForRealDescendantsAndReadersBeforeRemovingStaging(mode: String) async throws {
        let runner = DescendantCoordinatorRunner(mode: mode)
        let destination = try TestSupport.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: destination) }
        let coordinator = JobCoordinator(runner: runner, tools: TestSupport.tools)
        defer { Task { await runner.release.signal(); await coordinator.shutdown() } }
        let h = CoordinatorObservation(coordinator: coordinator)
        await coordinator.preview(CoordinatorHarness.request)
        _ = try await h.waitFor(.ready)
        await coordinator.download(preset: .mp4, destination: destination)
        try await runner.started.wait()
        let pid = try #require(await runner.childPID())
        let staging = try #require(await runner.staging())
        let quitting = Task { await coordinator.shutdown() }
        // This signal is emitted after ProcessRunner returns: descendants and readers
        // have stopped, but the adapter intentionally holds the runner return boundary.
        try await runner.stopped.wait()
        #expect([0, 5].contains(fixture_process_status(pid)))
        #expect(FileManager.default.fileExists(atPath: staging.path))
        await runner.release.signal()
        await quitting.value
        #expect(try await h.waitFor(.cancelled).phase == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
    }
}

/// Cancellation-aware five-second deadline, without polling for ordering.
actor OneShotSignal {
    private var signalled = false
    private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    func signal() {
        signalled = true
        let pending = waiters.values; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
    func wait() async throws {
        if signalled { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
                if Task.isCancelled { expire(id) }
                else { Task { try? await Task.sleep(for: .seconds(5)); self.expire(id) } }
            }
        } onCancel: { Task { await self.expire(id) } }
    }
    private func expire(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: ScriptedWaitFailure.deadline) }
}

private final class PublicationGate: Sendable {
    let entered = OneShotSignal()
    private let semaphore = DispatchSemaphore(value: 0)
    func block() throws {
        Task { await entered.signal() }
        guard semaphore.wait(timeout: .now() + 5) == .success else { throw ScriptedWaitFailure.deadline }
    }
    func release() { semaphore.signal() }
}
private struct BlockingPublisher: FilePublishing {
    let gate: PublicationGate
    func moveExclusively(from: URL, to: URL) throws {
        try gate.block()
        try DarwinFilePublisher().moveExclusively(from: from, to: to)
    }
}

private struct CoordinatorObservation {
    let coordinator: JobCoordinator
    func waitFor(_ phase: JobPhase) async throws -> JobSnapshot {
        let stream = await coordinator.updates()
        return try await withThrowingTaskGroup(of: JobSnapshot.self) { group in
            group.addTask {
                for await value in stream where value.phase == phase { return value }
                throw ScriptedWaitFailure.deadline
            }
            group.addTask { try await Task.sleep(for: .seconds(5)); throw ScriptedWaitFailure.deadline }
            defer { group.cancelAll() }
            let next = try await group.next()
            return try #require(next)
        }
    }
}

private actor DescendantCoordinatorRunner: ProcessRunning {
    let started = OneShotSignal()
    let stopped = OneShotSignal()
    let release = OneShotSignal()
    private let mode: String
    private var pid: Int32?
    private var directory: URL?
    init(mode: String) { self.mode = mode }
    func childPID() -> Int32? { pid }
    func staging() -> URL? { directory }
    private func accept(_ line: ProcessLine) async {
        if let value = Int32(String(decoding: line.bytes, as: UTF8.self)) {
            pid = value
            await started.signal()
        }
    }
    func run(_ command: ProcessCommand, onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult {
        if command.arguments.contains("--dump-single-json") {
            await onLine(.init(stream: .stdout, bytes: try TestSupport.fixture("single-video")))
            return .init(exitCode: 0)
        }
        let index = try #require(command.arguments.firstIndex(of: "-o"))
        directory = URL(fileURLWithPath: command.arguments[index + 1]).deletingLastPathComponent()
        do {
            return try await ProcessRunner().run(TestSupport.fixtureCommand([mode], timeout: nil)) { await self.accept($0) }
        } catch {
            await stopped.signal()
            // Await independently so task cancellation does not remove our deliberate
            // post-readers/pre-return test barrier.
            let barrier = Task.detached { try await self.release.wait() }
            try await barrier.value
            throw error
        }
    }
}

extension JobCoordinatorTests {
    @Test(arguments: [0, 1, 2])
    func unsafeShutdownIsLatchedAgainstAllRestartAttempts(origin: Int) async throws {
        let h = origin == 0 ? try CoordinatorHarness() : try await CoordinatorHarness.readyVideo()
        defer { h.remove() }
        if origin == 0 { await h.coordinator.preview(CoordinatorHarness.request) }
        else {
            await h.coordinator.download(preset: .mp4, destination: h.destination)
            let command = try await h.runner.waitForCommand(at: 1)
            if origin == 2 { await h.runner.resume(.init(lines: [try h.finalPathLine(for: command)]), at: 1) }
        }
        _ = try await h.runner.waitForCommand(at: origin)
        await h.runner.resume(.init(failure: .shutdownUnconfirmed(13)), at: origin)
        let failed = try await h.waitForTerminal()
        #expect(failed.phase == .failed && failed.issue == .shutdownUnconfirmed)
        let count = await h.runner.commands().count
        await h.coordinator.invalidatePreview()
        await h.coordinator.cancel()
        await h.coordinator.preview(CoordinatorHarness.request)
        await h.coordinator.download(preset: .mp4, destination: h.destination)
        await h.coordinator.shutdown()
        let after = try await h.waitForTerminal()
        #expect(after == failed)
        #expect(await h.runner.commands().count == count)
    }

    @Test func stalePreviewUnsafeShutdownStillBlocksPendingReplacement() async throws {
        let h = try CoordinatorHarness(); defer { h.remove() }
        await h.runner.holdCancellation(at: 0)
        await h.coordinator.preview(CoordinatorHarness.request)
        _ = try await h.runner.waitForCommand(at: 0)
        let replacing = Task { await h.coordinator.preview(.init(rawURL: "https://video.example.test/new", browser: .chrome)) }
        try await h.runner.waitForCancellation(at: 0)
        let newID = try await h.waitForPhase(.previewing).operationID
        await h.runner.resume(.init(failure: .shutdownUnconfirmed(13)), at: 0)
        await replacing.value
        let failed = try await h.waitForTerminal()
        #expect(failed.issue == .shutdownUnconfirmed && failed.operationID == newID)
        #expect(await h.runner.commands().count == 1)
    }
}
