import Darwin
import Foundation

/// Each invocation owns independent state, so actor reentrancy cannot replace a
/// running process or redirect cancellation to a different invocation.
/// `onLine` runs serially and must return promptly: delivery is joined before
/// this method returns, including cancellation, so no callback outlives the run.
public actor ProcessRunner: ProcessRunning {
    public init() { }

    public func run(_ command: ProcessCommand,
                    onLine: @escaping @Sendable (ProcessLine) async -> Void) async throws -> ProcessResult {
        let run = ProcessInvocation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            // One serial consumer. Readers never wait for an asynchronous client.
            let delivery = Task.detached {
                for await line in run.events {
                    await onLine(line)
                    run.consumed(line.bytes.count)
                }
            }
            let result: Result<ProcessResult, Error> = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try run.execute(command) }
                    run.finish()
                    continuation.resume(returning: result)
                }
            }
            await delivery.value
            try Task.checkCancellation()
            return try result.get()
        } onCancel: {
            run.stop(CancellationError())
        }
    }
}

/// Lock protects only small bookkeeping operations; all POSIX waits and reads
/// run on dedicated dispatch workers, never the Swift cooperative executor.
private final class ProcessInvocation: @unchecked Sendable {
    let events: AsyncStream<ProcessLine>
    private let continuation: AsyncStream<ProcessLine>.Continuation
    private let lock = NSLock()
    private var failure: (any Error)?
    private var queuedBytes = 0
    private let maximumQueuedBytes = 32 * 1024 * 1024

    init() {
        let pair = AsyncStream<ProcessLine>.makeStream(bufferingPolicy: .bufferingOldest(4096))
        events = pair.stream
        continuation = pair.continuation
    }

    func stop(_ error: any Error) {
        lock.withLock { if failure == nil { failure = error } }
    }
    private var error: (any Error)? { lock.withLock { failure } }
    func consumed(_ count: Int) { lock.withLock { queuedBytes -= count } }
    func finish() { continuation.finish() }

    private func offer(_ line: ProcessLine) {
        let accepted = lock.withLock {
            guard failure == nil else { return false }
            guard line.bytes.count <= maximumQueuedBytes - queuedBytes else {
                failure = ProcessFailure.read(ENOBUFS)
                return false
            }
            queuedBytes += line.bytes.count
            return true
        }
        guard accepted else { return }
        switch continuation.yield(line) {
        case .enqueued: break
        case .dropped, .terminated:
            consumed(line.bytes.count)
            stop(ProcessFailure.read(ENOBUFS))
        @unknown default: stop(ProcessFailure.read(ENOBUFS))
        }
    }

