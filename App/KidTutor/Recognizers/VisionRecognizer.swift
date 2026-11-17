import Vision
import KidTutorKit

/// Apple's built-in on-device text recognition, kept as a baseline. It reads lines of text, not lone
/// characters: in `.accurate` mode it finds no text at all in a single handwritten letter (checked on the
/// simulator and on macOS, with and without extra padding), so this uses `.fast`, which at least guesses.
struct VisionRecognizer: CharacterRecognizer {
    let id = "vision"
    let name = "Apple Vision (baseline)"

    func recognize(_ ink: Ink, among candidates: Set<String>) async -> [RecognitionCandidate] {
        // Generous padding: text recognition does better with whitespace around the character.
        guard let image = InkRenderer.render(ink, size: 256, padding: 0.3, lineWidthFraction: 0.05) else {
            Log.warning(.recognition, "vision: couldn't render ink \(ink.logSummary)")
            return []
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            Log.error(.recognition, "vision failed: \(error)")
            return []
        }
        let observations = request.results ?? []
        let read = observations.flatMap { $0.topCandidates(5).map { "\"\($0.string)\"" } }
        Log.debug(.recognition, "vision read \(observations.count) observations: \(read.joined(separator: " "))")
        var best: [String: Double] = [:]
        for observation in observations {
            for text in observation.topCandidates(5) {
                for label in CharacterLabel.labels(fromOCRText: text.string, among: candidates) {
                    best[label] = max(best[label] ?? 0, Double(text.confidence))
                }
            }
        }
        return best
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { RecognitionCandidate(label: $0.key, score: $0.value) }
    }

    /// Reads a whole handwritten word, best guesses first. Unlike single letters, `.accurate` mode reads
    /// words well. Language correction stays off: it would turn a misspelling into the right word.
    func readText(_ ink: Ink) async -> [String] {
        guard let image = InkRenderer.render(ink, size: 768, padding: 0.08, lineWidthFraction: 0.012) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            Log.error(.recognition, "vision text failed: \(error)")
            return []
        }
        // A word split into pieces comes back as several observations; join them left to right.
        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        let joined = observations.compactMap { $0.topCandidates(1).first?.string }.joined()
        var reads = observations.count == 1 ? observations[0].topCandidates(10).map(\.string) : []
        if !joined.isEmpty && !reads.contains(joined) { reads.insert(joined, at: 0) }
        return reads
    }
}
