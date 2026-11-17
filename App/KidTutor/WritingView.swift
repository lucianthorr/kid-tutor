import SwiftUI
import KidTutorKit

/// A Writing session: characters written three times beside an example, then words.
/// Each item has a level: trace (faded letters in the boxes), copy (example shown), then from memory
/// (a character only spoken; a word shown for a moment, hidden, and written in one wide box).
struct WritingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var items: [WritingItem] = []
    @State private var itemIndex = 0
    @State private var level = 1
    @State private var boxes: [AnswerBox] = []
    /// Level 3: whether the example (a character) or the word (look, cover, write) is showing.
    @State private var showModel = true
    /// Look, cover, write: the word is showing before it's hidden.
    @State private var looking = false
    @State private var wordMissed: [String] = []
    @State private var checking = false
    @State private var usedHelp = false
    @State private var itemDone = false
    @State private var sessionDone = false
    @State private var tokensEarned = 0
    @State private var advanceTask: Task<Void, Never>?
    @State private var lookTask: Task<Void, Never>?

    private var item: WritingItem? { items.indices.contains(itemIndex) ? items[itemIndex] : nil }

    /// Look, cover, write: the whole word goes in one wide box.
    private var wholeWord: Bool {
        if case .word = item, level >= WritingItem.topLevel { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 24) {
            if sessionDone {
                SessionFinishedView(message: "Great writing!", tokens: tokensEarned) { dismiss() }
            } else if let item {
                ExerciseTopBar(
                    count: items.count,
                    index: itemIndex,
                    currentDone: itemDone,
                    helpDisabled: itemDone || looking,
                    onReplay: { model.speaker.say(wholeWord && !looking ? item.coverPrompt : item.prompt(level: level)) },
                    onHelp: giveHelp
                )
                Spacer(minLength: 0)
                switch item {
                case .character(let c): characterRow(c)
                case .word(let w): wordArea(w)
                }
                Text(itemDone ? item.praise : instruction(for: item))
                    .font(.title2)
                    .foregroundStyle(itemDone ? .green : .secondary)
                Spacer(minLength: 0)
                CheckButton(disabled: itemDone || checking || looking || boxes.allSatisfy { $0.accepted || $0.ink.isEmpty }) {
                    for i in boxes.indices where !boxes[i].ink.isEmpty { check(i) }
                }
            } else {
                ProgressView()
            }
        }
        .padding(32)
        .animation(.easeInOut, value: showModel)
        .onAppear(perform: startSession)
        .onDisappear {
            advanceTask?.cancel()
            lookTask?.cancel()
        }
    }

    private func instruction(for item: WritingItem) -> String {
        switch item {
        case .character: level <= 1 ? "Trace it three times" : "Write it three times"
        case .word: level <= 1 ? "Trace the word" : level == 2 ? "Copy the word" : looking ? "Look at the word" : "Write the word you saw"
        }
    }

    // MARK: - Layout

    /// The example on the left (so a right hand doesn't cover it), then three boxes.
    private func characterRow(_ character: String) -> some View {
        LetterRow(count: WritingItem.repetitions + 1) { size in
            Group {
                if showModel {
                    ModelBox(text: character)
                } else {
                    HiddenModel(systemImage: "ear")
                }
            }
            .frame(width: size.width, height: size.height)
            .padding(.trailing, 24)
            ForEach(boxes.indices.map { "\(itemIndex)-\($0)" }, id: \.self) { key in
                let i = Int(key.split(separator: "-")[1])!
                box(i, expected: character)
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    @ViewBuilder
    private func wordArea(_ word: String) -> some View {
        Group {
            if showModel {
                Text(word)
                    .font(KidFont.font(size: 110))
                    .padding(.horizontal, 48)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.secondary.opacity(0.45), lineWidth: 4))
                    .accessibilityLabel("Example: \(word)")
            } else {
                HiddenModel(systemImage: "eye.slash")
                    .frame(width: 260, height: 150)
            }
        }
        .frame(height: 170)
        if wholeWord {
            if boxes.indices.contains(0) {
                WholeWordBox(
                    box: Binding(get: { boxes.indices.contains(0) ? boxes[0] : AnswerBox() }, set: { if boxes.indices.contains(0) { boxes[0] = $0 } }),
                    word: word
                ) { autoCheckWholeWord(word) }
                .id(itemIndex)
                .disabled(itemDone || checking || looking)
            }
        } else {
            let letters = word.map(String.init)
            LetterRow(count: letters.count) { size in
                ForEach(boxes.indices.map { "\(itemIndex)-\($0)" }, id: \.self) { key in
                    let i = Int(key.split(separator: "-")[1])!
                    box(i, expected: letters.indices.contains(i) ? letters[i] : "")
                        .frame(width: size.width, height: size.height)
                }
            }
        }
    }

    private func box(_ i: Int, expected: String) -> some View {
        AnswerBoxView(
            box: Binding(get: { boxes.indices.contains(i) ? boxes[i] : AnswerBox() }, set: { if boxes.indices.contains(i) { boxes[i] = $0 } }),
            expected: expected
        ) { check(i) }
        .disabled(itemDone)
    }

    // MARK: - Flow

    private func startSession() {
        guard items.isEmpty else { return }
        items = model.writingSessionItems()
        itemIndex = 0
        if items.isEmpty {
            sessionDone = true
            return
        }
        startItem()
    }

    private func startItem() {
        guard let item else { return }
        let progress = model.writingProgress[item]
        level = min(progress.level, WritingItem.topLevel)
        let trace = level <= 1
        switch item {
        case .character:
            boxes = (0..<WritingItem.repetitions).map { _ in AnswerBox(trace: trace) }
        case .word(let w):
            boxes = level >= WritingItem.topLevel ? [AnswerBox()] : w.map { _ in AnswerBox(trace: trace) }
        }
        showModel = true
        looking = false
        wordMissed = []
        checking = false
        usedHelp = false
        itemDone = false
        Log.info(.writing, "item \(itemIndex + 1)/\(items.count) \(item.text) level=\(level) passes=\(progress.passes)")
        model.speaker.say(item.prompt(level: level))

        if level >= WritingItem.topLevel {
            if case .word(let w) = item {
                // Look, cover, write: show the word while it's read and spelled, then hide it.
                looking = true
                lookTask?.cancel()
                lookTask = Task {
                    try? await Task.sleep(for: .seconds(3 + 0.7 * Double(w.count)))
                    guard !Task.isCancelled, self.item == item else { return }
                    looking = false
                    showModel = false
                    model.speaker.say(item.coverPrompt)
                }
            } else {
                showModel = false
            }
        }
    }

    private func check(_ index: Int) {
        guard let item, boxes.indices.contains(index), !boxes[index].accepted, !boxes[index].ink.isEmpty else { return }
        if wholeWord {
            checkWholeWord()
            return
        }
        let expected: String
        switch item {
        case .character(let c): expected = c
        case .word(let w): expected = String(Array(w)[index])
        }
        let verdict = model.checkCharacter(
            boxes[index].ink,
            expected: expected,
            among: AppModel.AnswerCharacters(matching: expected),
            category: .writing,
            copied: showModel
        )
        switch boxes[index].judge(verdict) {
        case .accepted: break
        case .tryAgain: model.speaker.say("Almost! Try that one again.")
        case .trace: model.speaker.say("It's \(CharacterLabel.spokenName(for: expected)). Trace it.")
        }
        if boxes.allSatisfy(\.accepted) { finishItem() }
    }

    /// Checks the wide box when the pencil pauses, but only once enough letters seem written:
    /// children pause between letters.
    private func autoCheckWholeWord(_ word: String) {
        guard boxes.indices.contains(0), WordInk.letters(in: boxes[0].ink).count >= word.count else { return }
        checkWholeWord()
    }

    private func checkWholeWord() {
        guard let item, case .word(let word) = item, boxes.indices.contains(0), !boxes[0].accepted, !boxes[0].ink.isEmpty, !checking else { return }
        checking = true
        let ink = boxes[0].ink
        Task {
            let result = await model.checkWord(ink, expected: word, category: .writing)
            checking = false
            guard self.item == item, boxes.indices.contains(0), boxes[0].ink == ink else { return }
            wordMissed += result.missedLetters
            switch boxes[0].judge(result.verdict) {
            case .accepted: finishItem()
            case .tryAgain: model.speaker.say("Almost! Try the whole word again.")
            case .trace: model.speaker.say("Here's \(word). Trace it.")
            }
        }
    }

    /// Help never gives away more than the next step: the example, then a faded letter to trace.
    private func giveHelp() {
        guard let item, !itemDone else { return }
        if level <= 1 {
            // Already tracing: say the instruction again.
            model.speaker.say("Follow the gray \(item.text.count > 1 ? "letters" : "line") with your pencil.")
            return
        }
        usedHelp = true
        if !showModel {
            showModel = true
            Log.info(.writing, "help example \(item.text)")
            if wholeWord {
                model.speaker.say("Here it is again: \(item.text).")
                lookTask?.cancel()
                lookTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled, self.item == item, !itemDone else { return }
                    showModel = false
                }
            } else {
                model.speaker.say("Here's \(CharacterLabel.spokenName(for: item.text)). Copy it.")
            }
            return
        }
        guard let i = boxes.indices.first(where: { !boxes[$0].accepted }) else { return }
        boxes[i].showTrace = true
        Log.info(.writing, "help trace \(item.text) box \(i)")
        model.speaker.say("Trace the gray \(wholeWord ? "word" : "letter").")
    }

    private func finishItem() {
        guard let item, !itemDone else { return }
        itemDone = true
        lookTask?.cancel()
        showModel = true
        let missed: [String]
        switch item {
        case .character(let c): missed = boxes.contains { $0.misses > 0 } ? [c] : []
        case .word(let w):
            let letters = w.map(String.init)
            missed = wholeWord ? wordMissed : boxes.indices.filter { boxes[$0].misses > 0 && $0 < letters.count }.map { letters[$0] }
        }
        model.recordWriting(item, outcome: AnswerBox.outcome(of: boxes, usedHelp: usedHelp), missed: missed)
        model.speaker.say(item.praise)
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if itemIndex + 1 < items.count {
                itemIndex += 1
                startItem()
            } else {
                sessionDone = true
                tokensEarned = model.awardSessionTokens(.writing)
                Log.info(.writing, "session done items=\(items.count)")
                model.speaker.say("Great job! You finished your writing.\(TokenText.earned(tokensEarned))")
            }
        }
    }
}

/// Stands in for a hidden example: "listen" for a character written from memory, "hidden" for a covered word.
struct HiddenModel: View {
    var systemImage: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Image(systemName: systemImage)
            .font(.system(size: 54))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08), in: shape)
            .overlay(shape.stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 4, dash: [12, 8])))
            .accessibilityHidden(true)
    }
}
