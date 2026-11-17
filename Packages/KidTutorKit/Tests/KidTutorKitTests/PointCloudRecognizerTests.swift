import Testing
@testable import KidTutorKit

struct PointCloudRecognizerTests {
    let letters = SyntheticInk.letters.keys.sorted()

    var recognizer: PointCloudRecognizer {
        PointCloudRecognizer(samples: SyntheticInk.samples(letters, perLetter: 3))
    }

    @Test func recognizesUnseenVariantsOfEachLetter() {
        let recognizer = recognizer
        for letter in letters {
            let ink = SyntheticInk.ink(letter, seed: 9_000 + UInt64(letter.unicodeScalars.first!.value))
            #expect(recognizer.classify(ink).first?.label == letter, "misread \(letter)")
        }
    }

    @Test func keepsMirrorImagesApart() {
        let recognizer = recognizer
        #expect(recognizer.classify(SyntheticInk.ink("b", seed: 777), among: ["b", "d"]).first?.label == "b")
        #expect(recognizer.classify(SyntheticInk.ink("d", seed: 778), among: ["b", "d"]).first?.label == "d")
    }

    @Test func ignoresStrokeOrderAndDirection() {
        let recognizer = recognizer
        for letter in ["x", "t", "b", "i"] {
            let ink = SyntheticInk.ink(letter, seed: 4_242, reversed: true)
            #expect(recognizer.classify(ink).first?.label == letter, "misread reversed \(letter)")
        }
    }

    @Test func dotMakesIDifferentFromL() {
        let recognizer = recognizer
        #expect(recognizer.classify(SyntheticInk.ink("i", seed: 31), among: ["i", "l"]).first?.label == "i")
        #expect(recognizer.classify(SyntheticInk.ink("l", seed: 32), among: ["i", "l"]).first?.label == "l")
    }

    @Test func onlyReturnsAllowedCandidatesBestFirst() {
        let results = recognizer.classify(SyntheticInk.ink("o", seed: 5), among: ["c", "l"], limit: 5)
        #expect(Set(results.map(\.label)) == ["c", "l"])
        #expect(results.first?.label == "c")
        #expect(results[0].score >= results[1].score)
    }

    @Test func handlesEmptyAndSinglePointInk() {
        #expect(recognizer.classify(.empty).isEmpty)
        let tap = Ink(strokes: [InkStroke(points: [InkPoint(x: 10, y: 10)])], canvasWidth: 100, canvasHeight: 100)
        #expect(recognizer.classify(tap).count == 3)
    }

    @Test func noTemplatesMeansNoGuess() {
        #expect(PointCloudRecognizer(samples: []).classify(SyntheticInk.ink("o", seed: 1)).isEmpty)
    }

    @Test func skipsUnlabeledSamples() {
        let unlabeled = InkSample(source: .test, ink: SyntheticInk.ink("o", seed: 1), expected: "o", confirmedLabel: nil)
        #expect(PointCloudRecognizer(samples: [unlabeled]).templateCount == 0)
    }

    @Test func normalizesToFixedPointCount() {
        for letter in letters {
            #expect(PointCloudRecognizer.normalize(SyntheticInk.ink(letter, seed: 3))?.count == PointCloudRecognizer.pointCount)
        }
    }
}
