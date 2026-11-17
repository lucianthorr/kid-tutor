import Foundation

/// A small JSON file holding one value, such as a progress file. Missing files load as empty.
public protocol JSONFile: Codable, Sendable {
    init()
}

extension JSONFile {
    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// One handwriting box in an exercise (a spelling blank, a digit of a math answer).
public struct AnswerBox: Hashable, Sendable {
    public enum Feedback: Equatable, Sendable {
        case accepted
        /// First miss: clear the box and try again.
        case tryAgain
        /// Second miss: clear the box and show the answer faded to trace.
        case trace
    }

    public var ink = Ink.empty
    /// Bumped to clear the canvas.
    public var clearToken = 0
    public var accepted = false
    public var misses = 0
    public var showTrace = false
    /// The exercise itself is tracing (Writing's first level), so the faded letter isn't a hint.
    public private(set) var startedWithTrace = false
    public var lastWasWrong = false

    public init(trace: Bool = false) {
        showTrace = trace
        startedWithTrace = trace
    }

    /// Applies a verdict on what was written in this box.
    public mutating func judge(_ verdict: LetterCheck.Verdict) -> Feedback {
        if verdict != .incorrect {
            accepted = true
            lastWasWrong = false
            return .accepted
        }
        misses += 1
        lastWasWrong = true
        ink = .empty
        clearToken += 1
        if misses >= 2 {
            showTrace = true
            return .trace
        }
        return .tryAgain
    }

    /// How an exercise went, from its boxes: any trace or help means hinted, any miss means retried.
    /// A box that was a tracing exercise from the start doesn't count as hinted.
    public static func outcome(of boxes: some Collection<AnswerBox>, usedHelp: Bool) -> WordProgress.Outcome {
        if usedHelp || boxes.contains(where: { $0.showTrace && !$0.startedWithTrace }) { return .hinted }
        return boxes.contains { $0.misses > 0 } ? .retried : .firstTry
    }
}
