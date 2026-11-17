import SwiftUI
import KidTutorKit

/// A math session: number facts as flashcards, the answer written digit by digit.
/// Help shows counting dots first, then the answer faded to trace.
struct MathView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var facts: [MathFact] = []
    @State private var factIndex = 0
    @State private var boxes: [AnswerBox] = []
    @State private var showDots = false
    @State private var usedHelp = false
    @State private var factDone = false
    @State private var sessionDone = false
    @State private var tokensEarned = 0
    @State private var advanceTask: Task<Void, Never>?

    private var fact: MathFact? { facts.indices.contains(factIndex) ? facts[factIndex] : nil }

    var body: some View {
        VStack(spacing: 24) {
            if sessionDone {
                SessionFinishedView(message: "You did \(facts.count) number facts!", tokens: tokensEarned) { dismiss() }
            } else if let fact {
                ExerciseTopBar(
                    count: facts.count,
                    index: factIndex,
                    currentDone: factDone,
                    helpDisabled: factDone,
                    onReplay: { model.speaker.say(fact.question) },
                    onHelp: giveHelp
                )
                Spacer(minLength: 0)
                HStack(spacing: 32) {
                    Text(fact.display)
                        .font(KidFont.font(size: 120))
                        .monospacedDigit()
                    // The fact index keeps each fact's boxes separate, so no ink carries over.
                    HStack(spacing: 14) {
                        ForEach(fact.answerDigits.indices.map { "\(factIndex)-\($0)" }, id: \.self) { key in
                            let i = Int(key.split(separator: "-")[1])!
                            AnswerBoxView(
                                box: Binding(get: { boxes.indices.contains(i) ? boxes[i] : AnswerBox() }, set: { if boxes.indices.contains(i) { boxes[i] = $0 } }),
                                expected: fact.answerDigits[i]
                            ) { check(i) }
                            .disabled(factDone)
                            .frame(width: 150, height: 150 * 1.35)
                        }
                    }
                }
                if showDots {
                    CountingDots(fact: fact)
                        .transition(.opacity)
                }
                Text(factDone ? fact.answerSentence : " ")
                    .font(.title2)
                    .foregroundStyle(.green)
                Spacer(minLength: 0)
                CheckButton(disabled: factDone || boxes.allSatisfy { $0.accepted || $0.ink.isEmpty }) {
                    for i in boxes.indices where !boxes[i].ink.isEmpty { check(i) }
                }
            } else {
                ProgressView()
            }
        }
        .padding(32)
        .animation(.easeInOut, value: showDots)
        .onAppear(perform: startSession)
        .onDisappear { advanceTask?.cancel() }
    }

    // MARK: - Flow

    private func startSession() {
        guard facts.isEmpty else { return }
        facts = model.mathSessionFacts()
        factIndex = 0
        if facts.isEmpty {
            sessionDone = true
            return
        }
        startFact()
    }

    private func startFact() {
        guard let fact else { return }
        boxes = fact.answerDigits.map { _ in AnswerBox() }
        showDots = false
        usedHelp = false
        factDone = false
        Log.info(.math, "fact \(factIndex + 1)/\(facts.count) \(fact.id)=\(fact.answer) box=\(model.mathProgress[fact].box)")
        model.speaker.say(fact.question)
    }

    private func check(_ index: Int) {
        guard let fact, boxes.indices.contains(index), !boxes[index].accepted, !boxes[index].ink.isEmpty else { return }
        let digit = fact.answerDigits[index]
        let verdict = model.checkCharacter(boxes[index].ink, expected: digit, among: .digits, category: .math)
        switch boxes[index].judge(verdict) {
        case .accepted: break
        case .tryAgain: model.speaker.say("Almost! Try again.")
        case .trace: model.speaker.say("It's \(fact.answer). Trace it.")
        }
        if boxes.allSatisfy(\.accepted) { finishFact() }
    }

    /// First Help shows counting dots; the next shows the answer to trace.
    private func giveHelp() {
        guard let fact else { return }
        usedHelp = true
        if !showDots {
            showDots = true
            Log.info(.math, "help dots \(fact.id)")
            model.speaker.say(fact.operation == .add
                ? "Count all the dots. \(fact.a) and \(fact.b) more."
                : "Start with \(fact.a) dots. Take away the \(fact.b) crossed out. Count what's left.")
        } else {
            for i in boxes.indices where !boxes[i].accepted { boxes[i].showTrace = true }
            Log.info(.math, "help trace \(fact.id)")
            model.speaker.say("It's \(fact.answer). Trace it.")
        }
    }

    private func finishFact() {
        guard let fact, !factDone else { return }
        factDone = true
        model.recordMath(fact, outcome: AnswerBox.outcome(of: boxes, usedHelp: usedHelp))
        model.speaker.say("Yes! \(fact.answerSentence)")
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if factIndex + 1 < facts.count {
                factIndex += 1
                startFact()
            } else {
                sessionDone = true
                tokensEarned = model.awardSessionTokens(.math)
                Log.info(.math, "session done facts=\(facts.count)")
                model.speaker.say("Great job! You did \(facts.count) number facts.\(TokenText.earned(tokensEarned))")
            }
        }
    }
}

/// Dots to count, in rows of five: for adding, a blue group and an orange group; for taking away,
/// the first number of dots with the ones taken away crossed out.
struct CountingDots: View {
    var fact: MathFact

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            if fact.operation == .add {
                dotGroup(count: fact.a, color: .blue, crossedFrom: nil)
                dotGroup(count: fact.b, color: .orange, crossedFrom: nil)
            } else {
                dotGroup(count: fact.a, color: .blue, crossedFrom: fact.a - fact.b)
            }
        }
        .accessibilityLabel(fact.operation == .add
            ? "\(fact.a) blue dots and \(fact.b) orange dots"
            : "\(fact.a) dots, \(fact.b) crossed out")
    }

    private func dotGroup(count: Int, color: Color, crossedFrom: Int?) -> some View {
        let columns = Array(repeating: GridItem(.fixed(34), spacing: 10), count: 5)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .overlay {
                        if let crossedFrom, i >= crossedFrom {
                            Image(systemName: "xmark")
                                .font(.system(size: 30, weight: .heavy))
                                .foregroundStyle(.red)
                        }
                    }
                    .opacity(crossedFrom.map { i >= $0 ? 0.35 : 1 } ?? 1)
            }
        }
        .frame(width: 5 * 34 + 4 * 10)
    }
}
