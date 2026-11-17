import SwiftUI
import KidTutorKit

/// A spelling session: a few words, each shown with blanks the child fills in by hand.
/// Blanks grow with each word's level, one random missing letter per level, up to the whole word,
/// which is written from memory in one wide box.
/// The word itself is only spoken, never printed: printing it would give the answer away.
struct SpellingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var words: [SpellingWord] = []
    @State private var wordIndex = 0
    @State private var boxes: [Int: AnswerBox] = [:]
    /// The top level: the whole word in one wide box instead of `boxes`.
    @State private var wholeWord = false
    @State private var wordBox = AnswerBox()
    @State private var wordMissed: [String] = []
    @State private var checking = false
    @State private var usedHelp = false
    @State private var wordDone = false
    @State private var sessionDone = false
    @State private var tokensEarned = 0
    @State private var advanceTask: Task<Void, Never>?

    private var word: SpellingWord? { words.indices.contains(wordIndex) ? words[wordIndex] : nil }

    var body: some View {
        VStack(spacing: 24) {
            if sessionDone {
                SessionFinishedView(message: "You practiced \(words.count) words!", tokens: tokensEarned) { dismiss() }
            } else if let word {
                ExerciseTopBar(
                    count: words.count,
                    index: wordIndex,
                    currentDone: wordDone,
                    helpDisabled: wordDone,
                    onReplay: { model.speaker.say(word.prompt) },
                    onHelp: giveHelp
                )
                Spacer(minLength: 0)
                letterRow(word)
                Text(wordDone ? "Yes! \(word.word)!" : wholeWord ? "Write the whole word in the yellow box" : "Write the missing letters in the yellow boxes")
                    .font(.title2)
                    .foregroundStyle(wordDone ? .green : .secondary)
                Spacer(minLength: 0)
                CheckButton(disabled: wordDone || checking || (wholeWord ? wordBox.ink.isEmpty : boxes.values.allSatisfy { $0.accepted || $0.ink.isEmpty })) {
                    if wholeWord {
                        checkWholeWord()
                    } else {
                        for index in boxes.keys.sorted() where !(boxes[index]?.ink.isEmpty ?? true) { check(index) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .padding(32)
        .onAppear(perform: startSession)
        .onDisappear { advanceTask?.cancel() }
    }

    @ViewBuilder
    private func letterRow(_ word: SpellingWord) -> some View {
        if wholeWord {
            WholeWordBox(box: $wordBox, word: word.word) { autoCheckWholeWord() }
                .id(wordIndex)
                .disabled(wordDone || checking)
        } else {
            letterBoxes(word)
        }
    }

    private func letterBoxes(_ word: SpellingWord) -> some View {
        let letters = word.letters
        return GeometryReader { geo in
            let gap: CGFloat = 14
            let width = min(150, (geo.size.width - gap * CGFloat(letters.count - 1)) / CGFloat(letters.count))
            HStack(spacing: gap) {
                // Identify boxes by word and position: identified by position alone, SwiftUI kept the
                // previous word's canvas (and its ink) when the next word had a blank in the same place.
                ForEach(letters.indices.map { "\(wordIndex)-\($0)" }, id: \.self) { key in
                    let i = Int(key.split(separator: "-")[1])!
                    Group {
                        if boxes[i] != nil {
                            AnswerBoxView(
                                box: Binding(get: { boxes[i] ?? AnswerBox() }, set: { boxes[i] = $0 }),
                                expected: letters[i]
                            ) { check(i) }
                            .disabled(wordDone)
                        } else {
                            GivenBox(text: letters[i])
                        }
                    }
                    .frame(width: width, height: width * 1.35)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 210)
    }

    // MARK: - Flow

    private func startSession() {
        guard words.isEmpty else { return }
        words = model.spellingSessionWords()
        wordIndex = 0
        if words.isEmpty {
            sessionDone = true
            return
        }
        startWord()
    }

    private func startWord() {
        guard let word else { return }
        let progress = model.spellingProgress[word.word]
        wholeWord = SpellingScaffold.isWholeWord(word.word, level: progress.level)
        let blanks = wholeWord ? [] : SpellingScaffold.blanks(in: word.word, level: progress.level)
        boxes = Dictionary(uniqueKeysWithValues: blanks.map { ($0, AnswerBox()) })
        wordBox = AnswerBox()
        wordMissed = []
        checking = false
        usedHelp = false
        wordDone = false
        Log.info(.spelling, "word \(wordIndex + 1)/\(words.count) \(word.word) level=\(progress.level) passes=\(progress.passes) \(wholeWord ? "whole word" : "blanks=\(blanks)")")
        model.speaker.say(word.prompt)
    }

    private func check(_ index: Int) {
        guard let word, var box = boxes[index], !box.accepted, !box.ink.isEmpty else { return }
        let letter = word.letters[index]
        let verdict = model.checkCharacter(box.ink, expected: letter, among: .lowercaseLetters, category: .spelling)
        switch box.judge(verdict) {
        case .accepted: break
        case .tryAgain: model.speaker.say("Almost! Try that letter again.")
        case .trace: model.speaker.say("It's the letter \(letter.uppercased()). Trace it.")
        }
        boxes[index] = box
        if boxes.values.allSatisfy(\.accepted) { finishWord() }
    }

    /// Checks the wide box when the pencil pauses, but only once it looks like enough letters are
    /// written: children pause between letters.
    private func autoCheckWholeWord() {
        guard let word, WordInk.letters(in: wordBox.ink).count >= word.letters.count else { return }
        checkWholeWord()
    }

    private func checkWholeWord() {
        guard let word, !wordBox.accepted, !wordBox.ink.isEmpty, !checking else { return }
        checking = true
        let ink = wordBox.ink
        Task {
            let result = await model.checkWord(ink, expected: word.word, category: .spelling)
            checking = false
            // The child may have kept writing while the check ran; judge only what was checked.
            guard self.word == word, wordBox.ink == ink else { return }
            wordMissed += result.missedLetters
            switch wordBox.judge(result.verdict) {
            case .accepted: finishWord()
            case .tryAgain: model.speaker.say("Almost! Try the whole word again.")
            case .trace: model.speaker.say("Here's how to spell \(word.word). \(word.spelledOut) Trace it.")
            }
        }
    }

    private func giveHelp() {
        guard let word else { return }
        if wholeWord {
            wordBox.showTrace = true
            usedHelp = true
            Log.info(.spelling, "help \(word.word) whole word")
            model.speaker.say("Here's how to spell \(word.word). \(word.spelledOut) Trace it.")
            return
        }
        guard let index = boxes.keys.sorted().first(where: { !(boxes[$0]?.accepted ?? true) }) else { return }
        boxes[index]?.showTrace = true
        usedHelp = true
        let letter = word.letters[index]
        Log.info(.spelling, "help \(word.word) letter=\(letter) at \(index)")
        model.speaker.say("It's the letter \(letter.uppercased()). Trace it.")
    }

    private func finishWord() {
        guard let word, !wordDone else { return }
        wordDone = true
        let missed = wholeWord ? wordMissed : boxes.filter { $0.value.misses > 0 }.map { word.letters[$0.key] }
        let outcome = AnswerBox.outcome(of: wholeWord ? [wordBox] : Array(boxes.values), usedHelp: usedHelp)
        model.recordSpelling(word, outcome: outcome, missed: missed)
        model.speaker.say("Yes! \(word.spelledOut) \(word.word)!")
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            if wordIndex + 1 < words.count {
                wordIndex += 1
                startWord()
            } else {
                sessionDone = true
                tokensEarned = model.awardSessionTokens(.spelling)
                Log.info(.spelling, "session done words=\(words.count)")
                model.speaker.say("Great job! You practiced \(words.count) words.\(TokenText.earned(tokensEarned))")
            }
        }
    }
}
