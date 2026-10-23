import Darwin
import Foundation

public enum JobFileFailure: Error, Equatable, Sendable {
    case invalidDestination, ownership, invalidCandidate, filesystem(Int32)
}

private struct FileIdentity: Sendable {
    let device: dev_t
    let inode: ino_t
    init(_ info: stat) { device = info.st_dev; inode = info.st_ino }
    func matches(_ info: stat) -> Bool { device == info.st_dev && inode == info.st_ino }
}

/// An ownership token created only after this process creates the private directory.
public struct StagedJob: Sendable {
    public let id: UUID
    public let directory: URL
    public let destination: URL
    fileprivate let identity: FileIdentity
    fileprivate let destinationIdentity: FileIdentity

    fileprivate init(id: UUID, directory: URL, destination: URL, identity: FileIdentity, destinationIdentity: FileIdentity) {
        self.id = id; self.directory = directory; self.destination = destination
        self.identity = identity; self.destinationIdentity = destinationIdentity
    }
}

public protocol FilePublishing: Sendable {
    func moveExclusively(from: URL, to: URL) throws
}

/// Same-filesystem, exclusive atomic publication. No existence-check/rename gap.
public struct DarwinFilePublisher: FilePublishing {
    public init() {}
    public func moveExclusively(from: URL, to: URL) throws {
        guard FileSafety.absoluteFileURL(from), FileSafety.absoluteFileURL(to) else { throw JobFileFailure.invalidCandidate }
        guard renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) == 0 else { throw JobFileFailure.filesystem(errno) }
    }
}

public struct JobFiles: Sendable {
    private let publisher: any FilePublishing
    public init(publisher: any FilePublishing = DarwinFilePublisher()) { self.publisher = publisher }

