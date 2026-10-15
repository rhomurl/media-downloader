import Foundation
@testable import DownloaderCore

enum ScriptedFailure: Sendable { case timeout, launch }

struct ScriptedReply: Sendable {
    let lines: [ProcessLine]
    let exitCode: Int32
    let failure: ScriptedFailure?

    init(lines: [ProcessLine] = [], exitCode: Int32 = 0, failure: ScriptedFailure? = nil) {
        self.lines = lines
        self.exitCode = exitCode
        self.failure = failure
    }

    init(_ text: String, exitCode: Int32 = 0, stream: ProcessStream = .stdout) {
        self.init(lines: text.split(separator: "\n").map {
            ProcessLine(stream: stream, bytes: Data($0.utf8))
        }, exitCode: exitCode)
    }
}

/// Substitutes only process execution. Filesystem checks remain real.
actor ScriptedRunner: ProcessRunning {
    private var replies: [ScriptedReply]
    private var captured: [ProcessCommand] = []
    init(replies: [ScriptedReply]) { self.replies = replies }
    func commands() -> [ProcessCommand] { captured }
    func append(_ reply: ScriptedReply) { replies.append(reply) }

    func run(_ command: ProcessCommand,
             onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult {
        captured.append(command)
        guard !replies.isEmpty else { throw ProcessFailure.launch(2) }
        let reply = replies.removeFirst()
        for line in reply.lines { await onLine(line) }
        switch reply.failure {
        case .timeout: throw ProcessFailure.timeout
        case .launch: throw ProcessFailure.launch(2)
        case nil: return ProcessResult(exitCode: reply.exitCode)
        }
    }
}
