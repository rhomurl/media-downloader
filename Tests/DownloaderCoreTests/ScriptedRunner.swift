import Foundation
@testable import DownloaderCore

enum ScriptedFailure: Sendable { case timeout, launch, cancellation, shutdownUnconfirmed(Int32) }

struct ScriptedReply: Sendable {
    let lines: [ProcessLine]
    let exitCode: Int32
    let failure: ScriptedFailure?
    init(lines: [ProcessLine] = [], exitCode: Int32 = 0, failure: ScriptedFailure? = nil) {
        self.lines = lines; self.exitCode = exitCode; self.failure = failure
    }
    init(_ text: String, exitCode: Int32 = 0, stream: ProcessStream = .stdout) {
        self.init(lines: text.split(separator: "\n").map { ProcessLine(stream: stream, bytes: Data($0.utf8)) }, exitCode: exitCode)
    }
}

enum ScriptedWaitFailure: Error { case deadline }

/// Only execution is scripted. An absent reply suspends and observes cancellation.
/// Held cancellation models a runner still stopping descendants/draining readers.
actor ScriptedRunner: ProcessRunning {
    private var callbacks: [Int: @Sendable (ProcessLine) async -> Void] = [:]
    private var replies: [ScriptedReply]
    private var captured: [ProcessCommand] = []
    private var pending: [Int: CheckedContinuation<ScriptedReply, any Error>] = [:]
    private var resumed: [Int: ScriptedReply] = [:]
    private var heldCancellation: Set<Int> = []
    private var cancelled: Set<Int> = []
    private var commandWaiters: [UUID: (Int, CheckedContinuation<ProcessCommand, any Error>)] = [:]
    private var cancelWaiters: [UUID: (Int, CheckedContinuation<Void, any Error>)] = [:]

    init(replies: [ScriptedReply] = []) { self.replies = replies }
    func emit(_ line: ProcessLine, at index: Int) async { await callbacks[index]?(line) }
    func commands() -> [ProcessCommand] { captured }
    func append(_ reply: ScriptedReply) { replies.append(reply) }
    func holdCancellation(at index: Int) { heldCancellation.insert(index) }
    func resume(_ reply: ScriptedReply, at index: Int) {
        if let waiter = pending.removeValue(forKey: index) { waiter.resume(returning: reply) }
        else { resumed[index] = reply }
    }

    func waitForCommand(at index: Int) async throws -> ProcessCommand {
        if captured.indices.contains(index) { return captured[index] }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                commandWaiters[id] = (index, continuation)
                if Task.isCancelled { expire(id) }
                else { Task { try? await Task.sleep(for: .seconds(5)); self.expire(id) } }
            }
        } onCancel: { Task { await self.expire(id) } }
    }
    func waitForCancellation(at index: Int) async throws {
        if cancelled.contains(index) { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                cancelWaiters[id] = (index, continuation)
                if Task.isCancelled { expire(id) }
                else { Task { try? await Task.sleep(for: .seconds(5)); self.expire(id) } }
            }
        } onCancel: { Task { await self.expire(id) } }
    }
    private func expire(_ id: UUID) {
        commandWaiters.removeValue(forKey: id)?.1.resume(throwing: ScriptedWaitFailure.deadline)
        cancelWaiters.removeValue(forKey: id)?.1.resume(throwing: ScriptedWaitFailure.deadline)
    }
    private func didCancel(_ index: Int) {
        cancelled.insert(index)
        let ids = cancelWaiters.filter { $0.value.0 == index }.map(\.key)
        for id in ids { cancelWaiters.removeValue(forKey: id)?.1.resume() }
        if !heldCancellation.contains(index) { pending.removeValue(forKey: index)?.resume(throwing: CancellationError()) }
    }
    func run(_ command: ProcessCommand,
             onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult {
        let index = captured.count
        captured.append(command)
        callbacks[index] = onLine
        defer { callbacks[index] = nil }
        let ids = commandWaiters.filter { $0.value.0 == index }.map(\.key)
        for id in ids { commandWaiters.removeValue(forKey: id)?.1.resume(returning: command) }
        let reply: ScriptedReply
        if !replies.isEmpty { reply = replies.removeFirst() }
        else if let stored = resumed.removeValue(forKey: index) { reply = stored }
        else {
            reply = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    pending[index] = continuation
                    if Task.isCancelled { didCancel(index) }
                }
            } onCancel: { Task { await self.didCancel(index) } }
        }
        for line in reply.lines { await onLine(line) }
        switch reply.failure {
        case .timeout: throw ProcessFailure.timeout
        case .launch: throw ProcessFailure.launch(2)
        case .cancellation: throw CancellationError()
        case .shutdownUnconfirmed(let code): throw ProcessFailure.shutdownUnconfirmed(code)
        case nil:
            try Task.checkCancellation()
            return ProcessResult(exitCode: reply.exitCode)
        }
    }
}
