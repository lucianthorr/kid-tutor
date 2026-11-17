import Foundation

/// One thing to write in a Writing session: a character (written three times) or a word.
public enum WritingItem: Hashable, Sendable {
    case character(String)
    case word(String)

    /// Levels: trace, copy, then from memory (for words: look, cover, write in one wide box).
    public static let topLevel = 3
    /// A character is written this many times, each in its own box.
    public static let repetitions = 3
    /// Writing is copying, not recall, so one clean pass moves an item up a level.
    public static let passesToLevelUp = 1

    public var text: String {
        switch self {
        case .character(let c): c
        case .word(let w): w
        }
    }

    /// What the app says when the item appears.
    public func prompt(level: Int) -> String {
        switch self {
        case .character(let c):
            let name = CharacterLabel.spokenName(for: c)
            return level <= 1 ? "Trace \(name), three times." : "Write \(name), three times."
        case .word(let w):
            switch level {
            case ...1: return "Trace the word \(w)."
            case 2: return "Write the word \(w)."
            default: return "Look at this word: \(w). \(Self.spelledOut(w))"
            }
        }
    }

    /// Said when a look-cover-write word hides.
    public var coverPrompt: String { "Now write \(text) from memory." }

    /// Said when the item is done.
    public var praise: String {
        switch self {
        case .character(let c): "Beautiful! That's \(CharacterLabel.spokenName(for: c))."
        case .word(let w): "Yes! \(Self.spelledOut(w)) \(w.prefix(1).uppercased() + w.dropFirst())!"
        }
    }

    /// "C, A, T."
    static func spelledOut(_ word: String) -> String {
        word.map { $0.uppercased() }.joined(separator: ", ") + "."
    }
}

/// The order characters are introduced: lowercase letters by shape family (letters in a family start
/// with the same stroke), then numbers, then capitals by family.
public enum WritingOrder {
    public static let lowercase = ["c", "a", "d", "g", "o", "q", "l", "t", "i", "j", "k", "r", "n", "m", "h", "b", "p",
                                   "e", "s", "f", "u", "v", "w", "x", "y", "z"]
    public static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    /// Straight lines, slanted lines, curves, then mixed.
    public static let capitals = ["L", "F", "E", "H", "T", "I", "A", "K", "M", "N", "V", "W", "X", "Y", "Z",
                                  "C", "O", "Q", "G", "S", "B", "D", "P", "R", "U", "J"]
    public static let characters = lowercase + digits + capitals
}

/// Progress on every character and word in Writing, saved as `Progress/writing.json`.
/// Separate from Spelling: writing a shown word neatly is a different skill from spelling it.
public struct WritingProgress: JSONFile, Hashable {
    public var characters: [String: WordProgress] = [:]
    public var words: [String: WordProgress] = [:]

    public init() {}

    public subscript(item: WritingItem) -> WordProgress {
        get {
            switch item {
            case .character(let c): characters[c] ?? WordProgress()
            case .word(let w): words[w] ?? WordProgress()
            }
        }
        set {
            switch item {
            case .character(let c): characters[c] = newValue
            case .word(let w): words[w] = newValue
            }
        }
    }

    public mutating func record(_ item: WritingItem, _ outcome: WordProgress.Outcome, missed: [String], at date: Date = Date()) {
        self[item].record(outcome, missed: missed, topLevel: WritingItem.topLevel, passesToLevelUp: WritingItem.passesToLevelUp, at: date)
    }
}

/// Picks the items for one Writing session.
public enum WritingPlanner {
    /// Characters first, in `WritingOrder`, a few being learned at a time. Words join once `wordsUnlockAt`
    /// lowercase letters are written from memory, and only words whose letters have all been copied;
    /// then about half the session is words, shortest first.
    public static func sessionItems(
        words: [String],
        progress: WritingProgress,
        count: Int = 6,
        maxLearning: Int = 6,
        wordsUnlockAt: Int = 8
    ) -> [WritingItem] {
        let fromMemory = WritingOrder.lowercase.filter { letter in
            progress.characters[letter].map { $0.level >= WritingItem.topLevel || $0.isMastered } ?? false
        }
        var pickedWords: [String] = []
        if fromMemory.count >= wordsUnlockAt {
            let eligible = words.enumerated()
                .filter { _, word in
                    word.allSatisfy { progress.characters[String($0)].map { $0.level >= 2 || $0.isMastered } ?? false }
                }
                .sorted { ($0.element.count, $0.offset) < ($1.element.count, $1.offset) }
                .map(\.element)
            pickedWords = LearningPlanner.pick(eligible, progress: progress.words, count: count / 2, maxLearning: maxLearning)
        }
        let characters = LearningPlanner.pick(
            WritingOrder.characters, progress: progress.characters, count: count - pickedWords.count, maxLearning: maxLearning
        )
        return characters.map(WritingItem.character) + pickedWords.map(WritingItem.word)
    }
}
