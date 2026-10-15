import Foundation

/// Frames bytes before decoding. The cap includes a CR preceding LF.
public struct LineFramer: Sendable {
    private let limit: Int
    private var pending = Data()

    public init(limit: Int) { self.limit = max(0, limit) }

    public mutating func append(_ data: Data) throws -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        for index in data.indices where data[index] == 10 {
            try extend(data[start..<index])
            if pending.last == 13 { pending.removeLast() }
            lines.append(pending)
            pending = Data()
            start = data.index(after: index)
        }
        try extend(data[start..<data.endIndex])
        return lines
    }

    public mutating func finish() throws -> [Data] {
        guard !pending.isEmpty else { return [] }
        let line = pending
        pending = Data()
        return [line]
    }

    private mutating func extend(_ bytes: Data.SubSequence) throws {
        guard bytes.count <= limit - pending.count else { throw ProcessFailure.oversizedLine }
        pending.append(bytes)
    }
}
