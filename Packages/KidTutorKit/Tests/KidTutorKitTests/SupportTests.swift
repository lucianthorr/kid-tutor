import CoreGraphics
import Foundation
import Testing
@testable import KidTutorKit

struct CharacterLabelTests {
    @Test func folderNamesRoundTripAndNeverCollideByCase() {
        let characters = Alphabet.all.characters
        let folders = characters.map(CharacterLabel.folderName(for:))
        #expect(Set(folders.map { $0.lowercased() }).count == characters.count)
        for (character, folder) in zip(characters, folders) {
            #expect(CharacterLabel.character(fromFolderName: folder) == character)
        }
        #expect(CharacterLabel.character(fromFolderName: "nonsense") == nil)
    }

    @Test func spokenPromptsSayLetterNames() {
        #expect(CharacterLabel.spokenPrompt(for: "b") == "Write a lowercase B.")
        #expect(CharacterLabel.spokenPrompt(for: "B") == "Write a capital B.")
        #expect(CharacterLabel.spokenPrompt(for: "7") == "Write the number 7.")
    }

    @Test func ocrTextMapsToExpectedCharacters() {
        let lower = Set(Alphabet(lowercase: true, uppercase: false, digits: false).characters)
        #expect(CharacterLabel.labels(fromOCRText: " A", among: lower) == ["a"])
        #expect(CharacterLabel.labels(fromOCRText: "0", among: lower) == ["o"])
        #expect(CharacterLabel.labels(fromOCRText: "1", among: lower) == ["l"])
        #expect(CharacterLabel.labels(fromOCRText: "", among: lower).isEmpty)
        let digits = Set(Alphabet(lowercase: false, uppercase: false, digits: true).characters)
        #expect(CharacterLabel.labels(fromOCRText: "O", among: digits) == ["0"])
    }

    @Test func alphabetListsSelectedSets() {
        #expect(Alphabet().characters.count == 36)
        #expect(Alphabet.all.characters.count == 62)
        #expect(Alphabet(lowercase: false, uppercase: false, digits: false).characters.isEmpty)
    }
}

struct CalibrationPlanTests {
    func sample(_ label: String) -> InkSample {
        InkSample(source: .calibration, ink: .empty, expected: label, confirmedLabel: label)
    }

    @Test func asksInRoundsSoLettersDontRepeatBackToBack() {
        let plan = CalibrationPlan(characters: ["a", "b", "c"], samplesPerCharacter: 2)
        #expect(plan.remaining(given: []) == ["a", "b", "c", "a", "b", "c"])
        #expect(plan.remaining(given: [sample("a"), sample("a"), sample("b")]) == ["c", "b", "c"])
        #expect(plan.progress(given: [sample("a"), sample("a"), sample("b")]) == (3, 6))
    }

    @Test func extraSamplesDontCountTwice() {
        let plan = CalibrationPlan(characters: ["a"], samplesPerCharacter: 1)
        #expect(plan.remaining(given: [sample("a"), sample("a"), sample("a")]).isEmpty)
        #expect(plan.progress(given: [sample("a"), sample("a")]) == (1, 1))
    }
}

struct AccuracyReportTests {
    func test(_ written: String, _ guesses: [String: String], at seconds: Double) -> InkSample {
        InkSample(
            createdAt: Date(timeIntervalSince1970: seconds),
            source: .test,
            ink: .empty,
            expected: written,
            confirmedLabel: written,
            recognized: guesses
        )
    }

    @Test func scoresEachRecognizerWithConfusions() {
        let samples = [
            test("b", ["pdollar": "b", "vision": "d"], at: 1),
            test("b", ["pdollar": "d", "vision": "d"], at: 2),
            test("a", ["pdollar": "a", "vision": ""], at: 3),
            InkSample(source: .calibration, ink: .empty, expected: "a", confirmedLabel: "a"),
        ]
        let report = Dictionary(uniqueKeysWithValues: AccuracyReport.compute(samples: samples).map { ($0.recognizerID, $0) })

        let pdollar = try! #require(report["pdollar"])
        #expect((pdollar.attempts, pdollar.correct) == (3, 2))
        #expect(pdollar.confusions == [.init(written: "b", read: "d", count: 1)])
        #expect(pdollar.characters.first?.character == "b")

        let vision = try! #require(report["vision"])
        #expect((vision.attempts, vision.correct) == (3, 0))
        #expect(vision.confusions.first == .init(written: "b", read: "d", count: 2))
    }

    @Test func canLimitToRecentSamples() {
        let samples = [
            test("a", ["pdollar": "x"], at: 1),
            test("a", ["pdollar": "a"], at: 2),
        ]
        #expect(AccuracyReport.compute(samples: samples, lastN: 1).first?.rate == 1)
    }
}

struct StorageAndRenderingTests {
    @Test func storeRoundTripsSamples() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = SampleStore(directory: directory)
        #expect(try store.load().isEmpty)
        let samples = SyntheticInk.samples(["o", "x"], perLetter: 2)
        try store.save(samples)
        #expect(try store.load() == samples)
    }

    @Test func rendersCenteredBlackOnWhite() throws {
        let image = try #require(InkRenderer.render(SyntheticInk.ink("t", seed: 1)))
        #expect(image.width == InkRenderer.trainingImageSize && image.height == InkRenderer.trainingImageSize)

        let size = image.width
        var pixels = [UInt8](repeating: 0, count: size * size)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        #expect(drew)
        #expect(pixels[0] == 255, "corner should be paper")
        #expect(pixels.contains { $0 < 64 }, "some ink should be drawn")

        #expect(InkRenderer.pngData(image)?.isEmpty == false)
        #expect(InkRenderer.render(.empty) == nil)
    }
}

struct SubjectTests {
    @Test func homePromptNamesEverySubjectInOrder() {
        #expect(Subject.homePrompt == "What do you want to practice? Reading, writing, spelling, math, puzzles, or a bit of everything.")
    }

    @Test func rawValuesMatchLessonFileSubjects() {
        #expect(Subject(rawValue: "spelling") == .spelling)
        #expect(Subject.allCases.map(\.rawValue) == ["reading", "writing", "spelling", "math", "logic", "mixed"])
    }
}

struct VoiceCatalogTests {
    @Test func keepsOnlyNaturalVoices() {
        let human = [
            "com.apple.voice.compact.en-US.Samantha",
            "com.apple.voice.super-compact.en-GB.Daniel",
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Evan",
            "com.apple.ttsbundle.Samantha-compact",
        ]
        let robotic = [
            "com.apple.eloquence.en-US.Grandma",
            "com.apple.eloquence.en-GB.Eddy",
            "com.apple.speech.synthesis.voice.Fred",
            "com.apple.speech.synthesis.voice.Junior",
            "com.apple.speech.synthesis.voice.Zarvox",
        ]
        for id in human { #expect(VoiceCatalog.isHumanVoice(identifier: id, isNovelty: false, isPersonal: false), "\(id)") }
        for id in robotic { #expect(!VoiceCatalog.isHumanVoice(identifier: id, isNovelty: false, isPersonal: false), "\(id)") }
        #expect(!VoiceCatalog.isHumanVoice(identifier: "com.apple.voice.compact.en-US.X", isNovelty: true, isPersonal: false))
        #expect(VoiceCatalog.isHumanVoice(identifier: "personal-voice-1234", isNovelty: false, isPersonal: true))
    }
}
