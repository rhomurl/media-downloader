import Darwin
import Foundation
import Testing
@testable import DownloaderCore

enum TestSupport {
    static func fixtureCommand(_ args: [String], timeout: Duration? = .seconds(5), limit: Int = 65_536) -> ProcessCommand {
        let path = ProcessInfo.processInfo.environment["MEDIA_DOWNLOADER_FIXTURE_PATH"]
            ?? FileManager.default.currentDirectoryPath + "/.build/debug/ProcessFixture"
        return ProcessCommand(executable: URL(fileURLWithPath: path), arguments: args,
                              environment: ["PATH": "/usr/bin:/bin", "LANG": "C"],
                              timeout: timeout, maximumLineBytes: limit)
    }

    static func assertGone(_ pid: pid_t, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while kill(pid, 0) == 0 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(kill(pid, 0) == -1 && errno == ESRCH)
    }
}

actor TestLineSink {
    private var captured: [ProcessLine] = []
    private var streams: Set<String> = []
    func accept(_ line: ProcessLine) {
        streams.insert(line.stream == .stdout ? "stdout" : "stderr")
        if captured.count < 32 { captured.append(line) }
    }
    func streamsSeen() -> Set<String> { streams }
    func lines() -> [ProcessLine] { captured }
}

actor TestLatch {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor PIDLatch {
    private var value: pid_t?
    func accept(_ line: ProcessLine) {
        guard let pid = Int32(String(decoding: line.bytes, as: UTF8.self)) else { return }
        value = pid
    }
    func pid() async throws -> pid_t {
        let deadline = ContinuousClock.now + .seconds(3)
        while value == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        return try #require(value, "Fixture did not report a child PID")
    }
}

actor TestFlag {
    private var marked = false
    func mark() { marked = true }
    func value() -> Bool { marked }
}
