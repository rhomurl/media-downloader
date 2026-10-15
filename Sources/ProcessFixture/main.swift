import Darwin
import Foundation
import ProcessFixtureSupport
import DownloaderCore

func writeAll(_ fd: Int32, _ data: Data) {
    data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(fd, bytes.baseAddress! + offset, bytes.count - offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { _exit(90) }
            offset += count
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "flood":
    let count = Int(args.dropFirst().first ?? "0") ?? 0
    let line = Data((String(repeating: "x", count: 4095) + "\n").utf8)
    var remaining = count
    while remaining > 0 {
        let bytes = Data(line.prefix(min(remaining, line.count)))
        writeAll(STDOUT_FILENO, bytes)
        writeAll(STDERR_FILENO, bytes)
        remaining -= bytes.count
    }
case "flood-lines":
    writeAll(STDOUT_FILENO, Data("\(getpid())\n".utf8))
    writeAll(STDOUT_FILENO, Data(repeating: 10, count: 65_536))
    sleep(30)
case "flood-wide":
    writeAll(STDOUT_FILENO, Data("\(getpid())\n".utf8))
    let line = Data((String(repeating: "x", count: 1_048_575) + "\n").utf8)
    for _ in 0..<40 { writeAll(STDOUT_FILENO, line) }
    sleep(30)
case "report-pid":
    writeAll(STDOUT_FILENO, Data("\(getpid())\n".utf8))
case "closed-stdio":
    let saved = dup(STDOUT_FILENO)
    close(STDIN_FILENO)
    close(STDOUT_FILENO)
    close(STDERR_FILENO)
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    let command = ProcessCommand(executable: executable, arguments: ["echo-arguments", "intact"],
                                 environment: [:], timeout: .seconds(3), maximumLineBytes: 64)
    do {
        let result = try await ProcessRunner().run(command) { line in
            writeAll(saved, line.bytes)
        }
        _exit(result.exitCode)
    } catch { _exit(95) }
case "sleep":
    sleep(UInt32(args.dropFirst().first ?? "1") ?? 1)
case "exit":
    _exit(Int32(args.dropFirst().first ?? "0") ?? 0)
case "signal":
    raise(SIGTERM)
case "fork-hold", "orphan-hold":
    fixture_fork_hold(args[0] == "orphan-hold" ? 1 : 0)
case "echo-arguments":
    writeAll(STDOUT_FILENO, try JSONEncoder().encode(Array(args.dropFirst())))
case "long-line":
    writeAll(STDOUT_FILENO, Data(repeating: 65, count: 131_072))
default:
    _exit(93)
}
