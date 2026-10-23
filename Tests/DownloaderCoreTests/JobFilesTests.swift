import Darwin
import Foundation
import Testing
@testable import DownloaderCore

@Suite struct JobFilesTests {
    @Test func createsPrivateStagingAndRefusesExistingDirectory() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let id = UUID()
        let job = try files.create(id: id, destination: folder)
        #expect(job.id == id)
        #expect(job.directory == folder.appendingPathComponent(".media-downloader-" + id.uuidString))
        let attrs = try FileManager.default.attributesOfItem(atPath: job.directory.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(throws: (any Error).self) { try files.create(id: id, destination: folder) }
        try files.cleanup(job)
        #expect(!FileManager.default.fileExists(atPath: job.directory.path))
    }

    @Test(arguments: ["", "\u{0}\n\r\t/:\\", "  "])
    func emptySanitizedTitleFallsBack(title: String) throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let input = job.directory.appendingPathComponent("media.mp3"); try Data([1]).write(to: input)
        let result = try files.publish(candidate: input, job: job, title: title, preset: .mp3)
        #expect(result.lastPathComponent == "video-\(job.id.uuidString).mp3")
    }

    @Test func outputNameKeepsTitleInsideAByteBudget() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let input = job.directory.appendingPathComponent("media.mp4"); try Data([1]).write(to: input)
        let result = try files.publish(candidate: input, job: job,
            title: String(repeating: "😀", count: 200) + "/../%(title)s", preset: .mp4)
        #expect(result.deletingLastPathComponent() == folder)
        #expect(result.lastPathComponent.utf8.count <= 162)
        #expect(result.lastPathComponent == String(repeating: "😀", count: 30) + "-\(job.id.uuidString).mp4")
        #expect(try Data(contentsOf: result) == Data([1]))
        #expect(!FileManager.default.fileExists(atPath: input.path))
    }

    @Test func stripsControlsSeparatorsAndKeepsPercentAsFilenameData() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let input = job.directory.appendingPathComponent("media.mp4"); try Data([1]).write(to: input)
        let result = try files.publish(candidate: input, job: job, title: " a/\u{0}b:c\\d\n%(title)s  ", preset: .mp4)
        #expect(result.lastPathComponent == " abcd%(title)s-\(job.id.uuidString).mp4")
    }

    @Test func publicationNeverOverwritesAndFailurePreservesStaging() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let input = job.directory.appendingPathComponent("media.mp4"); try Data([1]).write(to: input)
        let output = folder.appendingPathComponent("same-\(job.id.uuidString).mp4"); try Data([2]).write(to: output)
        #expect(throws: (any Error).self) { try files.publish(candidate: input, job: job, title: "same", preset: .mp4) }
        #expect(try Data(contentsOf: output) == Data([2]))
        #expect(try Data(contentsOf: input) == Data([1]))
        let failing = JobFiles(publisher: FullDiskPublisher())
        #expect(throws: (any Error).self) { try failing.publish(candidate: input, job: job, title: "other", preset: .mp4) }
        #expect(try Data(contentsOf: input) == Data([1]))
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("other-\(job.id.uuidString).mp4").path))
    }

    @Test(arguments: ["missing", "empty", "symlink", "extension", "sibling", "traversal", "relative", "directory", "nul"])
    func rejectsUntrustedCandidate(kind: String) throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let expected = job.directory.appendingPathComponent("media.mp4")
        var path = expected.path
        switch kind {
        case "empty": try Data().write(to: expected)
        case "symlink":
            let target = folder.appendingPathComponent("outside"); try Data([1]).write(to: target)
            try FileManager.default.createSymbolicLink(at: expected, withDestinationURL: target)
        case "extension": path = job.directory.appendingPathComponent("media.mp3").path; try Data([1]).write(to: URL(fileURLWithPath: path))
        case "sibling":
            let sibling = URL(fileURLWithPath: job.directory.path + "-other"); try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
            path = sibling.appendingPathComponent("media.mp4").path; try Data([1]).write(to: URL(fileURLWithPath: path))
        case "traversal": try Data([1]).write(to: expected); path = job.directory.path + "/../" + job.directory.lastPathComponent + "/media.mp4"
        case "relative": try Data([1]).write(to: expected); path = "media.mp4"
        case "directory": try FileManager.default.createDirectory(at: expected, withIntermediateDirectories: false)
        case "nul": try Data([1]).write(to: expected); path += "\u{0}ignored"
        default: break
        }
        #expect(throws: (any Error).self) { try files.candidate(finalPath: path, job: job, preset: .mp4) }
        #expect(throws: (any Error).self) { try files.publish(candidate: URL(fileURLWithPath: path), job: job, title: "bad", preset: .mp4) }
    }

    @Test func candidateAcceptsOnlyExpectedFile() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let expected = job.directory.appendingPathComponent("media.mp4"); try Data([1]).write(to: expected)
        #expect(try files.candidate(finalPath: expected.path, job: job, preset: .mp4) == expected)
    }

    @Test(arguments: ["directory", "symlink"])
    func refusesReplacedStagingAndPreservesUnownedFiles(kind: String) throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let moved = folder.appendingPathComponent("original"); try FileManager.default.moveItem(at: job.directory, to: moved)
        let unowned = folder.appendingPathComponent("unowned"); try FileManager.default.createDirectory(at: unowned, withIntermediateDirectories: false)
        let sentinel = unowned.appendingPathComponent("keep"); try Data([9]).write(to: sentinel)
        if kind == "symlink" { try FileManager.default.createSymbolicLink(at: job.directory, withDestinationURL: unowned) }
        else { try FileManager.default.createDirectory(at: job.directory, withIntermediateDirectories: false) }
        #expect(throws: (any Error).self) { try files.cleanup(job) }
        #expect(throws: (any Error).self) { try files.candidate(finalPath: job.directory.appendingPathComponent("media.mp4").path, job: job, preset: .mp4) }
        #expect(try Data(contentsOf: sentinel) == Data([9]))
        #expect(FileManager.default.fileExists(atPath: job.directory.path))
    }

    @Test func cleanupDoesNotFollowNestedSymlinks() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let unowned = folder.appendingPathComponent("keep"); try Data([9]).write(to: unowned)
        let nested = job.directory.appendingPathComponent("nested"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("link"), withDestinationURL: unowned)
        try files.cleanup(job)
        #expect(try Data(contentsOf: unowned) == Data([9]))
        #expect(!FileManager.default.fileExists(atPath: job.directory.path))
    }

    @Test func refusesReplacedDestinationAndPreservesBothDirectories() throws {
        let root = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        let input = job.directory.appendingPathComponent("media.mp4"); try Data([1]).write(to: input)
        let moved = root.appendingPathComponent("moved"); try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createDirectory(at: job.directory, withIntermediateDirectories: true)
        let unowned = job.directory.appendingPathComponent("media.mp4"); try Data([9]).write(to: unowned)
        #expect(throws: (any Error).self) { try files.cleanup(job) }
        #expect(throws: (any Error).self) { try files.publish(candidate: unowned, job: job, title: "bad", preset: .mp4) }
        #expect(try Data(contentsOf: unowned) == Data([9]))
        #expect(try Data(contentsOf: moved.appendingPathComponent(job.directory.lastPathComponent).appendingPathComponent("media.mp4")) == Data([1]))
    }

    @Test func deletedDestinationFailsClosed() throws {
        let folder = try TestSupport.temporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let files = JobFiles(); let job = try files.create(id: UUID(), destination: folder)
        try FileManager.default.removeItem(at: folder)
        #expect(throws: (any Error).self) { try files.create(id: UUID(), destination: folder) }
        #expect(throws: (any Error).self) { try files.publish(candidate: job.directory.appendingPathComponent("media.mp4"), job: job, title: "title", preset: .mp4) }
        #expect(throws: (any Error).self) { try files.cleanup(job) }
    }
}

private struct FullDiskPublisher: FilePublishing {
    func moveExclusively(from: URL, to: URL) throws { throw POSIXError(.ENOSPC) }
}
