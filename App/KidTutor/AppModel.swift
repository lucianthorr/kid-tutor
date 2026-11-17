import Foundation
import Observation
import KidTutorKit

struct Phase0Settings: Codable, Equatable {
    var alphabet = Alphabet()
    var samplesPerCharacter = 3
    /// Treat the character as finished when the pencil has been lifted this long.
    var autoFinish = true
    var pauseSeconds = 1.5
    /// The Simulator has no Apple Pencil (mouse clicks arrive as finger touches), so allow fingers there.
    #if targetEnvironment(simulator)
    var allowFingerInput = true
    #else
    var allowFingerInput = false
    #endif
    /// Nil means the best installed voice.
    var voiceIdentifier: String?
    /// AVSpeechUtterance rate (0.5 is the system default).
    var speechRate = 0.45
    /// Claw-machine tokens for each finished practice session.
    var tokensPerSession = 3

    init() {}

    /// Missing keys keep their defaults, so adding a setting doesn't reset the others.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Phase0Settings()
        alphabet = try c.decodeIfPresent(Alphabet.self, forKey: .alphabet) ?? d.alphabet
        samplesPerCharacter = try c.decodeIfPresent(Int.self, forKey: .samplesPerCharacter) ?? d.samplesPerCharacter
        autoFinish = try c.decodeIfPresent(Bool.self, forKey: .autoFinish) ?? d.autoFinish
        pauseSeconds = try c.decodeIfPresent(Double.self, forKey: .pauseSeconds) ?? d.pauseSeconds
        allowFingerInput = try c.decodeIfPresent(Bool.self, forKey: .allowFingerInput) ?? d.allowFingerInput
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        speechRate = try c.decodeIfPresent(Double.self, forKey: .speechRate) ?? d.speechRate
        tokensPerSession = try c.decodeIfPresent(Int.self, forKey: .tokensPerSession) ?? d.tokensPerSession
    }
}

struct RecognizerResult: Identifiable {
    let id: String
    let name: String
    let candidates: [RecognitionCandidate]
}

@MainActor
@Observable
final class AppModel {
    private(set) var samples: [InkSample] = []
    var settings: Phase0Settings {
        didSet {
            guard settings != oldValue else { return }
            Log.info(.settings, "changed: \(settings)")
            saveSettings()
            if settings.voiceIdentifier != oldValue.voiceIdentifier || settings.speechRate != oldValue.speechRate {
                speaker.configure(voiceIdentifier: settings.voiceIdentifier, rate: settings.speechRate)
            }
        }
    }
    var lastError: String?

    let store: SampleStore
    let speaker = Speaker()
    let vision = VisionRecognizer()
    let coreML = CoreMLRecognizer.loadBundled()
    private(set) var pointCloud = PointCloudRecognizer(samples: [])
    private(set) var spellingProgress = SpellingProgress()
    let spellingProgressURL: URL
    private(set) var mathProgress = MathProgress()
    let mathProgressURL: URL
    private(set) var readingProgress = ReadingProgress()
    let readingProgressURL: URL
    private(set) var writingProgress = WritingProgress()
    let writingProgressURL: URL
    private(set) var puzzleProgress = PuzzleProgress()
    let puzzleProgressURL: URL
    private(set) var rewards = RewardsState()
    let rewardsURL: URL
    let listener = SpeechListener()