    private func readPipe(_ fd: Int32, stream: ProcessStream, limit: Int) {
        defer { close(fd) }
        var framer = LineFramer(limit: limit)
        var buffer = [UInt8](repeating: 0, count: 4096)
        do {
            while true {
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw ProcessFailure.read(errno)
                }
                if count == 0 { break }
                // Continue draining after a failure, without retaining output.
                if error != nil { continue }
                for bytes in try framer.append(Data(buffer.prefix(count))) {
                    offer(ProcessLine(stream: stream, bytes: bytes))
                }
            }
            if error == nil {
                for bytes in try framer.finish() { offer(ProcessLine(stream: stream, bytes: bytes)) }
            }
        } catch { stop(error) }
    }

    private func makePipe() throws -> [Int32] {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard pipe(&descriptors) == 0 else { throw ProcessFailure.launch(errno) }
        // Finder/GUI launches may have closed standard streams. Keep pipe
        // sources above 2 so child close actions cannot undo stdin/stdout wiring.
        for index in descriptors.indices {
            if descriptors[index] <= STDERR_FILENO {
                let replacement = fcntl(descriptors[index], F_DUPFD_CLOEXEC, 3)
                if replacement < 0 {
                    let code = errno
                    descriptors.forEach { close($0) }
                    throw ProcessFailure.launch(code)
                }
                close(descriptors[index])
                descriptors[index] = replacement
            }
        }
        return descriptors
    }

    func execute(_ command: ProcessCommand) throws -> ProcessResult {
        if let error { throw error }
        guard command.executable.isFileURL, command.executable.path.hasPrefix("/"),
              command.maximumLineBytes > 0,
              !([command.executable.path] + command.arguments).contains(where: { $0.utf8.contains(0) }),
              !command.environment.contains(where: { $0.key.isEmpty || $0.key.contains("=") || $0.key.utf8.contains(0) || $0.value.utf8.contains(0) })
        else { throw ProcessFailure.launch(EINVAL) }

        var out = try makePipe()
        var err: [Int32]
        do { err = try makePipe() }
        catch {
            out.forEach { close($0) }
            throw error
        }
        var parentOwnsReaders = true
        defer {
            close(out[1]); close(err[1])
            if parentOwnsReaders { close(out[0]); close(err[0]) }
        }
        var actions: posix_spawn_file_actions_t?
        let actionError = posix_spawn_file_actions_init(&actions)
        guard actionError == 0 else { throw ProcessFailure.launch(actionError) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        func check(_ code: Int32) throws {
            if code != 0 { throw ProcessFailure.launch(code) }
        }
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO))
        for fd in out + err { try check(posix_spawn_file_actions_addclose(&actions, fd)) }

        var attributes: posix_spawnattr_t?
        let initError = posix_spawnattr_init(&attributes)
        guard initError == 0 else { throw ProcessFailure.launch(initError) }
        defer { posix_spawnattr_destroy(&attributes) }
        let groupError = posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        var mask = sigset_t()
        sigfillset(&defaults)
        sigemptyset(&mask)
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        let flagsError = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        guard groupError == 0 else { throw ProcessFailure.launch(groupError) }
        guard flagsError == 0 else { throw ProcessFailure.launch(flagsError) }

        let argv = ([command.executable.path] + command.arguments).map { strdup($0) }
        let env = command.environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") }
        defer { (argv + env).forEach { free($0) } }
        guard (argv + env).allSatisfy({ $0 != nil }) else { throw ProcessFailure.launch(ENOMEM) }
        var pid: pid_t = 0
        let spawnError = (argv + [nil]).withUnsafeBufferPointer { arguments in
            (env + [nil]).withUnsafeBufferPointer { environment in
                posix_spawn(&pid, command.executable.path, &actions, &attributes,
                            UnsafeMutablePointer(mutating: arguments.baseAddress!),
                            UnsafeMutablePointer(mutating: environment.baseAddress!))
            }
        }
        guard spawnError == 0 else { throw ProcessFailure.launch(spawnError) }
        close(out[1]); out[1] = -1
        close(err[1]); err[1] = -1
        parentOwnsReaders = false
        let readers = DispatchGroup()
        for (fd, stream) in [(out[0], ProcessStream.stdout), (err[0], ProcessStream.stderr)] {
            readers.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                self.readPipe(fd, stream: stream, limit: command.maximumLineBytes)
                readers.leave()
            }
        }

        let clock = ContinuousClock()
        let deadline = command.timeout.map { clock.now + $0 }
        var terminationStarted: ContinuousClock.Instant?
        while true {
            var info = siginfo_t()
            let observed = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
            if observed < 0 && errno != EINTR { stop(ProcessFailure.read(errno)) }
            if observed == 0 && info.si_pid == pid && terminationStarted == nil {
                // Keep the leader waitable until the FINAL group signal. This
                // prevents pgid reuse, including when an orphan holds the pipes.
                // A naturally completed leader grants no grace to residual work.
                kill(-pid, SIGKILL)
                break
            }
            if let deadline, clock.now >= deadline { stop(ProcessFailure.timeout) }
            if error != nil && terminationStarted == nil {
                kill(-pid, SIGTERM)
                terminationStarted = clock.now
            }
            if let terminationStarted, clock.now - terminationStarted >= .seconds(2) {
                kill(-pid, SIGKILL)
                break
            }
            // A short blocking wait belongs to this dispatch worker, not an actor.
            usleep(5_000)
        }
        var status: Int32 = 0
        var waited: pid_t
        repeat { waited = waitpid(pid, &status, 0) } while waited < 0 && errno == EINTR
        if waited < 0 { stop(ProcessFailure.read(errno)) }
        readers.wait()
        if let error { throw error }
        let signal = status & 0x7f
        let exitCode = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        return ProcessResult(exitCode: exitCode)
    }
}
