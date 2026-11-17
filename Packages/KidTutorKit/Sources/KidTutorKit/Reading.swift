import Foundation

/// Something to read aloud: a single word or a short sentence.
public struct ReadingCard: Codable, Hashable, Identifiable, Sendable {
    public var text: String
    /// Other ways speech recognition may write the same sound ("I" → "eye").
    public var soundsLike: [String]

    public init(_ text: String, soundsLike: [String] = []) {
        self.text = text
        self.soundsLike = soundsLike
    }

    public var id: String { text }
    public var words: [String] { ReadingCheck.words(in: text) }
    public var isSentence: Bool { words.count > 1 }
    /// Spoken when the card appears. Never says the word itself.
    public var instruction: String {
        isSentence ? "Read this sentence. Tap the microphone, then read it out loud."
                   : "Read this word. Tap the microphone, then read it out loud."
    }
}

/// Built-in cards until lessons come from the iCloud lesson folder: early sight words (Dolch
/// pre-primer and primer) roughly easiest first, then short sentences made of them, then the rest of the
/// Dolch pre-primer, primer and first-grade words (all but "a", "an" and "live"), each group followed by
/// sentences that use it.
/// "a" is left out: on its own, speech recognition hears it as "uh" or "hey".
public enum StarterReading {
    public static let cards: [ReadingCard] = [
        "the", "I", "to", "and", "is", "it", "in", "see", "can", "go",
        "me", "my", "we", "you", "up", "look", "play", "run", "said", "big",
        "red", "blue", "here", "where", "jump", "help", "come", "little", "funny", "yellow",
    ].map { ReadingCard($0) } + [
        "I can run.", "We see a dog.", "Look at me!", "My cat is big.", "Come and play.",
        "I see the sun.", "Can you jump?", "Here is my red ball.",
    ].map { ReadingCard($0) } + [
        "away", "down", "find", "for", "make", "not", "one", "two", "three", "all",
        "am", "are", "at", "ate", "be", "black", "brown", "but", "came", "did",
        "do", "eat", "four", "get", "good", "have", "he", "into", "like", "must",
        "new", "no", "now", "on", "our", "out", "please", "pretty", "ran", "ride",
        "saw", "say", "she", "so", "soon", "that", "there", "they", "this", "too",
        "under", "want", "was", "well", "went", "what", "white", "who", "will", "with",
        "yes",
    ].map { ReadingCard($0) } + [
        // Sentences using the words so far.
        "We went out to play.", "Please come with me.", "Who is under the bed?", "Look at the white dog!",
        "Can you find my brown hat?", "They ran down the hill.", "What did you eat?", "Where are my two red shoes?",
    ].map { ReadingCard($0) } + [
        "after", "again", "any", "as", "ask", "by", "could", "every", "fly", "from",
        "give", "going", "had", "has", "her", "him", "his", "how", "just", "know",
        "let", "may", "of", "old", "once", "open", "over", "put", "round", "some",
        "stop", "take", "thank", "them", "then", "think", "walk", "were", "when",
    ].map { ReadingCard($0) } + [
        "She has a black cat.", "He will open the box.", "Thank you for the good cake.", "I think it will rain.",
    ].map { ReadingCard($0) }
}

/// Decides whether what speech recognition heard matches the card. Lenient on purpose: children's
/// speech is hard to recognize, and a wrong "no" discourages more than a generous "yes".
public enum ReadingCheck {
    public enum Verdict: String, Sendable {
        case correct
        /// Nearly: a sentence with most words right, or a word one sound off.
        case close
        case incorrect
    }

    /// Words that sound the same; recognition picks one spelling.
    static let soundAlikes: [[String]] = [
        ["to", "two", "too", "2"], ["for", "four", "4"], ["one", "won", "1"], ["see", "sea", "c"],
        ["i", "eye", "aye"], ["red", "read"], ["blue", "blew"], ["here", "hear"], ["where", "wear"],
        ["no", "know"], ["be", "bee"], ["you", "u", "ewe"], ["right", "write"], ["sun", "son"],
        ["three", "3"], ["eight", "ate", "8"], ["by", "buy", "bye"],
        ["there", "their", "they're"], ["new", "knew"], ["our", "hour"], ["so", "sew"], ["him", "hymn"], ["some", "sum"],
    ]

    /// Lowercased words without punctuation.
    public static func words(in text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }

    /// Checks every alternative transcription and returns the best verdict.
    public static func verdict(for card: ReadingCard, heard alternatives: [String]) -> Verdict {
        let verdicts = alternatives.map { verdict(for: card, heard: $0) }
        if verdicts.contains(.correct) { return .correct }
        if verdicts.contains(.close) { return .close }
        return .incorrect
    }

