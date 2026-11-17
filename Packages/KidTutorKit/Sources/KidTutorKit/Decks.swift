import Foundation

/// Where a card sits, the way Anki sorts a deck: never practiced ("new"), practiced but not learned yet
/// ("learning"), or mastered ("mature"). Mastered is each subject's own rule: box 3 for Reading and Math,
/// two first tries in a row at the top level for Spelling and Writing. A hint can take it away again.
public enum DeckPile: String, CaseIterable, Identifiable, Sendable {
    case inProgress, learned, toDo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inProgress: "In progress"
        case .learned: "Learned"
        case .toDo: "To do"
        }
    }
}

/// One card in a subject's deck, described for the grown-up's Progress page.
public struct DeckCard: Hashable, Identifiable, Sendable {
    public var id: String
    public var text: String
    /// "Lowercase", "Adding up to 5": cards are listed under their group when a deck has several.
    public var group: String?
    public var pile: DeckPile
    /// "Level 2 of 7 · 6 tries · often misses: a, u"; empty for a card not practiced yet.
    public var detail: String
    public var lastPracticed: Date?
    /// How far along the card is (box or level); lower is further from learned.
    public var step: Int
    public var attempts: Int
}

/// A subject's cards in teaching order, and how many are in each pile.
public struct Deck: Sendable {
    public var cards: [DeckCard]

    public init(cards: [DeckCard]) {
        self.cards = cards
    }

    public var total: Int { cards.count }

    public func count(_ pile: DeckPile) -> Int {
        cards.filter { $0.pile == pile }.count
    }

    /// In progress comes hardest first (least far along, then most tries), so what needs attention leads.
    /// To do and learned stay in teaching order: to do then shows what comes next.
    public func cards(in pile: DeckPile) -> [DeckCard] {
        let picked = cards.filter { $0.pile == pile }
        guard pile == .inProgress else { return picked }
        return picked.enumerated()
            .sorted { ($0.element.step, -$0.element.attempts, $0.offset) < ($1.element.step, -$1.element.attempts, $1.offset) }
            .map(\.element)
    }

    /// Group names in the order they first appear; empty when the deck isn't grouped.
    public var groups: [String] {
        var seen: [String] = []
        for case let group? in cards.map(\.group) where !seen.contains(group) { seen.append(group) }
        return seen
    }
}

/// Builds each subject's deck from its card list and saved progress.
public enum DeckReport {
    public static func reading(_ cards: [ReadingCard] = StarterReading.cards, progress: ReadingProgress) -> Deck {
        Deck(cards: cards.map { card in
            boxCard(id: card.id, text: card.text, group: card.isSentence ? "Sentences" : "Words", progress.cards[card.id])
        })
    }

    public static func math(_ progress: MathProgress) -> Deck {
        Deck(cards: MathSkill.allCases.flatMap { skill in
            skill.facts.map { fact in
                boxCard(id: fact.id, text: "\(fact.display) \(fact.answer)", group: skill.title, progress.facts[fact.id])
            }
        })
    }

    public static func spelling(_ words: [SpellingWord] = StarterWords.spelling, progress: SpellingProgress) -> Deck {
        Deck(cards: words.map { word in
            let top = SpellingScaffold.topLevel(for: word.word)
            return levelCard(id: word.word, text: word.word, group: nil, progress.words[word.word], topLevel: top) { level in
                level >= top ? "Whole word" : "Level \(level) of \(top)"
            }
        })
    }

    /// Characters in teaching order, grouped, then the words (which join once enough letters are written
    /// from memory).
    public static func writing(
        characters: [String] = WritingOrder.characters,
        words: [String] = StarterWords.spelling.map(\.word),
        progress: WritingProgress
    ) -> Deck {
        func group(_ c: String) -> String {
            WritingOrder.digits.contains(c) ? "Numbers" : c == c.lowercased() ? "Lowercase" : "Capitals"
        }
        let characterCards = characters.map { c in
            levelCard(id: "character:\(c)", text: c, group: group(c), progress.characters[c], topLevel: WritingItem.topLevel, levelName: writingLevel)
        }
        let wordCards = words.map { w in
            levelCard(id: "word:\(w)", text: w, group: "Words", progress.words[w], topLevel: WritingItem.topLevel, levelName: writingLevel)
        }
        return Deck(cards: characterCards + wordCards)
    }

    private static func writingLevel(_ level: Int) -> String {
        switch level {
        case ...1: "Tracing"
        case 2: "Copying"
        default: "From memory"
        }
    }

    // MARK: Cards

    /// A Leitner-box card (Reading, Math): learned at box 3.
    private static func boxCard(id: String, text: String, group: String?, _ progress: BoxProgress?) -> DeckCard {
        guard let progress else {
            return DeckCard(id: id, text: text, group: group, pile: .toDo, detail: "", lastPracticed: nil, step: 0, attempts: 0)
        }
        let learned = progress.isMastered
        let detail = learned
            ? "Learned · \(tries(progress.attempts))"
            : "\(progress.box) of 3 to learned · \(tries(progress.attempts))"
        return DeckCard(
            id: id, text: text, group: group, pile: learned ? .learned : .inProgress, detail: detail,
            lastPracticed: progress.lastPracticed, step: progress.box, attempts: progress.attempts
        )
    }

    /// A card with levels (Spelling, Writing): learned after first tries in a row at the top level.
    private static func levelCard(
        id: String, text: String, group: String?, _ progress: WordProgress?, topLevel: Int,
        levelName: (Int) -> String
    ) -> DeckCard {
        guard let progress else {
            return DeckCard(id: id, text: text, group: group, pile: .toDo, detail: "", lastPracticed: nil, step: 0, attempts: 0)
        }
        let level = min(progress.level, topLevel)
        var parts = [progress.isMastered ? "Learned" : levelName(level)]
        if !progress.isMastered, level >= topLevel {
            parts.append("\(progress.passes) of \(WordProgress.passesToMaster) passes")
        }
        parts.append(tries(progress.attempts))
        let often = progress.missedLetters.filter { $0.value >= 2 }
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .prefix(3).map(\.key)
        if !often.isEmpty { parts.append("often misses: " + often.joined(separator: ", ")) }
        return DeckCard(
            id: id, text: text, group: group, pile: progress.isMastered ? .learned : .inProgress,
            detail: parts.joined(separator: " · "), lastPracticed: progress.lastPracticed, step: level, attempts: progress.attempts
        )
    }

    private static func tries(_ n: Int) -> String { n == 1 ? "1 try" : "\(n) tries" }
}
