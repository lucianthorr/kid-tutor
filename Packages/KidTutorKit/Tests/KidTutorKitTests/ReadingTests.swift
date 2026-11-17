import Foundation
import Testing
@testable import KidTutorKit

struct ReadingCheckTests {
    func v(_ card: String, _ heard: String...) -> ReadingCheck.Verdict {
        ReadingCheck.verdict(for: ReadingCard(card), heard: heard)
    }

    @Test func singleWords() {
        #expect(v("look", "Look") == .correct)
        #expect(v("look", "look.") == .correct)
        #expect(v("look", "I look") == .correct)          // extra words are fine
        #expect(v("look", "book") == .correct)            // one letter off, 4+ letters: lenient
        #expect(v("see", "sea") == .correct)              // sound-alike
        #expect(v("to", "Two") == .correct)
        #expect(v("I", "eye") == .correct)
        #expect(v("big", "bag") == .close)                // short word, one off: try again
        #expect(v("yellow", "hello") == .close)           // a different word: try again
        #expect(v("jump", "dog") == .incorrect)
        #expect(v("jump", "") == .incorrect)
    }

    @Test func anyAlternativeCounts() {
        #expect(v("where", "wear", "we're") == .correct)
        #expect(v("run", "fun", "ran") == .close)
    }

    @Test func cardSpecificSoundsLike() {
        let card = ReadingCard("funny", soundsLike: ["phony"])
        #expect(ReadingCheck.verdict(for: card, heard: ["phony"]) == .correct)
    }

    @Test func sentences() {
        #expect(v("I can run.", "I can run") == .correct)
        #expect(v("Here is my red ball.", "here is my read ball") == .correct)
        #expect(v("Here is my red ball.", "here is ball") == .close)
        #expect(v("We see a dog.", "cat") == .incorrect)
    }

    @Test func instructionsMatchTheCardKind() {
        #expect(ReadingCard("look").instruction.hasPrefix("Read this word."))
        #expect(ReadingCard("I can run.").instruction.hasPrefix("Read this sentence."))
    }

    @Test func editDistance() {
        #expect(ReadingCheck.distance("look", "book") == 1)
        #expect(ReadingCheck.distance("yellow", "hello") == 2)
        #expect(ReadingCheck.distance("", "abc") == 3)
    }
}

struct ReadingPlannerTests {
    let cards = ["a", "b", "c", "d", "e"].map { ReadingCard($0) }

    @Test func newCardsInOrderThenLearningFirst() {
        #expect(ReadingPlanner.sessionCards(from: cards, progress: .init(), count: 3).map(\.text) == ["a", "b", "c"])
        var progress = ReadingProgress()
        progress[cards[2]].record(.firstTry, at: Date(timeIntervalSinceReferenceDate: 1))
        progress[cards[1]].record(.retried, at: Date(timeIntervalSinceReferenceDate: 2))
        #expect(ReadingPlanner.sessionCards(from: cards, progress: progress, count: 3).map(\.text) == ["b", "c", "a"])
    }

    @Test func starterCardsAreUnique() {
        let ids = StarterReading.cards.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

struct SpeechErrorMeaningTests {
    @Test func noSpeechIsNeverABrokenRecognizer() {
        // The real iPad log: "No speech detected" 1.9 s after starting turned the mic off for the session.
        #expect(SpeechErrorMeaning.of(domain: "kAFAssistantErrorDomain", code: 1110, heardAnything: false, secondsSinceStart: 1.9) == .heardNothing)
        #expect(SpeechErrorMeaning.of(domain: "kAFAssistantErrorDomain", code: 1110, heardAnything: false, secondsSinceStart: 6) == .heardNothing)
        #expect(SpeechErrorMeaning.of(domain: "kAFAssistantErrorDomain", code: 1110, heardAnything: true, secondsSinceStart: 3) == .turnEnded)
    }

    @Test func anEarlyFailureBeforeHearingAnythingCannotStart() {
        // The Simulator: "Failed to initialize recognizer" 0.2 s after starting.
        #expect(SpeechErrorMeaning.of(domain: "kLSRErrorDomain", code: 300, heardAnything: false, secondsSinceStart: 0.2) == .cannotStart)
        // Later, with nothing heard, the child just hasn't read yet: keep waiting.
        #expect(SpeechErrorMeaning.of(domain: "kLSRErrorDomain", code: 300, heardAnything: false, secondsSinceStart: 5) == .heardNothing)
        #expect(SpeechErrorMeaning.of(domain: "kLSRErrorDomain", code: 300, heardAnything: true, secondsSinceStart: 0.5) == .turnEnded)
        // A quick "no speech" with nothing heard is still just waiting.
        #expect(SpeechErrorMeaning.of(domain: "kAFAssistantErrorDomain", code: 1110, heardAnything: false, secondsSinceStart: 0.3) == .heardNothing)
    }
}

struct ListeningRetriesTests {
    @Test func noSpeechKeepsWaitingAsLongAsItTakes() {
        var retries = ListeningRetries()
        for _ in 0..<50 {
            #expect(retries.endedWithNothing(after: 5, failed: false) == .listenAgain(after: 0))
        }
    }

    @Test func aRecognizerThatKeepsFailingGivesUp() {
        // The review's case: every attempt fails 2.5 s in, too late to look like "can't start".
        var retries = ListeningRetries()
        #expect(retries.endedWithNothing(after: 2.5, failed: true) == .listenAgain(after: 0))
        #expect(retries.endedWithNothing(after: 2.5, failed: true) == .listenAgain(after: 0))
        #expect(retries.endedWithNothing(after: 2.5, failed: true) == .giveUp)
    }

    @Test func oneFailureBetweenQuietAttemptsIsForgiven() {
        var retries = ListeningRetries()
        _ = retries.endedWithNothing(after: 2.5, failed: true)
        _ = retries.endedWithNothing(after: 2.5, failed: true)
        _ = retries.endedWithNothing(after: 8, failed: false)
        #expect(retries.endedWithNothing(after: 2.5, failed: true) == .listenAgain(after: 0))
    }

    @Test func attemptsThatEndAtOnceSlowDownThenGiveUp() {
        var retries = ListeningRetries()
        for _ in 1..<ListeningRetries.maxQuickEnds {
            #expect(retries.endedWithNothing(after: 0.2, failed: false) == .listenAgain(after: 1))
        }
        #expect(retries.endedWithNothing(after: 0.2, failed: false) == .giveUp)
    }
}