    static func verdict(for card: ReadingCard, heard transcript: String) -> Verdict {
        let heard = words(in: transcript)
        guard !heard.isEmpty else { return .incorrect }
        let expected = card.words
        let extra = Set(card.soundsLike.map { $0.lowercased() })

        if expected.count == 1 {
            let target = expected[0]
            if heard.contains(where: { same(target, $0) || extra.contains($0) }) { return .correct }
            // One sound off in a longer word ("yellow" heard as "yello") still counts.
            if target.count >= 4, heard.contains(where: { distance(target, $0) <= 1 }) { return .correct }
            if heard.contains(where: { distance(target, $0) <= 2 && $0.count >= 2 }) { return .close }
            return .incorrect
        }

        // Sentences: share of the expected words heard, in any order.
        var remaining = heard
        var found = 0
        for word in expected {
            if let index = remaining.firstIndex(where: { same(word, $0) || (word.count >= 4 && distance(word, $0) <= 1) }) {
                found += 1
                remaining.remove(at: index)
            }
        }
        let share = Double(found) / Double(expected.count)
        if share >= 0.8 { return .correct }
        if share >= 0.5 { return .close }
        return .incorrect
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a == b || soundAlikes.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Levenshtein edit distance.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Progress on every reading card, saved as `Progress/reading.json`.
public struct ReadingProgress: JSONFile, Hashable {
    public var cards: [String: BoxProgress] = [:]

    public init() {}

    public subscript(card: ReadingCard) -> BoxProgress {
        get { cards[card.id] ?? BoxProgress() }
        set { cards[card.id] = newValue }
    }
}

/// Picks the cards for one reading session. A stand-in for FSRS scheduling.
public enum ReadingPlanner {
    /// Cards being learned (lowest box, least recently practiced first), then new cards in list order
    /// while fewer than `maxLearning` are being learned, then mastered cards for review.
    public static func sessionCards(
        from cards: [ReadingCard],
        progress: ReadingProgress,
        count: Int = 8,
        maxLearning: Int = 8
    ) -> [ReadingCard] {
        let started = cards.filter { progress.cards[$0.id] != nil }
        let learning = started.filter { !progress[$0].isMastered }
            .sorted { (progress[$0].box, progress[$0].lastPracticed ?? .distantPast) < (progress[$1].box, progress[$1].lastPracticed ?? .distantPast) }
        var picked = Array(learning.prefix(count))
        let fresh = cards.filter { progress.cards[$0.id] == nil }
        picked += fresh.prefix(min(max(0, maxLearning - learning.count), count - picked.count))
        if picked.count < count {
            let review = started.filter { progress[$0].isMastered }
                .sorted { (progress[$0].lastPracticed ?? .distantPast) < (progress[$1].lastPracticed ?? .distantPast) }
            picked += review.prefix(count - picked.count)
        }
        return picked
    }
}

/// What an error from the speech recognizer means for the child's turn.
public enum SpeechErrorMeaning: Equatable, Sendable {
    /// The recognizer stopped before hearing any speech: the child hasn't read yet. Keep listening;
    /// the mic waits as long as the child needs.
    case heardNothing
    /// The recognizer couldn't run at all (no speech model, broken setup): stop offering the mic.
    case cannotStart
    /// The turn ended after some speech: judge what was heard.
    case turnEnded

    /// "No speech detected" from the Siri/dictation recognizer.
    static let noSpeechCode = (domain: "kAFAssistantErrorDomain", code: 1110)

    /// Only a failure before any speech, very soon after the attempt started, means the recognizer can't
    /// start, and "no speech detected" never does: a child often takes a couple of seconds to begin.
    /// `secondsSinceStart` is for this attempt, not the whole turn: a recognizer that breaks after the
    /// child has been thinking for a while still fails fast on its next attempt.
    public static func of(domain: String, code: Int, heardAnything: Bool, secondsSinceStart: Double) -> SpeechErrorMeaning {
        if heardAnything { return .turnEnded }
        return !isNoSpeech(domain: domain, code: code) && secondsSinceStart < 2 ? .cannotStart : .heardNothing
    }

    public static func isNoSpeech(domain: String, code: Int) -> Bool {
        domain == noSpeechCode.domain && code == noSpeechCode.code
    }
}

/// While the mic waits for the child, recognition attempts that end with nothing heard start again.
/// This decides when that's normal waiting and when the recognizer is broken and should give up,
/// so a failing recognizer can't keep the mic red forever.
public struct ListeningRetries: Equatable, Sendable {
    public enum Next: Equatable, Sendable {
        case listenAgain(after: Double)
        case giveUp
    }

    /// Real errors in a row (not "no speech detected") before giving up.
    public static let maxFailures = 3
    /// Attempts in a row that end within a second, of any kind, before giving up.
    public static let maxQuickEnds = 5

    private var failures = 0
    private var quickEnds = 0

    public init() {}

    /// An attempt ran for `seconds` and ended with nothing heard; `failed` is a real error rather than
    /// "no speech detected" or a quiet end.
    public mutating func endedWithNothing(after seconds: Double, failed: Bool) -> Next {
        failures = failed ? failures + 1 : 0
        let quick = seconds < 1
        quickEnds = quick ? quickEnds + 1 : 0
        if failures >= Self.maxFailures || quickEnds >= Self.maxQuickEnds { return .giveUp }
        // An attempt that ended at once waits a moment, so a recognizer that keeps failing can't spin.
        return .listenAgain(after: quick ? 1 : 0)
    }
}
