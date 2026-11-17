import Foundation
import Testing
@testable import KidTutorKit

extension SyntheticInk {
    /// Letters side by side in one wide box, `spacing` apart.
    static func word(_ letters: [String], seed: UInt64, spacing: Double = 120) -> Ink {
        let strokes = letters.enumerated().flatMap { i, letter in
            ink(letter, seed: seed + UInt64(i)).strokes.map { stroke in
                InkStroke(points: stroke.points.map { InkPoint(x: $0.x + Double(i) * spacing, y: $0.y) })
            }
        }
        return Ink(strokes: strokes, canvasWidth: spacing * Double(letters.count), canvasHeight: 100)
    }
}

struct WordInkTests {
    @Test func splitsLettersAndKeepsDotsAndBarsWithTheirLetter() {
        for seed in UInt64(1)...20 {
            let ink = SyntheticInk.word(["l", "i", "t"], seed: seed * 10)
            let letters = WordInk.letters(in: ink)
            #expect(letters.map(\.strokes.count) == [1, 2, 2], "seed \(seed)")
        }
    }

    @Test func eachPieceIsRecognizedAsItsLetter() {
        let recognizer = PointCloudRecognizer(samples: SyntheticInk.samples(["l", "i", "o", "c", "b", "d", "x", "t"], perLetter: 3))
        let ink = SyntheticInk.word(["d", "o", "t"], seed: 500)
        let guesses = WordInk.letters(in: ink).map { recognizer.classify($0).first?.label }
        #expect(guesses == ["d", "o", "t"])
    }

    @Test func overlappingLettersStayTogether() {
        let ink = SyntheticInk.word(["o", "o"], seed: 3, spacing: 20)
        #expect(WordInk.letters(in: ink).count == 1)
        #expect(WordInk.letters(in: .empty).isEmpty)
    }

    @Test func aLateDotStillJoinsItsLetter() {
        // The child writes "it", then goes back to dot the i.
        var ink = SyntheticInk.word(["i", "t"], seed: 9)
        let dot = ink.strokes.remove(at: 1)
        ink.strokes.append(dot)
        let letters = WordInk.letters(in: ink)
        #expect(letters.count == 2 && letters[0].strokes.count == 2)
    }
}

struct WordCheckTests {
    @Test func everyLetterRightIsCorrect() {
        let result = WordCheck.verdict(expected: "cat", letters: [.correct, .unverified, .correct], read: [])
        #expect(result.verdict == .correct && result.how == "letters")
        #expect(WordCheck.verdict(expected: "cat", letters: [.unverified, .unverified, .unverified], read: []).verdict == .unverified)
    }

    @Test func wrongLettersAreNamedUnlessTheWordReadsRight() {
        let wrong = WordCheck.verdict(expected: "cat", letters: [.correct, .incorrect, .correct], read: ["cot"])
        #expect(wrong.verdict == .incorrect && wrong.missedLetters == ["a"])
        let rescued = WordCheck.verdict(expected: "cat", letters: [.correct, .incorrect, .correct], read: ["cot", "Cat."])
        #expect(rescued.verdict == .correct && rescued.how == "text")
    }

    @Test func unsplittableInkFallsBackToReading() {
        #expect(WordCheck.verdict(expected: "cat", letters: nil, read: ["c at"]).verdict == .correct)
        let result = WordCheck.verdict(expected: "cat", letters: nil, read: [])
        #expect(result.verdict == .incorrect && result.missedLetters.isEmpty)
        #expect(WordCheck.verdict(expected: "cat", letters: [.correct, .correct], read: []).verdict == .incorrect)
    }

    @Test func tinyMarksAreNotCharacters() {
        #expect(SyntheticInk.ink("o", seed: 1).isBigEnough())
        let dot = Ink(strokes: [InkStroke(points: [InkPoint(x: 50, y: 50), InkPoint(x: 52, y: 51)])], canvasWidth: 100, canvasHeight: 100)
        #expect(!dot.isBigEnough())
        #expect(!Ink.empty.isBigEnough())
    }
}

struct WritingTests {
    @Test func charactersComeInFamiliesThenNumbersThenCapitals() {
        let order = WritingOrder.characters
        #expect(order.count == 62 && Set(order).count == 62)
        #expect(Set(WritingOrder.lowercase) == Set(Alphabet(lowercase: true, uppercase: false, digits: false).characters))
        #expect(Set(WritingOrder.capitals) == Set(Alphabet(lowercase: false, uppercase: true, digits: false).characters))
        #expect(Array(order.prefix(6)) == ["c", "a", "d", "g", "o", "q"])
    }

    @Test func promptsReadNaturally() {
        #expect(WritingItem.character("a").prompt(level: 1) == "Trace a lowercase A, three times.")
        #expect(WritingItem.character("B").prompt(level: 2) == "Write a capital B, three times.")
        #expect(WritingItem.character("3").prompt(level: 3) == "Write the number 3, three times.")
        #expect(WritingItem.word("cat").prompt(level: 2) == "Write the word cat.")
        #expect(WritingItem.word("cat").prompt(level: 3) == "Look at this word: cat. C, A, T.")
        #expect(WritingItem.word("cat").praise == "Yes! C, A, T. Cat!")
    }

    @Test func oneCleanPassLevelsUpAndTwoAtTheTopMaster() {
        var progress = WritingProgress()
        let a = WritingItem.character("a")
        progress.record(a, .firstTry, missed: [])
        #expect(progress[a].level == 2)
        progress.record(a, .firstTry, missed: [])
        progress.record(a, .firstTry, missed: [])
        #expect(progress[a].level == 3 && !progress[a].isMastered)
        progress.record(a, .firstTry, missed: [])
        #expect(progress[a].isMastered)
        #expect(progress[.word("a")] == WordProgress())
    }

    @Test func firstSessionIsTheFirstFamily() {
        let items = WritingPlanner.sessionItems(words: ["cat"], progress: WritingProgress())
        #expect(items == ["c", "a", "d", "g", "o", "q"].map(WritingItem.character))
    }

    @Test func wordsJoinOnceLettersAreWrittenFromMemory() {
        var progress = WritingProgress()
        let words = ["cat", "dog", "go", "zoo"]
        // Seven letters from memory: no words yet.
        for letter in ["c", "a", "d", "g", "o", "q", "l"] {
            progress.characters[letter] = level(3)
        }
        #expect(WritingPlanner.sessionItems(words: words, progress: progress).allSatisfy { if case .character = $0 { true } else { false } })

        progress.characters["t"] = level(3)
        let items = WritingPlanner.sessionItems(words: words, progress: progress)
        // "zoo" has a letter not practiced yet; shorter words come first.
        #expect(items.suffix(3) == [.word("go"), .word("cat"), .word("dog")])
        #expect(items.count == 6)
    }

    private func level(_ n: Int) -> WordProgress {
        var p = WordProgress()
        p.level = n
        return p
    }
}

struct TraceBoxTests {
    @Test func aTracingExerciseIsNotAHint() {
        var box = AnswerBox(trace: true)
        #expect(box.showTrace)
        _ = box.judge(.correct)
        #expect(AnswerBox.outcome(of: [box], usedHelp: false) == .firstTry)

        var missed = AnswerBox(trace: true)
        _ = missed.judge(.incorrect)
        _ = missed.judge(.incorrect)
        _ = missed.judge(.correct)
        #expect(AnswerBox.outcome(of: [missed], usedHelp: false) == .retried)
    }
}
