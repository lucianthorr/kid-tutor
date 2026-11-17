import Foundation
import Testing
@testable import KidTutorKit

struct MathFactTests {
    @Test func describesItself() {
        let fact = MathFact(3, .add, 4)
        #expect(fact.answer == 7 && fact.id == "3+4" && fact.display == "3 + 4 =")
        #expect(fact.question == "What is 3 plus 4?" && fact.answerSentence == "3 plus 4 is 7.")
        let take = MathFact(14, .subtract, 6)
        #expect(take.answer == 8 && take.id == "14-6" && take.display == "14 − 6 =")
        #expect(MathFact(9, .add, 6).answerDigits == ["1", "5"])
    }

    @Test func skillsHaveSensibleAndDistinctFacts() {
        var seen = Set<String>()
        for skill in MathSkill.allCases {
            let facts = skill.facts
            #expect(!facts.isEmpty, "\(skill)")
            #expect(facts.allSatisfy { $0.answer >= 0 && $0.answer <= 20 }, "\(skill)")
            for fact in facts { #expect(seen.insert(fact.id).inserted, "\(fact.id) repeats in \(skill)") }
        }
        #expect(MathSkill.addWithin5.facts.allSatisfy { $0.answer <= 5 })
        #expect(MathSkill.addWithin20.facts.allSatisfy { $0.answer > 10 })
    }
}

struct MathProgressTests {
    @Test func boxesMoveWithOutcomes() {
        var p = BoxProgress()
        p.record(.firstTry); p.record(.firstTry); p.record(.retried)
        #expect(p.box == 2 && !p.isMastered)
        p.record(.firstTry)
        #expect(p.isMastered)
        p.record(.hinted)
        #expect(p.box == 2)
    }

    @Test func unlocksTheNextSkillAt80Percent() {
        var progress = MathProgress()
        #expect(MathPlanner.currentSkill(progress) == .addWithin5)
        let facts = MathSkill.addWithin5.facts
        for fact in facts.prefix(Int((Double(facts.count) * 0.8).rounded(.up))) {
            progress[fact].box = 3
        }
        #expect(MathPlanner.currentSkill(progress) == .addWithin10)
    }

    @Test func sessionMixesCurrentFactsWithReview() {
        var progress = MathProgress()
        for fact in MathSkill.addWithin5.facts { progress[fact].box = 3 }
        var rng = SeededGenerator(seed: 7)
        let facts = MathPlanner.sessionFacts(progress, count: 8, reviewCount: 2, using: &rng)
        #expect(facts.count == 8)
        #expect(facts.filter { MathSkill.addWithin5.facts.contains($0) }.count == 2)
        #expect(facts.filter { MathSkill.addWithin10.facts.contains($0) }.count == 6)
        #expect(Set(facts).count == 8)
    }

    @Test func firstSessionHasNoReview() {
        var rng = SeededGenerator(seed: 1)
        let facts = MathPlanner.sessionFacts(MathProgress(), count: 8, using: &rng)
        #expect(facts.count == 8 && facts.allSatisfy { MathSkill.addWithin5.facts.contains($0) })
    }

    @Test func roundTripsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        var progress = MathProgress()
        progress[MathFact(2, .add, 2)].record(.firstTry, at: Date(timeIntervalSinceReferenceDate: 5))
        try progress.save(to: url)
        #expect(try MathProgress.load(from: url) == progress)
    }
}

struct AnswerBoxTests {
    @Test func missTwiceThenTrace() {
        var box = AnswerBox()
        box.ink = SyntheticInk.ink("o", seed: 1)
        #expect(box.judge(.incorrect) == .tryAgain)
        #expect(box.ink.isEmpty && box.clearToken == 1 && !box.showTrace)
        #expect(box.judge(.incorrect) == .trace)
        #expect(box.showTrace && box.misses == 2)
        #expect(box.judge(.correct) == .accepted)
        #expect(box.accepted && !box.lastWasWrong)
    }

    @Test func outcomeFromBoxes() {
        var clean = AnswerBox(); _ = clean.judge(.correct)
        var missed = AnswerBox(); _ = missed.judge(.incorrect); _ = missed.judge(.correct)
        var traced = AnswerBox(); _ = traced.judge(.incorrect); _ = traced.judge(.incorrect)
        #expect(AnswerBox.outcome(of: [clean], usedHelp: false) == .firstTry)
        #expect(AnswerBox.outcome(of: [clean, missed], usedHelp: false) == .retried)
        #expect(AnswerBox.outcome(of: [clean, traced], usedHelp: false) == .hinted)
        #expect(AnswerBox.outcome(of: [clean], usedHelp: true) == .hinted)
    }
}

struct CalibrationNeedsTests {
    @Test func listsCharactersShortOfSamples() {
        let plan = CalibrationPlan(characters: ["a", "b", "1"], samplesPerCharacter: 2)
        let samples = ["a", "a", "b"].map { InkSample(source: .calibration, ink: .empty, expected: $0, confirmedLabel: $0) }
        #expect(plan.charactersNeedingSamples(given: samples) == ["b", "1"])
    }
}
