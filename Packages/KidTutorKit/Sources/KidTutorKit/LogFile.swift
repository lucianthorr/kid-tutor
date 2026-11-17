import Foundation

/// Appends log lines to one plain-text file per day (`kidtutor-2026-11-15.log`) and deletes
/// files older than `keepDays`. Writes happen on a private serial queue, so callers never block.
public final class LogFile: @unchecked Sendable {
    public enum Level: String, Sendable {
        case debug, info, warning, error
    }

    public let directory: URL
    public let keepDays: Int

    private let queue = DispatchQueue(label: "KidTutorKit.LogFile")
    private var handle: FileHandle?
    private var openDay: String?

    public init(directory: URL, keepDays: Int = 14) {
        self.directory = directory
        self.keepDays = keepDays
    }

    public func append(_ level: Level, _ category: String, _ message: String, at date: Date = Date()) {
        let line = Self.format(level, category, message, at: date)
        queue.async { self.write(line, at: date) }
    }

    /// Waits until everything appended so far is on disk.
    public func flush() {
        queue.sync { try? handle?.synchronize() }
    }

    public func fileURL(for date: Date) -> URL {
        directory.appendingPathComponent("kidtutor-\(Self.dayString(date)).log")
    }

    /// `2026-11-15 19:38:07.613 [error] recognition: Vision failed: …` in local time.
    /// Newlines inside the message are escaped so one event is always one line.
    public static func format(_ level: Level, _ category: String, _ message: String, at date: Date) -> String {
        let flat = message.replacingOccurrences(of: "\n", with: "\\n")
        return "\(timestampString(date)) [\(level.rawValue)] \(category): \(flat)\n"
    }

    // MARK: - Private, on `queue`

    private func write(_ line: String, at date: Date) {
        let day = Self.dayString(date)
        if day != openDay {
            try? handle?.close()
            handle = nil
            openDay = day
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL(for: date)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
            prune(now: date)
        }
        try? handle?.write(contentsOf: Data(line.utf8))
    }

    private func prune(now: Date) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let cutoff = Self.dayString(now.addingTimeInterval(-Double(keepDays) * 86_400))
        for file in files where file.lastPathComponent.hasPrefix("kidtutor-") && file.pathExtension == "log" {
            let day = file.deletingPathExtension().lastPathComponent.dropFirst("kidtutor-".count)
            if day < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    // MARK: - Dates

    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func timestampString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let millis = (c.nanosecond ?? 0) / 1_000_000
        return dayString(date) + String(format: " %02d:%02d:%02d.%03d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, millis)
    }
}

extension Ink {
    /// One-line summary for logs: stroke and point counts, bounds, and any non-finite values.
    public var logSummary: String {
        let points = strokes.flatMap(\.points)
        let nonFinite = points.filter { !$0.x.isFinite || !$0.y.isFinite || !$0.t.isFinite || !$0.force.isFinite }.count
        var parts = ["strokes=\(strokes.count)", "points=\(points.count)", "canvas=\(Int(canvasWidth))x\(Int(canvasHeight))"]
        if let b = bounds {
            parts.append(String(format: "bounds=%.0f,%.0f %.0fx%.0f", b.minX, b.minY, b.width, b.height))
        }
        if nonFinite > 0 { parts.append("NONFINITE=\(nonFinite)") }
        return parts.joined(separator: " ")
    }

    public var hasNonFiniteValues: Bool {
        strokes.contains { $0.points.contains { !$0.x.isFinite || !$0.y.isFinite || !$0.t.isFinite || !$0.force.isFinite } }
    }
}
