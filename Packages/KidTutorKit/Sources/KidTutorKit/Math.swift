import Foundation

public enum MathOperation: String, Codable, Sendable {
    case add, subtract

    public var symbol: String { self == .add ? "+" : "−" }
    public var spoken: String { self == .add ? "plus" : "minus" }
}

/// One number fact, such as 3 + 4 = 7.
public struct MathFact: Codable, Hashable, Identifiable, Sendable {
    public var a: Int
    public var b: Int
    public var operation: MathOperation

    public init(_ a: Int, _ operation: MathOperation, _ b: Int) {
        self.a = a
        self.b = b
        self.operation = operation
    }

    public var answer: Int { operation == .add ? a + b : a - b }
    /// "3+4", "9-2": the key progress is saved under.
    public var id: String { "\(a)\(operation == .add ? "+" : "-")\(b)" }
    /// "3 + 4 ="
    public var display: String { "\(a) \(operation.symbol) \(b) =" }
    /// "What is 3 plus 4?"
    public var question: String { "What is \(a) \(operation.spoken) \(b)?" }
    /// "3 plus 4 is 7."
    public var answerSentence: String { "\(a) \(operation.spoken) \(b) is \(answer)." }
    public var answerDigits: [String] { String(answer).map(String.init) }
}

/// Fact sets in teaching order. Each set holds only facts the earlier sets don't.
public enum MathSkill: String, CaseIterable, Codable, Sendable {
    case addWithin5, addWithin10, subtractWithin10, addWithin20, subtractWithin20

    public var title: String {
        switch self {
        case .addWithin5: "Adding up to 5"
        case .addWithin10: "Adding up to 10"
        case .subtractWithin10: "Taking away within 10"
        case .addWithin20: "Adding up to 20"
        case .subtractWithin20: "Taking away within 20"
        }
    }

    public var facts: [MathFact] {
        switch self {
        case .addWithin5:
            return pairs(0...5, 0...5).filter { $0 + $1 <= 5 && $0 + $1 > 0 }.map { MathFact($0, .add, $1) }
        case .addWithin10:
            return pairs(0...10, 0...10).filter { (6...10).contains($0 + $1) }.map { MathFact($0, .add, $1) }
        case .subtractWithin10:
            return pairs(1...10, 1...10).filter { $1 <= $0 }.map { MathFact($0, .subtract, $1) }
        case .addWithin20:
            return pairs(1...10, 1...10).filter { $0 + $1 > 10 }.map { MathFact($0, .add, $1) }
        case .subtractWithin20:
            return pairs(11...20, 1...10).filter { $0 - $1 <= 10 }.map { MathFact($0, .subtract, $1) }
        }
    }

    private func pairs(_ first: ClosedRange<Int>, _ second: ClosedRange<Int>) -> [(Int, Int)] {
        first.flatMap { a in second.map { (a, $0) } }
    }
}

/// How the child is doing on one card (a math fact, a reading word): a box that moves up on
/// first-try answers, Leitner style.
public struct BoxProgress: Codable, Hashable, Sendable {
    public var box = 0
    public var attempts = 0
    public var lastPracticed: Date?

    public init() {}

    public var isMastered: Bool { box >= 3 }

    public mutating func record(_ outcome: WordProgress.Outcome, at date: Date = Date()) {
        attempts += 1
        lastPracticed = date
        switch outcome {
        case .firstTry: box = min(box + 1, 5)
        case .retried: break
        case .hinted: box = max(0, box - 1)
        }
    }
}

/// Progress on every fact, saved as `Progress/math.json`.
public struct MathProgress: JSONFile, Hashable {
    public var facts: [String: BoxProgress] = [:]

    public init() {}

    public subscript(fact: MathFact) -> BoxProgress {
        get { facts[fact.id] ?? BoxProgress() }
        set { facts[fact.id] = newValue }
    }

    public func masteredFraction(of skill: MathSkill) -> Double {
        let all = skill.facts
        return Double(all.filter { self[$0].isMastered }.count) / Double(all.count)
    }
}

/// Picks the facts for one math session. A stand-in for FSRS scheduling.
public enum MathPlanner {
    public static let unlockFraction = 0.8

    /// The first skill that isn't mostly mastered yet.
    public static func currentSkill(_ progress: MathProgress) -> MathSkill {
        MathSkill.allCases.first { progress.masteredFraction(of: $0) < unlockFraction } ?? MathSkill.allCases.last!
    }

    /// Mostly facts from the current skill (lowest box first, least recently practiced first), plus a few
    /// mastered facts from earlier skills for review, shuffled together.
    public static func sessionFacts(
        _ progress: MathProgress,
        count: Int = 8,
        reviewCount: Int = 2,
        using rng: inout some RandomNumberGenerator
    ) -> [MathFact] {
        let skill = currentSkill(progress)
        let earlier = MathSkill.allCases.prefix { $0 != skill }
        let review = Array(
            earlier.flatMap(\.facts)
                .filter { progress[$0].isMastered }
                .shuffled(using: &rng)
                .sorted { (progress[$0].lastPracticed ?? .distantPast) < (progress[$1].lastPracticed ?? .distantPast) }
                .prefix(reviewCount)
        )
        // A random tie-break so new facts don't always come in the same order.
        let tieBreak = Dictionary(uniqueKeysWithValues: skill.facts.map { ($0.id, Int.random(in: 0..<1_000_000, using: &rng)) })
        let current = skill.facts.sorted {
            let p0 = progress[$0], p1 = progress[$1]
            return (p0.isMastered ? 1 : 0, p0.box, p0.lastPracticed ?? .distantPast, tieBreak[$0.id]!)
                < (p1.isMastered ? 1 : 0, p1.box, p1.lastPracticed ?? .distantPast, tieBreak[$1.id]!)
        }
        let picked = Array(current.prefix(count - review.count)) + review
        return picked.shuffled(using: &rng)
    }

    public static func sessionFacts(_ progress: MathProgress, count: Int = 8, reviewCount: Int = 2) -> [MathFact] {
        var rng = SystemRandomNumberGenerator()
        return sessionFacts(progress, count: count, reviewCount: reviewCount, using: &rng)
    }
}