    private static let settingsKey = "phase0.settings"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        store = SampleStore(directory: documents)
        spellingProgressURL = documents.appendingPathComponent("Progress/spelling.json")
        mathProgressURL = documents.appendingPathComponent("Progress/math.json")
        readingProgressURL = documents.appendingPathComponent("Progress/reading.json")
        writingProgressURL = documents.appendingPathComponent("Progress/writing.json")
        puzzleProgressURL = documents.appendingPathComponent("Progress/puzzles.json")
        rewardsURL = documents.appendingPathComponent("Progress/rewards.json")
        settings = Self.loadSettings()
        do {
            spellingProgress = try SpellingProgress.load(from: spellingProgressURL)
        } catch {
            Log.error(.storage, "spelling progress load failed: \(error)")
        }
        do {
            mathProgress = try MathProgress.load(from: mathProgressURL)
        } catch {
            Log.error(.storage, "math progress load failed: \(error)")
        }
        do {
            readingProgress = try ReadingProgress.load(from: readingProgressURL)
        } catch {
            Log.error(.storage, "reading progress load failed: \(error)")
        }
        do {
            writingProgress = try WritingProgress.load(from: writingProgressURL)
        } catch {
            Log.error(.storage, "writing progress load failed: \(error)")
        }
        do {
            puzzleProgress = try PuzzleProgress.load(from: puzzleProgressURL)
        } catch {
            Log.error(.storage, "puzzle progress load failed: \(error)")
        }
        do {
            rewards = try RewardsState.load(from: rewardsURL)
        } catch {
            Log.error(.storage, "rewards load failed: \(error)")
        }
        do {
            samples = try store.load()
        } catch {
            lastError = "Couldn't read the saved samples: \(error.localizedDescription)"
            Log.error(.storage, "load failed: \(error)")
        }
        pointCloud = PointCloudRecognizer(samples: samples)

        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
        #if targetEnvironment(simulator)
        let device = "simulator"
        #else
        let device = "device"
        #endif
        Log.info(.app, "launch version=\(version) \(device) samples=\(samples.count) templates=\(pointCloud.templateCount) coreML=\(coreML != nil) settings=\(settings)")
        Log.info(.app, "documents=\(documents.path)")

