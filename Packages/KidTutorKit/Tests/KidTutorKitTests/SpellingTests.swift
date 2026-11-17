import Foundation
import Testing
@testable import KidTutorKit

struct SpellingScaffoldTests {
    @Test func levelNBlanksNRandomLetters() {
        var rng = SeededGenerator(seed: 7)
        for level in 1...6 {
            let blanks = SpellingScaffold.blanks(in: "friend", level: level, using: &rng)
            #expect(blanks.count == level)
            #expect(Set(blanks).count == level && blanks == blanks.sorted())
            #expect(blanks.allSatisfy { (0..<6).contains($0) })
        }
        #expect(SpellingScaffold.blanks(in: "cat", level: 9, using: &rng) == [0, 1, 2])
        #expect(SpellingScaffold.blanks(in: "cat", level: 0, using: &rng).count == 1)
    }

    @Test func blanksMoveAround() {
        var rng = SeededGenerator(seed: 1)
        let seen = Set((0..<40).map { _ in SpellingScaffold.blanks(in: "friend", level: 1, using: &rng) })
        #expect(seen.count > 3)
    }

    @Test func topLevelIsTheWholeWord() {
        #expect(SpellingScaffold.topLevel(for: "friend") == 6)
        #expect(!SpellingScaffold.isWholeWord("cat", level: 2))
        #expect(SpellingScaffold.isWholeWord("cat", level: 3))
        #expect(SpellingScaffold.isWholeWord("cat", level: 4))
    }

    @Test func promptsReadNaturally() {
        let word = SpellingWord("friend", "My friend came over to play.")
        #expect(word.prompt == "Spell friend. My friend came over to play. Friend.")
        #expect(word.spelledOut == "F, R, I, E, N, D.")
    }

    @Test func starterWordsAreLowercaseAndUnique() {
        let words = StarterWords.spelling.map(\.word)
        #expect(Set(words).count == words.count)
        #expect(words.allSatisfy { $0 == $0.lowercased() && $0.allSatisfy(\.isLetter) })
    }
}

struct WordProgressTests {
    func record(_ p: inout WordProgress, _ outcome: WordProgress.Outcome, missed: [String] = []) {
        p.record(outcome, missed: missed, topLevel: 3, passesToLevelUp: 2)
    }

    @Test func twoFirstTriesInARowLevelUp() {
        var p = WordProgress()
        record(&p, .firstTry)
        #expect(p.level == 1 && p.passes == 1)
        record(&p, .retried, missed: ["e"])
        #expect(p.level == 1 && p.passes == 0 && p.missedLetters == ["e": 1])
        record(&p, .firstTry)
        record(&p, .firstTry)
        #expect(p.level == 2 && p.passes == 0)
    }

    @Test func aHintLevelsDown() {
        var p = WordProgress()
        p.level = 2
        record(&p, .hinted, missed: ["e"])
        #expect(p.level == 1 && p.missedLetters == ["e": 1])
        record(&p, .hinted)
        #expect(p.level == 1)
    }

    @Test func masteredAfterTwoFirstTriesAtTheTop() {
        var p = WordProgress()
        for _ in 0..<4 { record(&p, .firstTry) }
        #expect(p.level == 3 && !p.isMastered)
        record(&p, .firstTry)
        record(&p, .firstTry)
        #expect(p.isMastered && p.level == 3)
        record(&p, .retried)
        #expect(p.isMastered)
        record(&p, .hinted)
        #expect(!p.isMastered && p.level == 2)
    }

    @Test func oldLevelsAboveTheTopAreCappedOnUse() {
        var p = WordProgress()
        p.level = 4
        record(&p, .firstTry)
        record(&p, .firstTry)
        #expect(p.level == 3 && p.isMastered)
    }

