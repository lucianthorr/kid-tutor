/// Offline checks of recognizer quality on saved samples.
public enum Evaluation {
    public struct Result: Hashable, Sendable {
        public var sampleID: InkSample.ID
        public var truth: String
        public var guess: String?
        public var isCorrect: Bool { guess == truth }
    }

    /// Scores the personal recognizer by holding out each confirmed sample in turn and
    /// recognizing it with templates built from all the others.
    public static func leaveOneOut(samples: [InkSample], among candidates: Set<String>) -> [Result] {
        let labeled = samples.filter { $0.confirmedLabel != nil }
        return labeled.map { held in
            let recognizer = PointCloudRecognizer(samples: labeled.filter { $0.id != held.id })
            let guess = recognizer.classify(held.ink, among: candidates, limit: 1).first?.label
            return Result(sampleID: held.id, truth: held.confirmedLabel!, guess: guess)
        }
    }
}