        speaker.configure(voiceIdentifier: settings.voiceIdentifier, rate: settings.speechRate)
        Task {
            let voices = await Speaker.availableVoices()
            let byQuality = Dictionary(grouping: voices, by: \.quality.label).mapValues(\.count)
            let better = voices.filter { $0.quality > .standard }.map { "\($0.name) [\($0.quality.label)]" }
            Log.info(.speech, "english voices \(byQuality.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")); better: \(better.isEmpty ? "none installed" : better.joined(separator: ", "))")
        }

        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-speechProbe"), i + 1 < args.count, #available(iOS 26, *) {
            Task { await SpeechProbe.run(fileName: args[i + 1]) }
        }

        if ProcessInfo.processInfo.arguments.contains("-recognizerSelfCheck") {
            Task { await runSelfCheck() }
        }
    }

    var characters: [String] { settings.alphabet.characters }

    var calibrationPlan: CalibrationPlan {
        CalibrationPlan(characters: characters, samplesPerCharacter: settings.samplesPerCharacter)
    }

    var recognizers: [any CharacterRecognizer] {
        var list: [any CharacterRecognizer] = [pointCloud, vision]
        if let coreML { list.append(coreML) }
        return list
    }

    func recognizerName(_ id: String) -> String {
        recognizers.first { $0.id == id }?.name ?? id
    }

    func recognizeAll(_ ink: Ink) async -> [RecognizerResult] {
        let candidates = Set(characters)
        var results: [RecognizerResult] = []
        if ink.hasNonFiniteValues {
            Log.warning(.ink, "ink has non-finite values: \(ink.logSummary)")
        }
        for recognizer in recognizers {
            let start = ContinuousClock.now
            let found = await recognizer.recognize(ink, among: candidates)
            Log.info(.recognition, "\(recognizer.id) -> \(found.logDescription) in \(Log.elapsed(since: start))")
            results.append(RecognizerResult(id: recognizer.id, name: recognizer.name, candidates: found))
        }
        return results
    }

    /// Active characters the personal recognizer has at least one example of. Testing others
    /// only measures missing calibration, not recognition.
    var testableCharacters: [String] {
        let known = pointCloud.labels
        return characters.filter(known.contains)
    }

    /// The testable character with the fewest test samples so far, avoiding an immediate repeat.
    func nextTestCharacter(after previous: String?) -> String? {
        let characters = testableCharacters
        var counts: [String: Int] = [:]
        for sample in samples where sample.source == .test {
            counts[sample.expected, default: 0] += 1
        }
        let pool = characters.count > 1 ? characters.filter { $0 != previous } : characters
        guard let fewest = pool.map({ counts[$0, default: 0] }).min() else { return nil }
        return pool.filter { counts[$0, default: 0] == fewest }.randomElement()
    }

    // MARK: - Samples

    func add(_ sample: InkSample) {
        let guesses = sample.recognized.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.isEmpty ? "-" : $0.value)" }
        Log.info(.storage, "add \(sample.source.rawValue) expected=\(sample.expected) label=\(sample.confirmedLabel ?? "-") \(guesses.joined(separator: " ")) \(sample.ink.logSummary)")
        samples.append(sample)
        samplesChanged()
    }

    func delete(_ id: InkSample.ID) {
        Log.info(.storage, "delete \(id)")
        samples.removeAll { $0.id == id }
        samplesChanged()
    }

    func relabel(_ id: InkSample.ID, as label: String) {
        guard let index = samples.firstIndex(where: { $0.id == id }) else { return }
        Log.info(.storage, "relabel \(id) \(samples[index].confirmedLabel ?? "-") -> \(label)")
        samples[index].confirmedLabel = label
        samplesChanged()
    }

    func deleteAllSamples() {
        Log.info(.storage, "delete all (\(samples.count) samples)")
        samples = []
        samplesChanged()
    }

    private func samplesChanged() {
        pointCloud = PointCloudRecognizer(samples: samples)
        do {
            try store.save(samples)
        } catch {
            lastError = "Couldn't save the samples: \(error.localizedDescription)"
            Log.error(.storage, "save failed: \(error)")
        }
    }

    // MARK: - Spelling

    func spellingSessionWords() -> [SpellingWord] {
        let words = SpellingPlanner.sessionWords(from: StarterWords.spelling, progress: spellingProgress)
        Log.info(.spelling, "session words: " + words.map { "\($0.word)(L\(spellingProgress[$0.word].level))" }.joined(separator: " "))
        return words
    }

    func recordSpelling(_ word: SpellingWord, outcome: WordProgress.Outcome, missed: [String]) {
        var progress = spellingProgress[word.word]
        let before = progress.level
        progress.record(
            outcome,
            missed: missed,
            topLevel: SpellingScaffold.topLevel(for: word.word),
            passesToLevelUp: SpellingScaffold.passesToLevelUp
        )
        spellingProgress[word.word] = progress
        Log.info(.spelling, "word \(word.word) \(outcome.rawValue) missed=\(missed.joined()) level \(before)->\(progress.level) passes=\(progress.passes)\(progress.isMastered ? " MASTERED" : "")")
        do {
            try spellingProgress.save(to: spellingProgressURL)
        } catch {
            Log.error(.storage, "spelling progress save failed: \(error)")
        }
    }

    /// Characters a written answer is compared against.
    /// Characters a written answer is compared against. Limited to one kind, because the personal
    /// recognizer ignores size and can't tell o from O or s from S.
    enum AnswerCharacters {
        case lowercaseLetters, uppercaseLetters, digits

        /// The kind `character` belongs to.
        init(matching character: String) {
            let c = character.first
            if c?.isNumber == true {
                self = .digits
            } else if c?.isUppercase == true {
                self = .uppercaseLetters
            } else {
                self = .lowercaseLetters
            }
        }

        var set: Set<String> {
            switch self {
            case .lowercaseLetters: Set(Alphabet(lowercase: true, uppercase: false, digits: false).characters)
            case .uppercaseLetters: Set(Alphabet(lowercase: false, uppercase: true, digits: false).characters)
            case .digits: Set(Alphabet(lowercase: false, uppercase: false, digits: true).characters)
            }
        }
    }

    /// Judges one handwritten character and keeps the sample.
    /// - Parameter copied: the child was shown the character (tracing or copying it), so if the recognizer
    ///   can't judge it yet, it's kept as an example anyway, the way calibration keeps what it asked for.
    func checkCharacter(
        _ ink: Ink,
        expected: String,
        among answers: AnswerCharacters,
        category: Log.Category,
        copied: Bool = false
    ) -> LetterCheck.Verdict {
        let candidates = pointCloud.classify(ink, among: answers.set)
        let examples = pointCloud.templateCount(for: expected)
        let verdict = LetterCheck.verdict(expected: expected, candidates: candidates, examplesOfExpected: examples)
        Log.info(category, "character expected=\(expected) examples=\(examples) -> \(verdict.rawValue) (\(candidates.logDescription)) \(ink.logSummary)")
        // Only letters that passed a real check become examples. An unverified letter is accepted so the
        // child isn't blocked, but it may be a scribble, and one bad example ruins a letter with few examples.
        // A copied one is kept if it's big enough not to be a stray mark.
        let keep = verdict == .correct || (verdict == .unverified && copied && ink.isBigEnough())
        add(InkSample(
            source: .practice,
            ink: ink,
            expected: expected,
            confirmedLabel: keep ? expected : nil,
            recognized: [pointCloud.id: candidates.first?.label ?? ""]
        ))
        return verdict
    }

    /// Judges a whole lowercase word written in one wide box: split into letters and check each with the
    /// personal recognizer, and if that doesn't pass, read it as text with Apple Vision. Letters that pass
    /// become examples; the whole word isn't kept.
    func checkWord(_ ink: Ink, expected: String, category: Log.Category) async -> WordCheck.Result {
        let expectedLetters = expected.lowercased().map(String.init)
        let pieces = WordInk.letters(in: ink)
        var verdicts: [LetterCheck.Verdict]?
        var guesses: [String] = []
        if pieces.count == expectedLetters.count {
            let among = AnswerCharacters.lowercaseLetters.set
            var judged: [LetterCheck.Verdict] = []
            for (piece, letter) in zip(pieces, expectedLetters) {
                let candidates = pointCloud.classify(piece, among: among)
                let verdict = LetterCheck.verdict(expected: letter, candidates: candidates, examplesOfExpected: pointCloud.templateCount(for: letter))
                judged.append(verdict)
                guesses.append(candidates.first?.label ?? "?")
            }
            verdicts = judged
        }
        var read: [String] = []
        if verdicts == nil || verdicts!.contains(.incorrect) {
            read = await vision.readText(ink)
        }
        let result = WordCheck.verdict(expected: expected, letters: verdicts, read: read)
        Log.info(category, "word expected=\(expected) pieces=\(pieces.count) letters=\(guesses.joined()) \(verdicts.map { $0.map(\.rawValue).joined(separator: ",") } ?? "-") read=\(read.prefix(5)) -> \(result.verdict.rawValue) via \(result.how) missed=\(result.missedLetters.joined()) \(ink.logSummary)")
        if let verdicts {
            for (piece, (letter, verdict)) in zip(pieces, zip(expectedLetters, verdicts)) where verdict == .correct {
                add(InkSample(source: .practice, ink: piece, expected: letter, confirmedLabel: letter, recognized: [pointCloud.id: letter]))
            }
        }
        return result
    }

    // MARK: - Writing

    func writingSessionItems() -> [WritingItem] {
        let items = WritingPlanner.sessionItems(words: StarterWords.spelling.map(\.word), progress: writingProgress)
        Log.info(.writing, "session items: " + items.map { "\($0.text)(L\(writingProgress[$0].level))" }.joined(separator: " "))
        return items
    }

    func recordWriting(_ item: WritingItem, outcome: WordProgress.Outcome, missed: [String]) {
        let before = writingProgress[item].level
        writingProgress.record(item, outcome, missed: missed)
        let after = writingProgress[item]
        Log.info(.writing, "item \(item.text) \(outcome.rawValue) missed=\(missed.joined()) level \(before)->\(after.level) passes=\(after.passes)\(after.isMastered ? " MASTERED" : "")")
        do {
            try writingProgress.save(to: writingProgressURL)
        } catch {
            Log.error(.storage, "writing progress save failed: \(error)")
        }
    }

    // MARK: - Rewards

    /// Tokens for finishing a practice session. Returns how many were earned.
    func awardSessionTokens(_ subject: Subject) -> Int {
        let count = settings.tokensPerSession
        rewards.earn(count)
        Log.info(.rewards, "earned \(count) for \(subject.rawValue) session, tokens=\(rewards.tokens)")
        saveRewards()
        return count
    }

    /// A grown-up's gift or correction from Settings. Never below zero.
    func adjustTokens(by delta: Int) {
        if delta > 0 {
            rewards.earn(delta)
        } else {
            rewards.tokens = max(0, rewards.tokens + delta)
        }
        Log.info(.rewards, "grown-up adjusted tokens by \(delta), tokens=\(rewards.tokens)")
        saveRewards()
    }

    /// Spends a token and decides the drop. Saved before any animation plays.
    func dropClaw(at x: Double) -> RewardsState.Drop? {
        let reach = ClawMachine.secureReach(missStreak: rewards.missStreak)
        guard let drop = rewards.drop(at: x) else {
            Log.info(.rewards, "drop with no tokens")
            return nil
        }
        let result: String
        switch drop.grab {
        case .caught: result = "caught \(drop.caught?.id ?? "?")"
        case .slipped(let i, let lift): result = "slipped toy \(i) lift=\(String(format: "%.2f", lift))"
        case .missed: result = "missed"
        }
        Log.info(.rewards, "drop x=\(String(format: "%.3f", x)) reach=\(String(format: "%.3f", reach)) \(result) tokens=\(rewards.tokens) missStreak=\(rewards.missStreak)")
        saveRewards()
        return drop
    }

    private func saveRewards() {
        do {
            try rewards.save(to: rewardsURL)
        } catch {
            Log.error(.storage, "rewards save failed: \(error)")
        }
    }

    // MARK: - Math

    func mathSessionFacts() -> [MathFact] {
        let skill = MathPlanner.currentSkill(mathProgress)
        let facts = MathPlanner.sessionFacts(mathProgress)
        Log.info(.math, "session skill=\(skill.rawValue) mastered=\(Int(mathProgress.masteredFraction(of: skill) * 100))% facts: " + facts.map { "\($0.id)(box \(mathProgress[$0].box))" }.joined(separator: " "))
        return facts
    }

    func recordMath(_ fact: MathFact, outcome: WordProgress.Outcome) {
        var progress = mathProgress[fact]
        let before = progress.box
        progress.record(outcome)
        mathProgress[fact] = progress
        Log.info(.math, "fact \(fact.id) \(outcome.rawValue) box \(before)->\(progress.box)")
        do {
            try mathProgress.save(to: mathProgressURL)
        } catch {
            Log.error(.storage, "math progress save failed: \(error)")
        }
    }

    // MARK: - Resetting progress

    /// Starts a subject over from Settings › Progress. The old file is copied to `Progress/Backups/` first,
    /// so a reset by mistake can be undone by hand. Tokens and won toys are kept.
    func resetProgress(_ subject: Subject) {
        switch subject {
        case .reading:
            readingProgress = ReadingProgress()
            replace(readingProgress, at: readingProgressURL)
        case .writing:
            writingProgress = WritingProgress()
            replace(writingProgress, at: writingProgressURL)
        case .spelling:
            spellingProgress = SpellingProgress()
            replace(spellingProgress, at: spellingProgressURL)
        case .math:
            mathProgress = MathProgress()
            replace(mathProgress, at: mathProgressURL)
        case .logic:
            puzzleProgress = PuzzleProgress()
            replace(puzzleProgress, at: puzzleProgressURL)
        case .mixed:
            return
        }
        Log.info(.app, "grown-up reset \(subject.rawValue) progress")
    }

    func resetAllProgress() {
        for subject in Subject.allCases { resetProgress(subject) }
    }

    /// Starts handwriting calibration over. Every confirmed sample counts toward calibration (copied,
    /// tested or accepted in practice), so all of them go; a copy is kept in `Backups/` first.
    func resetCalibration() {
        do {
            try backUp(store.fileURL)
        } catch {
            Log.error(.storage, "samples backup failed, not resetting calibration: \(error)")
            return
        }
        Log.info(.app, "grown-up reset calibration")
        deleteAllSamples()
    }

    private func replace(_ file: some JSONFile, at url: URL) {
        do {
            try backUp(url)
            try file.save(to: url)
        } catch {
            Log.error(.storage, "reset of \(url.lastPathComponent) failed: \(error)")
        }
    }

    /// Copies a file to a `Backups` folder beside it, named with the time, before a reset replaces it.
    private func backUp(_ url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else { return }
        let backups = url.deletingLastPathComponent().appendingPathComponent("Backups")
        try manager.createDirectory(at: backups, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(url.deletingPathExtension().lastPathComponent)-\(formatter.string(from: Date())).json"
        try manager.copyItem(at: url, to: backups.appendingPathComponent(name))
        Log.info(.storage, "backed up \(url.lastPathComponent) to Backups/\(name)")
    }

    // MARK: - Puzzles

    /// The puzzles for one session. `-puzzle grid:3` at launch gives a session of one kind at one level
    /// (for screenshots and testing).
    func puzzleSession() -> [Puzzle] {
        var rng = SystemRandomNumberGenerator()
        let puzzles: [Puzzle]
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-puzzle"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ":")
            let kind = PuzzleKind(rawValue: String(parts[0])) ?? .next
            let level = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            puzzles = (0..<6).map { _ in PuzzleMaker.make(kind, level: level, seed: rng.next()) }
        } else {
            puzzles = PuzzlePlanner.session(puzzleProgress, using: &rng)
            puzzleProgress.sessions += 1
            savePuzzleProgress()
        }
        let levels = PuzzleKind.allCases.map { "\($0.rawValue)=L\(puzzleProgress[$0].level)" }.joined(separator: " ")
        Log.info(.puzzles, "session \(levels) kinds: " + puzzles.map(\.kind.rawValue).joined(separator: " "))
        return puzzles
    }

    func recordPuzzle(_ puzzle: Puzzle, outcome: WordProgress.Outcome, wrongPicks: Int) {
        var skill = puzzleProgress[puzzle.kind]
        let before = skill.level
        skill.record(outcome, maxLevel: puzzle.kind.maxLevel)
        puzzleProgress[puzzle.kind] = skill
        Log.info(.puzzles, "solved \(puzzle.kind.rawValue) seed=\(puzzle.seed) \(outcome.rawValue) wrong=\(wrongPicks) level \(before)->\(skill.level) streak=\(skill.streak) misses=\(skill.misses)")
        savePuzzleProgress()
    }

    private func savePuzzleProgress() {
        do {
            try puzzleProgress.save(to: puzzleProgressURL)
        } catch {
            Log.error(.storage, "puzzle progress save failed: \(error)")
        }
    }

    // MARK: - Reading

    func readingSessionCards() -> [ReadingCard] {
        let cards = ReadingPlanner.sessionCards(from: StarterReading.cards, progress: readingProgress)
        Log.info(.reading, "session cards: " + cards.map { "\($0.text)(box \(readingProgress[$0].box))" }.joined(separator: " "))
        return cards
    }

    func recordReading(_ card: ReadingCard, outcome: WordProgress.Outcome, how: String) {
        var progress = readingProgress[card]
        let before = progress.box
        progress.record(outcome)
        readingProgress[card] = progress
        Log.info(.reading, "card \"\(card.text)\" \(outcome.rawValue) via \(how) box \(before)->\(progress.box)")
        do {
            try readingProgress.save(to: readingProgressURL)
        } catch {
            Log.error(.storage, "reading progress save failed: \(error)")
        }
    }

    // MARK: - Calibration status

    /// Active characters with fewer calibration samples than asked for in Settings.
    var charactersNeedingCalibration: [String] {
        calibrationPlan.charactersNeedingSamples(given: samples)
    }

    // MARK: - Self-check

    /// Launch with `-recognizerSelfCheck` to score every recognizer on the saved samples and log
    /// the results; the personal recognizer is scored leave-one-out so it never sees the sample itself.
    func runSelfCheck() async {
        let candidates = Set(characters)
        let labeled = samples.filter { $0.confirmedLabel != nil }
        Log.info(.recognition, "self-check start samples=\(labeled.count) candidates=\(candidates.count)")

        let personal = Evaluation.leaveOneOut(samples: labeled, among: candidates)
        for result in personal {
            Log.info(.recognition, "self-check pdollar truth=\(result.truth) guess=\(result.guess ?? "-")")
        }
        Log.info(.recognition, "self-check pdollar \(personal.filter(\.isCorrect).count)/\(personal.count)")

        var others: [any CharacterRecognizer] = [vision]
        if let coreML { others.append(coreML) }
        for recognizer in others {
            var correct = 0
            for sample in labeled {
                let found = await recognizer.recognize(sample.ink, among: candidates)
                if found.first?.label == sample.confirmedLabel { correct += 1 }
                Log.info(.recognition, "self-check \(recognizer.id) truth=\(sample.confirmedLabel!) -> \(found.logDescription)")
            }
            Log.info(.recognition, "self-check \(recognizer.id) \(correct)/\(labeled.count)")
        }
        Log.info(.recognition, "self-check done")
        Log.file.flush()
    }

    // MARK: - Settings

    private static func loadSettings() -> Phase0Settings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(Phase0Settings.self, from: data) else { return Phase0Settings() }
        return settings
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}