    @Test func readsProgressSavedBeforeLevelsCountedBlanks() throws {
        let json = #"{"words":{"cat":{"attempts":4,"level":4,"missedLetters":{"a":1},"topLevelPasses":2},"dog":{"attempts":1,"level":2,"missedLetters":{},"topLevelPasses":0}}}"#
        let progress = try JSONDecoder().decode(SpellingProgress.self, from: Data(json.utf8))
        #expect(progress["cat"].isMastered && progress["cat"].level == 4 && progress["cat"].missedLetters == ["a": 1])
        #expect(!progress["dog"].isMastered && progress["dog"].level == 2 && progress["dog"].passes == 0)
    }

    @Test func progressRoundTripsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Progress/spelling.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(try SpellingProgress.load(from: url) == SpellingProgress())
        var progress = SpellingProgress()
        progress["cat"].record(.firstTry, missed: [], topLevel: 3, passesToLevelUp: 2, at: Date(timeIntervalSinceReferenceDate: 100))
        try progress.save(to: url)
        #expect(try SpellingProgress.load(from: url) == progress)
    }
}

struct SpellingPlannerTests {
    let words = ["a", "b", "c", "d", "e", "f", "g", "h"].map { SpellingWord($0, "") }

    @Test func firstSessionTakesNewWordsInOrder() {
        #expect(SpellingPlanner.sessionWords(from: words, progress: .init(), count: 3).map(\.word) == ["a", "b", "c"])
    }

    @Test func learningWordsComeFirstOldestFirstThenNew() {
        var progress = SpellingProgress()
        progress["c"].record(.retried, missed: [], topLevel: 1, passesToLevelUp: 2, at: Date(timeIntervalSinceReferenceDate: 200))
        progress["b"].record(.retried, missed: [], topLevel: 1, passesToLevelUp: 2, at: Date(timeIntervalSinceReferenceDate: 100))
        let picked = SpellingPlanner.sessionWords(from: words, progress: progress, count: 4).map(\.word)
        #expect(picked == ["b", "c", "a", "d"])
    }

    @Test func capsWordsBeingLearnedAndReviewsMasteredWords() {
        var progress = SpellingProgress()
        for w in ["a", "b"] { progress[w].record(.retried, missed: [], topLevel: 1, passesToLevelUp: 2) }
        var mastered = WordProgress()
        for _ in 0..<2 { mastered.record(.firstTry, missed: [], topLevel: 1, passesToLevelUp: 2, at: Date(timeIntervalSinceReferenceDate: 0)) }
        progress.words["h"] = mastered
        let picked = SpellingPlanner.sessionWords(from: words, progress: progress, count: 5, maxLearning: 3).map(\.word)
        #expect(picked == ["a", "b", "c", "h"])
    }
}

struct LetterCheckTests {
    func c(_ pairs: (String, Double)...) -> [RecognitionCandidate] {
        pairs.map { RecognitionCandidate(label: $0.0, score: $0.1) }
    }

    @Test func judgesAgainstTheTopGuesses() {
        #expect(LetterCheck.verdict(expected: "e", candidates: c(("e", 0.5), ("c", 0.4)), examplesOfExpected: 3) == .correct)
        #expect(LetterCheck.verdict(expected: "e", candidates: c(("c", 0.5), ("e", 0.45)), examplesOfExpected: 3) == .correct)
        #expect(LetterCheck.verdict(expected: "e", candidates: c(("c", 0.5), ("e", 0.30)), examplesOfExpected: 3) == .incorrect)
        // The "u" read third after v and c (0.36 vs 0.43) in a real session should pass.
        #expect(LetterCheck.verdict(expected: "u", candidates: c(("v", 0.43), ("c", 0.40), ("u", 0.36)), examplesOfExpected: 2) == .correct)
        #expect(LetterCheck.verdict(expected: "e", candidates: [], examplesOfExpected: 3) == .incorrect)
    }

    @Test func acceptsLettersItCannotJudgeYet() {
        #expect(LetterCheck.verdict(expected: "x", candidates: c(("k", 0.9)), examplesOfExpected: 1) == .unverified)
    }
}
