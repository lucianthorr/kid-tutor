import Foundation
import OSLog
import KidTutorKit

/// App logging. Every event goes to Apple's unified log (Console.app, `log show`) and to a daily
/// text file in Documents/Logs, which can be read from the simulator container or the Files app.
enum Log {
    enum Category: String {
        case app, speech, ink, calibration, test, recognition, storage, settings, spelling, math, reading, writing, puzzles, rewards
    }

    static let subsystem = Bundle.main.bundleIdentifier ?? "kidtutor"

    static let file = LogFile(
        directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
    )

    static func debug(_ category: Category, _ message: String) { write(.debug, category, message) }
    static func info(_ category: Category, _ message: String) { write(.info, category, message) }
    static func warning(_ category: Category, _ message: String) { write(.warning, category, message) }
    static func error(_ category: Category, _ message: String) { write(.error, category, message) }

    private static func write(_ level: LogFile.Level, _ category: Category, _ message: String) {
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        file.append(level, category.rawValue, message)
    }

    /// Milliseconds since `start`, for timing log lines.
    static func elapsed(since start: ContinuousClock.Instant) -> String {
        let duration = ContinuousClock.now - start
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        return String(format: "%.0fms", ms)
    }
}

extension Array where Element == RecognitionCandidate {
    var logDescription: String {
        isEmpty ? "none" : map { "\($0.label):\(String(format: "%.2f", $0.score))" }.joined(separator: " ")
    }
}
