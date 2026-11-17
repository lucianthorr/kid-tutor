import Foundation
import Testing
@testable import KidTutorKit

struct DeckTests {
    @Test func everyCardStartsToDo() {
        let decks = [
            DeckReport.reading(progress: ReadingProgress()),
            DeckReport.spelling(progress: SpellingProgress()),
            DeckReport.writing(progress: WritingProgress()),
            DeckReport.math(MathProgress()),
        ]
        for deck in decks {
            #expect(deck.total > 0 && deck.count(.toDo) == deck.total)
            #expect(Set(deck.cards.map(\.id)).count == deck.total)
        }
        #expect(DeckReport.reading(progress: ReadingProgress()).total == StarterReading.cards.count)
        #expect(DeckReport.math(MathProgress()).groups == MathSkill.allCases.map(\.title))
        #expect(DeckReport.writing(progress: WritingProgress()).groups == ["Lowercase", "Numbers", "Capitals", "Words"])
    }

    @Test func readingCardsAreLearnedAtBoxThree() {
        var progress = ReadingProgress()
        let cards = StarterReading.cards
        progress[cards[0]].record(.firstTry)
        for _ in 0..<3 { progress[cards[1]].record(.firstTry) }
        let deck = DeckReport.reading(progress: progress)
        #expect(deck.count(.inProgress) == 1 && deck.count(.learned) == 1)
        #expect(deck.count(.toDo) == cards.count - 2)
        #expect(deck.cards(in: .inProgress).first?.detail == "1 of 3 to learned · 1 try")
        #expect(deck.cards(in: .learned).first?.detail == "Learned · 3 tries")
        // A hint after learning drops it back to in progress.
        progress[cards[1]].record(.hinted)
        #expect(DeckReport.reading(progress: progress).count(.learned) == 0)
    }

    @Test func spellingShowsLevelPassesAndOftenMissedLetters() {
        let words = [SpellingWord("cat", "."), SpellingWord("because", "."), SpellingWord("dog", ".")]
        var progress = SpellingProgress()
        var because = WordProgress()
        because.record(.hinted, missed: ["a", "u"], topLevel: 7, passesToLevelUp: 2)
        because.record(.retried, missed: ["a"], topLevel: 7, passesToLevelUp: 2)
        progress.words["because"] = because
        var cat = WordProgress()
        cat.level = 3
        cat.record(.firstTry, missed: [], topLevel: 3, passesToLevelUp: 2)
        progress.words["cat"] = cat
        let deck = DeckReport.spelling(words, progress: progress)
        #expect(deck.cards(in: .inProgress).map(\.text) == ["because", "cat"])
        #expect(deck.cards(in: .inProgress)[0].detail == "Level 1 of 7 · 2 tries · often misses: a")
        #expect(deck.cards(in: .inProgress)[1].detail == "Whole word · 1 of 2 passes · 1 try")
        #expect(deck.cards(in: .toDo).map(\.text) == ["dog"])
    }

    @Test func inProgressIsHardestFirst() {
        func card(_ id: String, step: Int, attempts: Int) -> DeckCard {
            DeckCard(id: id, text: id, pile: .inProgress, detail: "", step: step, attempts: attempts)
        }
        let deck = Deck(cards: [card("a", step: 2, attempts: 1), card("b", step: 1, attempts: 2), card("c", step: 1, attempts: 5)])
        #expect(deck.cards(in: .inProgress).map(\.id) == ["c", "b", "a"])
    }
}
