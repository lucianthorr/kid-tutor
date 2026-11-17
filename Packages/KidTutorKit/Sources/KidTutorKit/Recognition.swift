public struct RecognitionCandidate: Hashable, Sendable {
    public var label: String
    /// Higher is better. Scales differ between recognizers, so compare only within one.
    public var score: Double

    public init(label: String, score: Double) {
        self.label = label
        self.score = score
    }
}

/// Anything that can guess which character some ink is.
public protocol CharacterRecognizer: Sendable {
    var id: String { get }
    var name: String { get }
    /// Best guesses first, limited to `candidates`.
    func recognize(_ ink: Ink, among candidates: Set<String>) async -> [RecognitionCandidate]
}
