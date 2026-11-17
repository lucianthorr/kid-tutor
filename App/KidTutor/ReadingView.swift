import SwiftUI
import KidTutorKit

/// A reading session: the child reads each card aloud and on-device speech recognition checks it.
/// The app never says the card before the child tries; tapping a word (or Help) reads it, as a hint.
struct ReadingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [ReadingCard] = []
    @State private var cardIndex = 0
    @State private var misses = 0
    @State private var usedHelp = false
    @State private var cardDone = false
    @State private var sessionDone = false
    @State private var tokensEarned = 0
    @State private var feedback = ""
    @State private var lastHeard = ""
    @State private var advanceTask: Task<Void, Never>?
    @State private var simulatedSpeech = ""

    private var card: ReadingCard? { cards.indices.contains(cardIndex) ? cards[cardIndex] : nil }
    private var listener: SpeechListener { model.listener }
    private var micUsable: Bool { listener.availability == .ready || listener.availability == .needsPermission }

    var body: some View {
        VStack(spacing: 28) {
            if sessionDone {
                SessionFinishedView(message: "You read \(cards.count) cards!", tokens: tokensEarned) { dismiss() }
            } else if let card {
                ExerciseTopBar(
                    count: cards.count,
                    index: cardIndex,
                    currentDone: cardDone,
                    helpDisabled: cardDone,
                    onReplay: { say(card.instruction) },
                    onHelp: { readAloud(card) }
                )
                Spacer(minLength: 0)
                cardText(card)
                micButton(card)
                Text(heardLine)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(feedback.isEmpty ? " " : feedback)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(cardDone ? .green : .primary)
                if case .unavailable(let reason) = listener.availability {
                    Label(reason + " A grown-up can approve reading with the buttons below.", systemImage: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                #if targetEnvironment(simulator)
                // The Simulator has no working speech recognition (no model for any Speech API), so type
                // what the child "said" to test matching and feedback.
                TextField("Simulator only: type what was read, then Return", text: $simulatedSpeech)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                    .onSubmit {
                        Log.info(.reading, "simulated speech \"\(simulatedSpeech)\"")
                        evaluate(card, heard: [simulatedSpeech].filter { !$0.isEmpty })
                        simulatedSpeech = ""
                    }
                    .disabled(cardDone)
                #endif
                Spacer(minLength: 0)
                grownUpRow(card)
            } else {
                ProgressView()
            }
        }
        .padding(32)
        .onAppear(perform: startSession)
        .onDisappear {
            advanceTask?.cancel()
            listener.cancel()
        }
    }

    private var heardLine: String {
        if listener.isListening { return listener.heard.isEmpty ? "Listening…" : "Listening… I heard “\(shown(listener.heard))”" }
        return lastHeard.isEmpty ? " " : "I heard “\(shown(lastHeard))”"
    }

    /// What was heard, in the card's spelling when it counts as the card: the recognizer writes a
    /// sound-alike its own way ("Two" for "to"), and showing that tells a child they said something else.
    private func shown(_ heard: String) -> String {
        guard let card, ReadingCheck.verdict(for: card, heard: [heard]) == .correct else { return heard }
        return card.text
    }

    // MARK: - Pieces

    /// The card in Andika. Each word is a button that reads it aloud.
    private func cardText(_ card: ReadingCard) -> some View {
        HStack(spacing: card.isSentence ? 28 : 0) {
            ForEach(Array(card.text.split(separator: " ").enumerated()), id: \.offset) { _, piece in
                Button {
                    usedHelp = true
                    let word = ReadingCheck.words(in: String(piece)).first ?? String(piece)
                    Log.info(.reading, "tapped word \(word)")
                    say(word)
                } label: {
                    Text(piece)
                        .font(KidFont.font(size: card.isSentence ? 96 : 170))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }

    private func micButton(_ card: ReadingCard) -> some View {
        let listening = listener.isListening
        return Button {
            if listening {
                listener.cancel()
            } else if listener.availability == .needsPermission {
                Task {
                    await listener.requestPermission()
                    if listener.availability == .ready { listen(to: card) }
                }
            } else {
                listen(to: card)
            }
        } label: {
            Image(systemName: listening ? "waveform" : "mic.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: listening)
                .frame(width: 150, height: 150)
                .background(listening ? Color.red : Color.blue, in: Circle())
                .overlay(Circle().stroke((listening ? Color.red : Color.blue).opacity(0.25), lineWidth: 18).padding(-9))
        }
        .buttonStyle(.plain)
        .disabled(cardDone || !micUsable)
        .opacity(micUsable ? 1 : 0.35)
        .accessibilityLabel(listening ? "Stop listening" : "Tap, then read out loud")
    }

    /// Grown-up overrides: approve what the child read, or skip the card.
    private func grownUpRow(_ card: ReadingCard) -> some View {
        HStack(spacing: 16) {
            Text("Grown-up:")
                .foregroundStyle(.secondary)
            Button("Read it", systemImage: "checkmark") { accept(card, how: "grown-up") }
            Button("Skip", systemImage: "forward") {
                Log.info(.reading, "grown-up skipped \"\(card.text)\"")
                listener.cancel()
                next()
            }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(cardDone)
    }

    // MARK: - Flow

    private func startSession() {
        listener.checkStatus()
        guard cards.isEmpty else { return }
        cards = model.readingSessionCards()
        cardIndex = 0
        if cards.isEmpty {
            sessionDone = true
            return
        }
        startCard()
    }

    private func startCard() {
        guard let card else { return }
        misses = 0
        usedHelp = false
        cardDone = false
        feedback = ""
        lastHeard = ""
        Log.info(.reading, "card \(cardIndex + 1)/\(cards.count) \"\(card.text)\" box=\(model.readingProgress[card].box)")
        say(card.instruction)
    }

    private func listen(to card: ReadingCard) {
        model.speaker.stop()
        feedback = ""
        listener.start(
            hints: [card.text] + card.words,
            onUpdate: { ReadingCheck.verdict(for: card, heard: $0) == .correct },
            onFinish: { evaluate(card, heard: $0) }
        )
    }

    private func evaluate(_ card: ReadingCard, heard result: [String]?) {
        guard let alternatives = result else {
            feedback = ""
            say("Let's have a grown-up check this one.")
            return
        }
        // Listening only finishes once something was heard; stopping early reports nothing.
        guard let first = alternatives.first else { return }
        lastHeard = first
        let verdict = ReadingCheck.verdict(for: card, heard: alternatives)
        Log.info(.reading, "verdict \(verdict.rawValue) for \"\(card.text)\" misses=\(misses)")
        if verdict == .correct {
            accept(card, how: "speech")
            return
        }
        misses += 1
        switch misses {
        case 1:
            feedback = verdict == .close ? "So close!" : "Let's try again."
            say(verdict == .close ? "So close! Let's try once more." : "Let's try once more.")
        case 2:
            usedHelp = true
            feedback = "Listen, then read it."
            say(card.isSentence ? "Listen: \(card.text) Now you read it." : "This word is \(card.text). Say it with me.")
        default:
            model.recordReading(card, outcome: .hinted, how: "gave up after \(misses) tries")
            cardDone = true
            feedback = "Good try!"
            say("Good try! It says \(card.text). Let's keep going.")
            advance(after: 3.5)
        }
    }

    private func accept(_ card: ReadingCard, how: String) {
        guard !cardDone else { return }
        listener.cancel()
        cardDone = true
        let outcome: WordProgress.Outcome = usedHelp ? .hinted : misses > 0 ? .retried : .firstTry
        model.recordReading(card, outcome: outcome, how: how)
        feedback = "Yes!"
        say("Yes! \(card.text)")
        advance(after: 2.5)
    }

    private func readAloud(_ card: ReadingCard) {
        usedHelp = true
        Log.info(.reading, "help \"\(card.text)\"")
        say(card.isSentence ? "It says: \(card.text)" : "This word is \(card.text).")
    }

    private func advance(after seconds: Double) {
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            next()
        }
    }

    private func next() {
        if cardIndex + 1 < cards.count {
            cardIndex += 1
            startCard()
        } else {
            sessionDone = true
            tokensEarned = model.awardSessionTokens(.reading)
            Log.info(.reading, "session done cards=\(cards.count)")
            say("Great job! You read \(cards.count) cards.\(TokenText.earned(tokensEarned))")
        }
    }

    /// Speaking stops the mic first: the app mustn't hear itself, and a child who taps Help, Replay or a
    /// word while the mic waits has to hear the answer.
    private func say(_ text: String) {
        if listener.isListening {
            Log.info(.reading, "stopped listening to speak")
            listener.cancel()
        }
        model.speaker.say(text)
    }
}
