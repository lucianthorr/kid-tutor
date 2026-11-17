import CoreML
import Vision
import KidTutorKit

/// An image classifier trained in Create ML on the child's exported samples.
/// Only active when `HandwritingClassifier.mlmodel` has been added to App/KidTutor/Models.
struct CoreMLRecognizer: CharacterRecognizer, @unchecked Sendable {
    let id = "coreml"
    let name = "Trained model"
    private let model: VNCoreMLModel

    static func loadBundled() -> CoreMLRecognizer? {
        guard let url = Bundle.main.url(forResource: "HandwritingClassifier", withExtension: "mlmodelc") else {
            Log.info(.recognition, "coreml: no HandwritingClassifier in the app bundle")
            return nil
        }
        do {
            let model = try VNCoreMLModel(for: MLModel(contentsOf: url))
            Log.info(.recognition, "coreml: loaded \(url.lastPathComponent)")
            return CoreMLRecognizer(model: model)
        } catch {
            Log.error(.recognition, "coreml: couldn't load \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    func recognize(_ ink: Ink, among candidates: Set<String>) async -> [RecognitionCandidate] {
        // Same size and padding as the training images from kidtutor-export.
        guard let image = InkRenderer.render(ink) else { return [] }
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFit
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            Log.error(.recognition, "coreml failed: \(error)")
            return []
        }
        let observations = request.results as? [VNClassificationObservation] ?? []
        return observations
            .compactMap { observation -> RecognitionCandidate? in
                guard let label = CharacterLabel.character(fromFolderName: observation.identifier),
                      candidates.contains(label) else { return nil }
                return RecognitionCandidate(label: label, score: Double(observation.confidence))
            }
            .prefix(3)
            .map { $0 }
    }
}
