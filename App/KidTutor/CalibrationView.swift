import SwiftUI
import KidTutorKit

/// The child copies each character a few times. These samples teach the personal recognizer
/// and become training images for a Core ML model.
struct CalibrationView: View {
    @Environment(AppModel.self) private var model
    @State private var ink = Ink.empty
    @State private var clearToken = 0
    @State private var skipped: Set<String> = []

    private var queue: [String] {
        model.calibrationPlan.remaining(given: model.samples).filter { !skipped.contains($0) }
    }

    var body: some View {
        let progress = model.calibrationPlan.progress(given: model.samples)
        VStack(spacing: 24) {
            if model.characters.isEmpty {
                ContentUnavailableView(
                    "No characters selected",
                    systemImage: "character",
                    description: Text("Turn on letters or numbers in Settings.")
                )
            } else if let current = queue.first {
                HStack(spacing: 20) {
                    Text("Write")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    PromptCharacter(character: current)
                    Button {
                        speak(current)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 36))
                    }
                    .accessibilityLabel("Say it again")
                }

                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                    Text("\(progress.done) of \(progress.total) written")
                }
                .frame(maxWidth: 520)

                WritingPad(ink: $ink, clearToken: clearToken) {
                    save(current)
                }
                .frame(maxWidth: 520)

                HStack(spacing: 16) {
                    Button("Start over", systemImage: "arrow.counterclockwise") { clear() }
                    Button("Skip", systemImage: "forward") {
                        Log.info(.calibration, "skip \(current)")
                        skipped.insert(current)
                        clear()
                        speakNext()
                    }
                    Button("Done", systemImage: "checkmark") { save(current) }
                        .buttonStyle(.borderedProminent)
                        .disabled(ink.isEmpty)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
            } else {
                ContentUnavailableView(
                    "All written",
                    systemImage: "checkmark.seal",
                    description: Text("Each character has \(model.settings.samplesPerCharacter) samples. Try the Test tab, or ask for more samples in Settings.")
                )
                if !skipped.isEmpty {
                    Button("Try the \(skipped.count) skipped characters") {
                        skipped = []
                        speakNext()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(32)
        .onAppear {
            Log.info(.calibration, "appear remaining=\(queue.count)")
            speakNext()
        }
    }

    private func save(_ character: String) {
        guard !ink.isEmpty else { return }
        model.add(InkSample(source: .calibration, ink: ink, expected: character, confirmedLabel: character))
        clear()
        speakNext()
    }

    private func clear() {
        ink = .empty
        clearToken += 1
    }

    private func speakNext() {
        if let next = queue.first { speak(next) }
    }

    private func speak(_ character: String) {
        model.speaker.say(CharacterLabel.spokenPrompt(for: character))
    }
}
