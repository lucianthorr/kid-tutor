import SwiftUI
import KidTutorKit

/// The app asks for a character, every recognizer guesses, and a grown-up confirms what was
/// actually written. Guesses are recorded before the sample joins the training set, so the
/// personal recognizer is never scored on its own templates.
struct TestView: View {
    @Environment(AppModel.self) private var model
    @State private var target: String?
    @State private var ink = Ink.empty
    @State private var clearToken = 0
    @State private var results: [RecognizerResult]?
    @State private var isRecognizing = false
    @State private var showCharacter = false
    @State private var choosingLabel = false

    var body: some View {
        VStack(spacing: 24) {
            if let target {
                HStack(spacing: 20) {
                    Text("Write")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    // Reveal the answer once the recognizers have guessed.
                    PromptCharacter(character: showCharacter || results != nil ? target : "?")
                    Button {
                        speak(target)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 36))
                    }
                    .accessibilityLabel("Say it again")
                }
                Toggle("Show the character", isOn: $showCharacter)
                    .frame(maxWidth: 320)

                if model.pointCloud.templateCount == 0 {
                    Label("Calibrate first so the personal recognizer has examples to compare against.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }

                WritingPad(ink: $ink, clearToken: clearToken) {
                    Task { await recognize() }
                }
                .frame(maxWidth: 520)
                .disabled(results != nil)

                if let results {
                    RecognizerResultsPanel(results: results, target: target)
                        .frame(maxWidth: 640)
                    reviewButtons(target)
                } else {
                    HStack(spacing: 16) {
                        Button("Start over", systemImage: "arrow.counterclockwise") { clear() }
                        Button("Check", systemImage: "sparkle.magnifyingglass") {
                            Task { await recognize() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(ink.isEmpty || isRecognizing)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.extraLarge)
                }
            } else {
                ContentUnavailableView(
                    model.characters.isEmpty ? "No characters selected" : "Calibrate first",
                    systemImage: "character",
                    description: Text(model.characters.isEmpty
                        ? "Turn on letters or numbers in Settings."
                        : "Tests only ask for characters that have calibration samples. Write some in the Calibrate tab.")
                )
            }
        }
        .padding(32)
        .onAppear {
            if target == nil || !model.testableCharacters.contains(target!) { next() } else if let target { speak(target) }
        }
        .sheet(isPresented: $choosingLabel) {
            if let target {
                CharacterPicker(title: "What did they write?") { label in
                    choosingLabel = false
                    confirm(target, as: label)
                }
            }
        }
    }

    private func reviewButtons(_ target: String) -> some View {
        VStack(spacing: 12) {
            Text("Grown-up: what did they write?")
                .font(.headline)
            HStack(spacing: 16) {
                Button("“\(target)”, as asked", systemImage: "checkmark") { confirm(target, as: target) }
                    .buttonStyle(.borderedProminent)
                Button("Something else…", systemImage: "character.cursor.ibeam") { choosingLabel = true }
                Button("Unreadable, skip", systemImage: "xmark") {
                    Log.info(.test, "skip unreadable target=\(target)")
                    next()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func recognize() async {
        guard results == nil, !isRecognizing, !ink.isEmpty else {
            Log.debug(.test, "recognize skipped results=\(results != nil) busy=\(isRecognizing) empty=\(ink.isEmpty)")
            return
        }
        isRecognizing = true
        Log.info(.test, "recognize target=\(target ?? "-") \(ink.logSummary)")
        let start = ContinuousClock.now
        let found = await model.recognizeAll(ink)
        isRecognizing = false
        results = found
        Log.info(.test, "recognized in \(Log.elapsed(since: start))")
    }

    private func confirm(_ target: String, as label: String) {
        Log.info(.test, "confirm target=\(target) wrote=\(label)")
        var recognized: [String: String] = [:]
        for result in results ?? [] {
            recognized[result.id] = result.candidates.first?.label ?? ""
        }
        model.add(InkSample(source: .test, ink: ink, expected: target, confirmedLabel: label, recognized: recognized))
        next()
    }

    private func next() {
        target = model.nextTestCharacter(after: target)
        Log.info(.test, "next target=\(target ?? "-")")
        results = nil
        clear()
        if let target { speak(target) }
    }

    private func clear() {
        ink = .empty
        clearToken += 1
    }

    private func speak(_ character: String) {
        model.speaker.say(CharacterLabel.spokenPrompt(for: character))
    }
}

struct RecognizerResultsPanel: View {
    var results: [RecognizerResult]
    var target: String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Text("Asked for “\(target)”. Each recognizer read:")
                    .font(.headline)
                    .gridCellColumns(3)
            }
            ForEach(results) { result in
                GridRow {
                    Text(result.name)
                        .font(.headline)
                    if let top = result.candidates.first {
                        Label("read “\(top.label)”", systemImage: top.label == target ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(top.label == target ? .green : .red)
                    } else {
                        Text("No guess")
                            .foregroundStyle(.secondary)
                    }
                    Text(result.candidates.count > 1
                         ? "next: " + result.candidates.dropFirst().map { "\($0.label) \(String(format: "%.2f", $0.score))" }.joined(separator: "   ")
                         : "")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Every letter and digit, so a grown-up can record what was really written.
struct CharacterPicker: View {
    var title: String
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 12) {
                    ForEach(Alphabet.all.characters, id: \.self) { character in
                        Button {
                            onPick(character)
                        } label: {
                            Text(character)
                                .font(.system(size: 32, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 64)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