    public func create(id: UUID, destination: URL) throws -> StagedJob {
        guard FileSafety.absoluteFileURL(destination) else { throw JobFileFailure.invalidDestination }
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        let parent = open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw JobFileFailure.invalidDestination }
        defer { close(parent) }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0 else { throw JobFileFailure.filesystem(errno) }
        let name = ".media-downloader-" + id.uuidString
        guard mkdirat(parent, name, 0o700) == 0 else { throw JobFileFailure.filesystem(errno) }
        // Fail closed if anything changed before ownership could be captured.
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else {
            throw JobFileFailure.ownership
        }
        return StagedJob(id: id, directory: destination.appendingPathComponent(name), destination: destination,
                         identity: FileIdentity(info), destinationIdentity: FileIdentity(parentInfo))
    }

    public func candidate(finalPath: String, job: StagedJob, preset: OutputPreset) throws -> URL {
        guard finalPath.hasPrefix("/"), !finalPath.contains("\u{0}"),
              !finalPath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." }) else {
            throw JobFileFailure.invalidCandidate
        }
        let url = URL(fileURLWithPath: finalPath)
        let expected = job.directory.appendingPathComponent("media." + preset.rawValue)
        guard url.pathComponents == expected.pathComponents else { throw JobFileFailure.invalidCandidate }
        let handles = try ownedHandles(job)
        defer { close(handles.directory); close(handles.parent) }
        try FileSafety.nonemptyRegularFile(url, preset: preset)
        return expected
    }

    public func publish(candidate: URL, job: StagedJob, title: String, preset: OutputPreset) throws -> URL {
        guard FileSafety.absoluteFileURL(candidate) else { throw JobFileFailure.invalidCandidate }
        let input = try self.candidate(finalPath: candidate.path, job: job, preset: preset)
        let output = job.destination.appendingPathComponent(Self.filenameTitle(title) + "-" + job.id.uuidString + "." + preset.rawValue)
        // Validate identities immediately before path-based publication. Concurrent hostile
        // same-user renames during the syscall are outside this personal-app threat model.
        let handles = try ownedHandles(job)
        defer { close(handles.directory); close(handles.parent) }
        try publisher.moveExclusively(from: input, to: output)
        return output
    }

    /// The coordinator must call this only after owned children/readers are confirmed
    /// stopped. In particular it MUST NOT call cleanup after shutdownUnconfirmed.
    public func cleanup(_ job: StagedJob) throws {
        let handles = try ownedHandles(job)
        defer { close(handles.directory); close(handles.parent) }
        try Self.removeContents(of: handles.directory, device: job.identity.device, depth: 0)
        var current = stat()
        guard fstatat(handles.parent, job.directory.lastPathComponent, &current, AT_SYMLINK_NOFOLLOW) == 0,
              job.identity.matches(current), current.st_mode & S_IFMT == S_IFDIR else { throw JobFileFailure.ownership }
        guard unlinkat(handles.parent, job.directory.lastPathComponent, AT_REMOVEDIR) == 0 else { throw JobFileFailure.filesystem(errno) }
    }

    private func ownedHandles(_ job: StagedJob) throws -> (parent: Int32, directory: Int32) {
        let parent = open(job.destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw JobFileFailure.ownership }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0, job.destinationIdentity.matches(parentInfo) else {
            close(parent); throw JobFileFailure.ownership
        }
        let directory = openat(parent, job.directory.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { close(parent); throw JobFileFailure.ownership }
        var info = stat()
        guard fstat(directory, &info) == 0, job.identity.matches(info), info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else {
            close(directory); close(parent); throw JobFileFailure.ownership
        }
        return (parent, directory)
    }

    private static func filenameTitle(_ title: String) -> String {
        var result = ""
        var count = 0
        for scalar in title.unicodeScalars {
            guard !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.illegalCharacters.contains(scalar),
                  scalar != "/", scalar != ":", scalar != "\\" else { continue }
            let next = String(scalar)
            guard count + next.utf8.count <= 120 else { break }
            result.unicodeScalars.append(scalar); count += next.utf8.count
        }
        while let last = result.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
            result.unicodeScalars.removeLast()
        }
        return result.isEmpty ? "video" : result
    }

    /// Descriptor-relative traversal never follows symlinks, including nested links.
    /// Any uncertain identity/mount/race leaves the remaining contents for recovery.
    private static func removeContents(of directory: Int32, device: dev_t, depth: Int) throws {
        guard depth < 128 else { throw JobFileFailure.ownership }
        let copy = dup(directory)
        guard copy >= 0 else { throw JobFileFailure.filesystem(errno) }
        guard let stream = fdopendir(copy) else { let code = errno; close(copy); throw JobFileFailure.filesystem(code) }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw JobFileFailure.filesystem(errno) }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            var info = stat()
            guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0, info.st_dev == device else {
                throw JobFileFailure.ownership
            }
            if info.st_mode & S_IFMT == S_IFDIR {
                let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard child >= 0 else { throw JobFileFailure.ownership }
                defer { close(child) }
                var opened = stat()
                guard fstat(child, &opened) == 0, FileIdentity(info).matches(opened) else { throw JobFileFailure.ownership }
                try removeContents(of: child, device: device, depth: depth + 1)
                var current = stat()
                guard fstatat(directory, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                      FileIdentity(info).matches(current) else { throw JobFileFailure.ownership }
                guard unlinkat(directory, name, AT_REMOVEDIR) == 0 else { throw JobFileFailure.filesystem(errno) }
            } else {
                guard unlinkat(directory, name, 0) == 0 else { throw JobFileFailure.filesystem(errno) }
            }
        }
    }
}

enum FileSafety {
    static func absoluteFileURL(_ url: URL) -> Bool {
        url.isFileURL && url.host.map({ $0.isEmpty || $0 == "localhost" }) != false
            && url.path.hasPrefix("/") && !url.path.contains("\u{0}")
    }

    static func nonemptyRegularFile(_ url: URL, preset: OutputPreset) throws {
        guard absoluteFileURL(url), url.pathExtension == preset.rawValue else { throw JobFileFailure.invalidCandidate }
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0 else {
            throw JobFileFailure.invalidCandidate
        }
    }
}
