import Darwin
import Foundation
import Testing
@testable import DownloaderCore

struct ProcessRunnerTests {
    @Test func floodsBothPipesWithoutDeadlock() async throws {
        let sink = TestLineSink()
        let result = try await ProcessRunner().run(TestSupport.fixtureCommand(["flood", "2097152"], timeout: .seconds(15))) {
            await sink.accept($0)
        }
        #expect(result.exitCode == 0)
        #expect(await sink.streamsSeen() == Set(["stdout", "stderr"]))
    }

    @Test func returnsNonzeroAndSignalExit() async throws {
        let runner = ProcessRunner()
        #expect(try await runner.run(TestSupport.fixtureCommand(["exit", "7"])) { _ in }.exitCode == 7)
        #expect(try await runner.run(TestSupport.fixtureCommand(["signal"])) { _ in }.exitCode == 128 + SIGTERM)
    }

    @Test func oversizedOutputStopsTheProcess() async {
        await #expect(throws: ProcessFailure.self) {
            try await ProcessRunner().run(TestSupport.fixtureCommand(["long-line"])) { _ in }
        }
    }

    @Test func concurrentInvocationsKeepCancellationSeparate() async throws {
        let runner = ProcessRunner()
        let latch = PIDLatch()
        let cancelled = Task {
            try await runner.run(TestSupport.fixtureCommand(["fork-hold"], timeout: nil)) { await latch.accept($0) }
        }
        defer { cancelled.cancel() }
        let pid = try await latch.pid()
        cancelled.cancel()
        let result = try await runner.run(TestSupport.fixtureCommand(["exit", "9"])) { _ in }
        #expect(result.exitCode == 9)
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        try await TestSupport.assertGone(pid)
    }

    @Test func launchesWithClosedStandardDescriptors() async throws {
        let sink = TestLineSink()
        let result = try await ProcessRunner().run(TestSupport.fixtureCommand(["closed-stdio"])) { await sink.accept($0) }
        #expect(result.exitCode == 0)
        #expect(await sink.lines().map { String(decoding: $0.bytes, as: UTF8.self) } == ["[\"intact\"]"])
    }

    @Test func reportsLaunchFailure() async {
        let command = ProcessCommand(executable: URL(fileURLWithPath: "/nonexistent/fixture"), arguments: [], environment: [:], timeout: nil, maximumLineBytes: 64)
        await #expect(throws: ProcessFailure.self) { try await ProcessRunner().run(command) { _ in } }
    }

    @Test func passesArgumentsWithoutShellInterpretationAndDrainsEOF() async throws {
        let sink = TestLineSink()
        let args = ["a b", "$(touch nope)", "☃", "--flag", "a\nb"]
        _ = try await ProcessRunner().run(TestSupport.fixtureCommand(["echo-arguments"] + args)) { await sink.accept($0) }
        let lines = await sink.lines()
        #expect(lines.count == 1)
        let actual = try JSONDecoder().decode([String].self, from: #require(lines.first).bytes)
        #expect(actual == args)
    }

    @Test func immediateAndRepeatedCancellation() async throws {
        let runner = ProcessRunner()
        for _ in 0..<3 {
            let task = Task { try await runner.run(TestSupport.fixtureCommand(["sleep", "30"], timeout: nil)) { _ in } }
            task.cancel()
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test func timesOutAfterGroupCleanup() async {
        await #expect(throws: ProcessFailure.self) {
            try await ProcessRunner().run(TestSupport.fixtureCommand(["sleep", "30"], timeout: .milliseconds(30))) { _ in }
        }
    }

    @Test(arguments: ["fork-hold", "orphan-hold"])
    func cancellationStopsDescendantBeforeReturning(mode: String) async throws {
        let latch = PIDLatch()
        let release = TestLatch()
        let task = Task {
            try await ProcessRunner().run(TestSupport.fixtureCommand([mode], timeout: nil)) {
                await latch.accept($0)
                await release.wait()
            }
        }
        defer {
            task.cancel()
            Task { await release.open() }
        }
        let pid = try await latch.pid()
        let start = ContinuousClock.now
        task.cancel()
        task.cancel()
        await release.open()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(start.duration(to: .now) < .seconds(5))
        if mode == "fork-hold" { #expect(start.duration(to: .now) >= .seconds(2)) }
        try await TestSupport.assertGone(pid)
    }

    @Test func naturalParentExitStopsOrphan() async throws {
        let latch = PIDLatch()
        _ = try await ProcessRunner().run(TestSupport.fixtureCommand(["orphan-hold"])) { await latch.accept($0) }
        try await TestSupport.assertGone(try await latch.pid())
    }

    @Test(arguments: ["flood-lines", "flood-wide"])
    func overflowStopsProducerWithoutBlockingReader(mode: String) async throws {
        let pid = PIDLatch()
        let release = TestLatch()
        let task = Task {
            try await ProcessRunner().run(TestSupport.fixtureCommand([mode], timeout: .seconds(25), limit: 1_048_576)) { line in
                await pid.accept(line)
                await release.wait()
            }
        }
        defer {
            task.cancel()
            Task { await release.open() }
        }
        // The first callback is held until the producer has stopped. A dropped
        // event must fail the operation; silent truncation would return success.
        try await TestSupport.assertGone(try await pid.pid(), timeout: .seconds(20))
        await release.open()
        do {
            _ = try await task.value
            Issue.record("Expected bounded delivery overflow")
        } catch ProcessFailure.read(let code) {
            #expect(code == ENOBUFS)
        }
    }

    @Test func callbackCompletesBeforeRunReturns() async throws {
        let pid = PIDLatch()
        let release = TestLatch()
        let completed = TestFlag()
        let task = Task {
            let result = try await ProcessRunner().run(TestSupport.fixtureCommand(["report-pid"])) { line in
                await pid.accept(line)
                await release.wait()
                await completed.mark()
            }
            #expect(await completed.value())
            return result
        }
        defer {
            task.cancel()
            Task { await release.open() }
        }
        // Observe direct-child reaping before allowing the callback to finish.
        try await TestSupport.assertGone(try await pid.pid())
        await release.open()
        #expect(try await task.value.exitCode == 0)
    }

    @Test func cancellationRacingTimeoutStillCleansDescendant() async throws {
        let latch = PIDLatch()
        let task = Task {
            try await ProcessRunner().run(TestSupport.fixtureCommand(["fork-hold"], timeout: .seconds(1))) { await latch.accept($0) }
        }
        defer {
            task.cancel()
        }
        let pid = try await latch.pid()
        // Exercise cancellation while the deadline shutdown can also be in flight.
        try await Task.sleep(for: .seconds(1))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation or timeout") }
        catch is CancellationError { }
        catch ProcessFailure.timeout { }
        try await TestSupport.assertGone(pid)
    }

}
