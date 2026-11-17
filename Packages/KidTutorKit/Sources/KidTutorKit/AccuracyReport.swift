/// How well one recognizer did on reviewed test samples.
public struct RecognizerAccuracy: Hashable, Sendable {
    public struct Confusion: Hashable, Sendable {
        /// What the child wrote.
        public var written: String
        /// What the recognizer read instead. Empty when it had no guess.
        public var read: String
        public var count: Int
    }

    public struct CharacterScore: Hashable, Sendable {
        public var character: String
        public var attempts: Int
        public var correct: Int
        public var rate: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
    }

    public var recognizerID: String
    public var attempts: Int
    public var correct: Int
    /// Most frequent first.
    public var confusions: [Confusion]
    /// Worst first.
    public var characters: [CharacterScore]

    public var rate: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

public enum AccuracyReport {
    /// Scores each recognizer on reviewed test samples, optionally only the most recent `lastN`.
    public static func compute(samples: [InkSample], lastN: Int? = nil) -> [RecognizerAccuracy] {
        var reviewed = samples
            .filter { $0.source == .test && $0.confirmedLabel != nil }
            .sorted { $0.createdAt < $1.createdAt }
        if let lastN { reviewed = Array(reviewed.suffix(lastN)) }

        let ids = Set(reviewed.flatMap(\.recognized.keys)).sorted()
        return ids.map { id in
            var attempts = 0, correct = 0
            var confusions: [String: [String: Int]] = [:]
            var perCharacter: [String: (attempts: Int, correct: Int)] = [:]
            for sample in reviewed {
                guard let guess = sample.recognized[id], let truth = sample.confirmedLabel else { continue }
                attempts += 1
                let isCorrect = guess == truth
                if isCorrect {
                    correct += 1
                } else {
                    confusions[truth, default: [:]][guess, default: 0] += 1
                }
                perCharacter[truth, default: (0, 0)].attempts += 1
                if isCorrect { perCharacter[truth, default: (0, 0)].correct += 1 }
            }
            let confusionList = confusions
                .flatMap { written, reads in
                    reads.map { RecognizerAccuracy.Confusion(written: written, read: $0.key, count: $0.value) }
                }
                .sorted { ($0.count, $1.written, $1.read) > ($1.count, $0.written, $0.read) }
            let characterList = perCharacter
                .map { RecognizerAccuracy.CharacterScore(character: $0.key, attempts: $0.value.attempts, correct: $0.value.correct) }
                .sorted { ($0.rate, $1.attempts, $0.character) < ($1.rate, $0.attempts, $1.character) }
            return RecognizerAccuracy(
                recognizerID: id,
                attempts: attempts,
                correct: correct,
                confusions: confusionList,
                characters: characterList
            )
        }
    }
}
