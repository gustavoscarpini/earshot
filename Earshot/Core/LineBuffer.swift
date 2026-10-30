import Foundation

/// Splits a byte stream into newline-terminated lines.
///
/// A pipe delivers arbitrary chunks, so a line may arrive in pieces. The buffer
/// keeps the unterminated tail until the rest arrives.
struct LineBuffer {
    private var pending = Data()

    /// Appends a chunk and returns the lines it completed, in order, without the
    /// trailing newline. Empty lines are skipped.
    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            if !line.isEmpty {
                lines.append(Data(line))
            }
            pending = Data(pending[pending.index(after: newline)...])
        }
        return lines
    }
}
