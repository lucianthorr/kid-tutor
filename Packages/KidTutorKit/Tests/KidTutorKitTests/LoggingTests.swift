import Foundation
import Testing
@testable import KidTutorKit

struct LogFileTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func appendsOneLinePerEventIntoTodaysFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = LogFile(directory: directory)
        let now = Date()
        log.append(.info, "app", "launched", at: now)
        log.append(.error, "recognition", "line one\nline two", at: now)
        log.flush()

        let text = try String(contentsOf: log.fileURL(for: now), encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix("[info] app: launched"))
        #expect(lines[1].hasSuffix("[error] recognition: line one\\nline two"))
    }

    @Test func deletesFilesOlderThanKeepDays() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = directory.appendingPathComponent("kidtutor-2000-01-01.log")
        let unrelated = directory.appendingPathComponent("notes.txt")
        try Data().write(to: old)
        try Data().write(to: unrelated)

        let log = LogFile(directory: directory, keepDays: 14)
        log.append(.info, "app", "hello")
        log.flush()
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }

    @Test func formatsLocalTimestamp() {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 11, 5)
        (components.hour, components.minute, components.second, components.nanosecond) = (9, 7, 3, 45_500_000)
        let date = Calendar.current.date(from: components)!
        #expect(LogFile.format(.warning, "ink", "x", at: date) == "2026-11-05 09:07:03.045 [warning] ink: x\n")
    }
}

struct InkSummaryTests {
    @Test func summarizesAndFlagsNonFiniteValues() {
        var ink = SyntheticInk.ink("t", seed: 1)
        #expect(ink.logSummary.hasPrefix("strokes=2 points=26 canvas=100x100 bounds="))
        #expect(!ink.hasNonFiniteValues)
        ink.strokes[0].points[0].force = .nan
        #expect(ink.hasNonFiniteValues)
        #expect(ink.logSummary.hasSuffix("NONFINITE=1"))
    }
}

struct EvaluationTests {
    @Test func leaveOneOutNeverMatchesASampleAgainstItself() {
        let letters = ["o", "x", "t", "l"]
        let samples = SyntheticInk.samples(letters, perLetter: 3)
        let results = Evaluation.leaveOneOut(samples: samples, among: Set(letters))
        #expect(results.count == samples.count)
        let allCorrect = results.allSatisfy { $0.isCorrect }
        #expect(allCorrect)

        // With one sample per letter, holding it out leaves no template for that letter.
        let single = SyntheticInk.samples(["o"], perLetter: 1)
        #expect(Evaluation.leaveOneOut(samples: single, among: ["o"]).first?.guess == nil)
    }
}
