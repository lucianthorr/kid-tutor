import Foundation

/// Splits a whole word written in one wide box into its letters.
public enum WordInk {
    /// Groups strokes into letters, left to right. Strokes whose left-to-right extents overlap belong to
    /// the same letter, so the dot of an i and the bar of a t stay with their letter. Letters written
    /// touching each other can't be split; the caller falls back to reading the word as text.
    ///
    /// Two extents overlap when they share at least `overlap` of the narrower one. Every extent is at
    /// least `minimumWidth` of the ink's height wide, so a dot (no width at all) can still overlap.
    public static func letters(in ink: Ink, overlap: Double = 0.3, minimumWidth: Double = 0.08) -> [Ink] {
        guard let bounds = ink.bounds else { return [] }
        let minWidth = max(bounds.height * minimumWidth, 1)

        struct Group {
            var minX: Double
            var maxX: Double
            var strokes: [Int]
        }
        let extents: [(index: Int, minX: Double, maxX: Double)] = ink.strokes.enumerated().compactMap { index, stroke in
            guard let lo = stroke.points.map(\.x).min(), let hi = stroke.points.map(\.x).max() else { return nil }
            let pad = max(0, minWidth - (hi - lo)) / 2
            return (index, lo - pad, hi + pad)
        }
        var groups: [Group] = []
        for extent in extents.sorted(by: { $0.minX < $1.minX }) {
            if var last = groups.last {
                let shared = min(last.maxX, extent.maxX) - max(last.minX, extent.minX)
                let narrower = min(last.maxX - last.minX, extent.maxX - extent.minX)
                if shared >= overlap * narrower {
                    last.minX = min(last.minX, extent.minX)
                    last.maxX = max(last.maxX, extent.maxX)
                    last.strokes.append(extent.index)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append(Group(minX: extent.minX, maxX: extent.maxX, strokes: [extent.index]))
        }
        return groups.map { group in
            Ink(strokes: group.strokes.sorted().map { ink.strokes[$0] }, canvasWidth: ink.canvasWidth, canvasHeight: ink.canvasHeight)
        }
    }
}

/// Decides whether a word written in one wide box is the word expected.
public enum WordCheck {
    public struct Result: Hashable, Sendable {
        public var verdict: LetterCheck.Verdict
        /// Expected letters judged wrong, when the ink split into the right number of letters.
        public var missedLetters: [String]
        /// How it was decided: "letters" (each letter checked), "text" (read as a word) or "none".
        public var how: String
    }

    /// Correct when the ink split into one piece per letter and no letter was wrong, or when a text
    /// reader read exactly the expected word. Lenient on purpose, like `LetterCheck`.
    ///
    /// - Parameters:
    ///   - letters: a verdict per letter, or nil when the ink didn't split into as many letters as expected.
    ///   - read: what a text reader read, best first (may be empty).
    public static func verdict(expected: String, letters: [LetterCheck.Verdict]?, read: [String]) -> Result {
        let expectedLetters = expected.lowercased().map(String.init)
        var missed: [String] = []
        if let letters, letters.count == expectedLetters.count {
            if !letters.contains(.incorrect) {
                return Result(verdict: letters.contains(.correct) ? .correct : .unverified, missedLetters: [], how: "letters")
            }
            missed = zip(expectedLetters, letters).filter { $0.1 == .incorrect }.map(\.0)
        }
        if read.contains(where: { normalized($0) == normalized(expected) }) {
            return Result(verdict: .correct, missedLetters: [], how: "text")
        }
        return Result(verdict: .incorrect, missedLetters: missed, how: "none")
    }

    /// Lowercase letters only: text readers add spaces, capitals and stray punctuation.
    static func normalized(_ text: String) -> String {
        String(text.lowercased().filter(\.isLetter))
    }
}

extension Ink {
    /// False for a tiny mark (a tap or a stray dot) that shouldn't be kept as an example of a character:
    /// the ink must span at least `fraction` of the box's height.
    public func isBigEnough(fraction: Double = 0.2) -> Bool {
        guard let bounds, canvasHeight > 0 else { return false }
        return max(bounds.width, bounds.height) >= canvasHeight * fraction
    }
}
