import Foundation

public enum ProcessStream: Sendable {
    case stdout, stderr
}

public struct ProcessLine: Sendable {
    public let stream: ProcessStream
    public let bytes: Data

    public init(stream: ProcessStream, bytes: Data) {
        self.stream = stream
        self.bytes = bytes
    }
}

public struct ProcessCommand: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let timeout: Duration?
    public let maximumLineBytes: Int

    public init(executable: URL, arguments: [String], environment: [String: String], timeout: Duration?, maximumLineBytes: Int) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.timeout = timeout
        self.maximumLineBytes = maximumLineBytes
    }
}

public struct ProcessResult: Sendable {
    public let exitCode: Int32

    public init(exitCode: Int32) {
        self.exitCode = exitCode
    }
}

public enum ProcessFailure: Error, Sendable {
    case launch(Int32), timeout, oversizedLine, read(Int32)
    /// Shutdown could not be confirmed. Callers MUST preserve owned staging.
    case shutdownUnconfirmed(Int32)
}

/// A runner owns process-group shutdown and pipe-reader cleanup before returning
/// or throwing. Nonzero exits are results; cancellation throws CancellationError
/// after cleanup, and deadlines follow the same shutdown path before timeout.
/// `shutdownUnconfirmed` takes precedence over cancellation/timeout and means
/// cleanup safety is unknown: callers must preserve staging for manual recovery.
public protocol ProcessRunning: Sendable {
    func run(_ command: ProcessCommand,
             onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult
}
