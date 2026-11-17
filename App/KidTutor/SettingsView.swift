import SwiftUI
import KidTutorKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDelete = false
    @State private var confirmingCalibrationReset = false
    /// `-openProgress spelling` (or `logic` for Puzzles) at launch opens that subject's progress page.
    @State private var openedProgress: Subject? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-openProgress"), i + 1 < args.count else { return nil }
        return Subject(rawValue: args[i + 1])
    }()

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                ProgressSettingsSection()

                Section {
                    Toggle("Lowercase letters", isOn: $model.settings.alphabet.lowercase)
                    Toggle("Capital letters", isOn: $model.settings.alphabet.uppercase)
                    Toggle("Numbers", isOn: $model.settings.alphabet.digits)
                } header: {
                    Text("Characters")
                } footer: {
                    Text("Turning on both lowercase and capitals makes look-alikes such as o/O and s/S hard to tell apart.")
                }

                Section {
                    Stepper("Samples per character: \(model.settings.samplesPerCharacter)", value: $model.settings.samplesPerCharacter, in: 1...10)
                    Button("Reset calibration", role: .destructive) { confirmingCalibrationReset = true }
                        .disabled(model.samples.isEmpty)
                        .confirmationDialog("Reset handwriting calibration?", isPresented: $confirmingCalibrationReset, titleVisibility: .visible) {
                            Button("Reset calibration", role: .destructive) { model.resetCalibration() }
                        } message: {
                            Text("All \(model.samples.count) handwriting samples are deleted, so every letter and number is asked for again in Calibrate. A copy is kept in On My iPad › Kid Tutor › Backups.")
                        }
                } header: {
                    Text("Calibration")
                }

                Section {
                    Toggle("Finish when the pencil pauses", isOn: $model.settings.autoFinish)
                    if model.settings.autoFinish {
                        LabeledContent("Pause") {
                            HStack {
                                Slider(value: $model.settings.pauseSeconds, in: 0.8...3, step: 0.1)
                                    .frame(maxWidth: 280)
                                Text("\(model.settings.pauseSeconds, specifier: "%.1f") s")
                                    .monospacedDigit()
                                    .frame(width: 56, alignment: .trailing)
                            }
                        }
                    }
                    Toggle("Allow drawing with a finger", isOn: $model.settings.allowFingerInput)
                } header: {
                    Text("Writing")
                } footer: {
                    Text("Letters with several strokes, like k, t and E, need a longer pause. Finger drawing is for trying the app in the Simulator.")
                }

                VoiceSettingsSection()

                ReadingSettingsSection()

                RewardsSettingsSection()

                Section {
                    LabeledContent("Recognizers", value: model.recognizers.map(\.name).joined(separator: ", "))
                    LabeledContent("Saved samples", value: "\(model.samples.count)")
                    ShareLink("Export samples", item: model.store.fileURL)
                        .disabled(model.samples.isEmpty)
                    Button("Delete all samples", role: .destructive) { confirmingDelete = true }
                        .disabled(model.samples.isEmpty)
                } header: {
                    Text("Data")
                } footer: {
                    Text("Samples are also in the Files app under On My iPad › Kid Tutor › samples.json. Nothing leaves the iPad unless you export it.")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(item: $openedProgress) { subject in
                if subject == .logic { PuzzleProgressPage() } else { DeckPage(subject: subject) }
            }
            .confirmationDialog("Delete all \(model.samples.count) samples?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete all samples", role: .destructive) { model.deleteAllSamples() }
            } message: {
                Text("Calibration and test results will be gone. Export first if you want to keep them.")
            }
        }
    }
}

/// Claw-machine tokens: how many a session earns, and a way to give or take back a few.
struct RewardsSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Stepper("Tokens per finished session: \(model.settings.tokensPerSession)", value: $model.settings.tokensPerSession, in: 0...10)
            LabeledContent("Tokens now", value: "\(model.rewards.tokens)")
            HStack {
                Button("Give 1 token") { model.adjustTokens(by: 1) }
                Spacer()
                Button("Take back 1", role: .destructive) { model.adjustTokens(by: -1) }
                    .disabled(model.rewards.tokens == 0)
            }
            .buttonStyle(.borderless)
            LabeledContent("Toys won", value: "\(model.rewards.won.count) (\(model.rewards.collection.count) different)")
        } header: {
            Text("Rewards")
        } footer: {
            Text("One token is one try at the claw machine. The claw lands on the highest toy under it. Grabbed near its middle, the toy holds; grabbed off-center, it slips out. Each miss in a row makes the grip better, so by the third try any drop onto the pile wins. There is no luck involved.")
        }
    }
}
