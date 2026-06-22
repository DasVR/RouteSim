import Foundation

final class LogManager {
    static let shared = LogManager()

    private let maxEntries = 200
    private var entries: [LogEntry] = []
    private let lock = NSLock()

    private init() {}

    func addInfoLog(_ message: String) {
        append(LogEntry(level: .info, message: message))
    }

    func addErrorLog(_ message: String) {
        append(LogEntry(level: .error, message: message))
    }

    func recentLogs() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    private func append(_ entry: LogEntry) {
        lock.lock()
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst() }
        lock.unlock()
    }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let level: Level
    let message: String

    enum Level { case info, error }
}
