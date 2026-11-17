import SwiftUI
import KidTutorKit

/// A puzzles session: what comes next, odd one out, finish the grid and who am I, taking turns.
/// Every puzzle has one answer, so tapping a tile is the answer: no Check button. A wrong pick fades and the child tries again;
/// each Help says a hint and takes away a wrong choice, so every puzzle ends on a success.
struct PuzzleView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var puzzles: [Puzzle] = []
    @State private var index = 0
    @State private var picked: Int?
    /// Wrong picks and choices Help took away.
    @State private var removed: Set<Int> = []
    @State private var wrongPicks = 0
    @State private var helpPresses = 0
    @State private var hintLine: GridLine?
    @State private var speakingClue: Int?
    /// Why the last pick was wrong, lit up until the next pick or Help.
    @State private var cue: WrongCue?
    /// Who am I: bumped for a clue each time a wrong pick breaks it, to shake its chip. Never reset:
    /// a whole number of shakes leaves the chip where it started.
    @State private var shakes: [Int: Int] = [:]
    /// Who am I: clues a wrong pick broke; the tiles they rule out stay faded.
    @State private var brokenClues: Set<Int> = []
    @State private var solved = false
    @State private var sessionDone = false
    @State private var tokensEarned = 0
    @State private var advanceTask: Task<Void, Never>?

    private var puzzle: Puzzle? { puzzles.indices.contains(index) ? puzzles[index] : nil }

    var body: some View {
        VStack(spacing: 28) {
            if sessionDone {
                SessionFinishedView(message: "You solved \(puzzles.count) puzzles!", tokens: tokensEarned) { dismiss() }
            } else if let puzzle {
                ExerciseTopBar(
                    count: puzzles.count,
                    index: index,
                    currentDone: solved,
                    helpDisabled: solved || puzzle.wrongChoices.allSatisfy(removed.contains),
                    onReplay: { sayIntro(puzzle) },
                    onHelp: { giveHelp(puzzle) }
                )
                Text(puzzle.kind.question)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                if case .clues(let clues) = puzzle.board {
                    HStack(spacing: 24) {
                        ForEach(clues.indices, id: \.self) { i in
                            ClueChip(clue: clues[i], speaking: speakingClue == i, broken: cue?.clue == i, shakes: shakes[i, default: 0]) {
                                speakingClue = nil
                                model.speaker.say(clues[i].spoken)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                board(puzzle)
                    .id(index)
                Spacer(minLength: 0)
            } else {
                ProgressView()
            }
        }
        .padding(32)
        .animation(.easeInOut(duration: 0.3), value: removed)
        .animation(.easeInOut(duration: 0.3), value: hintLine)
        .animation(.easeInOut(duration: 0.3), value: cue)
        .animation(.easeInOut(duration: 0.5), value: brokenClues)
        .onAppear(perform: startSession)
        .onDisappear { advanceTask?.cancel() }
    }

    // MARK: - Boards

    @ViewBuilder
    private func board(_ puzzle: Puzzle) -> some View {
        let counting = puzzle.varying.contains(.count)
        switch puzzle.board {
        case .row(let row, _):
            VStack(spacing: 56) {
                GeometryReader { geo in
                    let n = CGFloat(row.count + 1)
                    let size = min(150, (geo.size.width - 16 * (n - 1)) / n)
                    HStack(spacing: 16) {
                        ForEach(row.indices, id: \.self) { i in
                            TileCard(tile: row[i], size: size, counting: counting)
                        }
                        GapCard(ghost: picked.map { puzzle.choices[$0] }, solid: solved, size: size, counting: counting)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.map(puzzle.name(of:)).joined(separator: ", ") + ", then a gap")
                tray(puzzle, size: 170, columns: puzzle.choices.count)
            }
        case .group:
            HStack(spacing: 36) {
                ForEach(puzzle.choices.indices, id: \.self) { choiceButton(puzzle, $0, size: 210) }
            }
        case .grid(let cells, let columns, _):
            let size: CGFloat = columns == 2 ? 180 : 150
            let gap = cells.firstIndex(of: nil) ?? 0
            HStack(spacing: 56) {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    ForEach(0..<(cells.count / columns), id: \.self) { r in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { c in
                                let i = r * columns + c
                                let inRow = r == gap / columns, inColumn = c == gap % columns
                                // A wrong pick lights the line it doesn't fit in orange; Help lights its line in blue.
                                let missed = (inRow && cue?.lines.contains(.row) == true) || (inColumn && cue?.lines.contains(.column) == true)
                                let hinted = (inRow && hintLine == .row) || (inColumn && hintLine == .column)
                                if let tile = cells[i] {
                                    TileCard(tile: tile, size: size, counting: counting, lit: missed ? .orange : hinted ? .blue : nil)
                                } else {
                                    GapCard(ghost: picked.map { puzzle.choices[$0] }, solid: solved, size: size, counting: counting)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("A grid with a gap")
                tray(puzzle, size: 150, columns: 2)
            }
        case .clues:
            let columns = puzzle.choices.count == 6 ? 3 : 4
            let size: CGFloat = puzzle.choices.count == 8 ? 180 : 200
            Grid(horizontalSpacing: 28, verticalSpacing: 28) {
                ForEach(0..<(puzzle.choices.count / columns), id: \.self) { r in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in choiceButton(puzzle, r * columns + c, size: size) }
                    }
                }
            }
        }
    }

    /// The choices to pick from, on a gray tray.
    private func tray(_ puzzle: Puzzle, size: CGFloat, columns: Int) -> some View {
        Grid(horizontalSpacing: 32, verticalSpacing: 28) {
            ForEach(0..<((puzzle.choices.count + columns - 1) / columns), id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        let i = r * columns + c
                        if i < puzzle.choices.count { choiceButton(puzzle, i, size: size) }
                    }
                }
            }
        }
        .padding(28)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func choiceButton(_ puzzle: Puzzle, _ i: Int, size: CGFloat) -> some View {
        let gone = removed.contains(i)
        let ruledOut = fadedByClues(puzzle, i)
        let marked = (solved && i == puzzle.answer) || picked == i
        return Button {
            pick(puzzle, i)
        } label: {
            TileCard(
                tile: puzzle.choices[i],
                size: size,
                counting: puzzle.varying.contains(.count),
                lit: cue?.together.contains(i) == true ? .blue : nil,
                border: marked ? (solved ? .green : .yellow) : .secondary.opacity(0.35),
                borderWidth: marked ? 7 : 3
            )
        }
        .buttonStyle(.plain)
        .disabled(gone)
        .opacity(gone ? 0.12 : ruledOut ? 0.3 : 1)
        .accessibilityLabel(puzzle.name(of: puzzle.choices[i]))
    }

    /// Who am I: tiles ruled out by a clue a wrong pick broke.
    private func fadedByClues(_ puzzle: Puzzle, _ i: Int) -> Bool {
        guard case .clues = puzzle.board, let clue = puzzle.clueRulingOut(i) else { return false }
        return brokenClues.contains(clue)
    }

    // MARK: - Flow

    private func startSession() {
        guard puzzles.isEmpty else { return }
        puzzles = model.puzzleSession()
        index = 0
        if puzzles.isEmpty {
            sessionDone = true
            return
        }
        startPuzzle()
    }

    private func startPuzzle() {
        guard let puzzle else { return }
        picked = nil
        removed = []
        wrongPicks = 0
        helpPresses = 0
        hintLine = nil
        cue = nil
        brokenClues = []
        speakingClue = nil
        solved = false
        Log.info(.puzzles, "puzzle \(index + 1)/\(puzzles.count) \(puzzle.logDescription)")
        if !PuzzleSolver.isFair(puzzle) {
            Log.error(.puzzles, "solver found \(PuzzleSolver.solutions(puzzle)) instead of only \(puzzle.answer): PuzzleMaker gave up after \(PuzzleMaker.maxTries) tries")
        }
        sayIntro(puzzle)
    }

    private func sayIntro(_ puzzle: Puzzle) {
        guard case .clues(let clues) = puzzle.board else {
            model.speaker.say(puzzle.intro.joined(separator: " "))
            return
        }
        model.speaker.say(
            parts: puzzle.intro,
            onStart: { part in
                let clue = part - Puzzle.firstCluePart
                speakingClue = clues.indices.contains(clue) ? clue : nil
            },
            onFinish: { part in
                let clue = part - Puzzle.firstCluePart
                guard clues.indices.contains(clue) else { return }
                speakingClue = nil
            }
        )
    }

    /// A tap is the child's answer. What's said next names the tile either way ("Yes! … blue square!",
    /// "The small blue square isn't red…"), so the tap itself says nothing.
    private func pick(_ puzzle: Puzzle, _ choice: Int) {
        guard !solved, !removed.contains(choice) else { return }
        speakingClue = nil
        picked = choice
        cue = nil
        if choice == puzzle.answer {
            solved = true
            let outcome: WordProgress.Outcome = helpPresses > 0 ? .hinted : wrongPicks > 0 ? .retried : .firstTry
            model.recordPuzzle(puzzle, outcome: outcome, wrongPicks: wrongPicks)
            model.speaker.say(puzzle.praise)
            advance(after: puzzle.praise)
        } else {
            Log.info(.puzzles, "wrong pick \(puzzle.name(of: puzzle.choices[choice]))")
            wrongPicks += 1
            removed.insert(choice)
            picked = nil
            hintLine = nil
            let cue = puzzle.wrongCue(choice)
            self.cue = cue
            if let clue = cue.clue {
                brokenClues.insert(clue)
                withAnimation(.linear(duration: 0.5)) { shakes[clue, default: 0] += 1 }
            }
            if !cue.together.isEmpty {
                // Odd one out: only a glimpse of the three that go together, or it gives the answer away.
                let shown = cue
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if self.cue == shown { self.cue = nil }
                }
            }
            model.speaker.say(puzzle.wrong(choice))
        }
    }

    private func giveHelp(_ puzzle: Puzzle) {
        speakingClue = nil
        let hint = puzzle.hint(press: helpPresses)
        helpPresses += 1
        hintLine = hint.line
        cue = nil
        if let take = puzzle.wrongChoices.first(where: { !removed.contains($0) }) {
            removed.insert(take)
            if picked == take { picked = nil }
        }
        Log.info(.puzzles, "help \(helpPresses) \"\(hint.text)\"")
        model.speaker.say(hint.text)
    }

    /// Moves on once the praise has had time to be said (about 0.4 s a word).
    private func advance(after praise: String) {
        let words = praise.split(separator: " ").count
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(max(2.5, Double(words) * 0.4 + 1)))
            guard !Task.isCancelled else { return }
            if index + 1 < puzzles.count {
                index += 1
                startPuzzle()
            } else {
                sessionDone = true
                tokensEarned = model.awardSessionTokens(.logic)
                Log.info(.puzzles, "session done puzzles=\(puzzles.count)")
                model.speaker.say("Great job! You solved \(puzzles.count) puzzles.\(TokenText.earned(tokensEarned))")
            }
        }
    }
}

// MARK: - Tiles

extension TileColor {
    var swiftUI: Color {
        switch self {
        case .red: Color(red: 0.878, green: 0.325, blue: 0.239)
        case .blue: Color(red: 0.231, green: 0.510, blue: 0.769)
        case .yellow: Color(red: 0.949, green: 0.718, blue: 0.020)
        case .green: Color(red: 0.180, green: 0.620, blue: 0.357)
        }
    }
}

/// The outline of a tile's shape, to fill or stroke.
struct TileOutline: Shape {
    var shape: TileShape

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.addLines(points.map { point($0.0, $0.1) })
            path.closeSubpath()
            return path
        }
        switch shape {
        case .circle:
            return Circle().path(in: rect)
        case .square:
            let inset = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
            return RoundedRectangle(cornerRadius: inset.width * 0.12).path(in: inset)
        case .triangle:
            return polygon([(0.5, 0.04), (0.98, 0.92), (0.02, 0.92)])
        case .star:
            return polygon([(0.5, 0.02), (0.62, 0.37), (0.98, 0.37), (0.69, 0.59), (0.8, 0.95),
                            (0.5, 0.73), (0.2, 0.95), (0.31, 0.59), (0.02, 0.37), (0.38, 0.37)])
        }
    }
}

/// The picture on a tile: one shape sized big or small, or for counting puzzles, `count` small shapes.
struct TileArt: View {
    var tile: Tile
    var size: CGFloat
    var counting = false

    var body: some View {
        if counting {
            let item = size * 0.24
            let perRow = tile.count == 4 ? 2 : 3
            VStack(spacing: size * 0.05) {
                ForEach(0..<((tile.count + perRow - 1) / perRow), id: \.self) { r in
                    HStack(spacing: size * 0.05) {
                        ForEach(0..<min(perRow, tile.count - r * perRow), id: \.self) { _ in
                            TileOutline(shape: tile.shape).fill(tile.color.swiftUI).frame(width: item, height: item)
                        }
                    }
                }
            }
        } else {
            let side = size * (tile.size == .big ? 0.66 : 0.23)
            TileOutline(shape: tile.shape).fill(tile.color.swiftUI).frame(width: side, height: side)
        }
    }
}

/// A tile on a rounded card. `lit` marks tiles to look at: a grid line a hint or a wrong pick points at,
/// or the odd-one-out tiles that go together.
struct TileCard: View {
    var tile: Tile
    var size: CGFloat
    var counting = false
    var lit: Color?
    var border: Color = .secondary.opacity(0.35)
    var borderWidth: CGFloat = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
        TileArt(tile: tile, size: size, counting: counting)
            .frame(width: size, height: size)
            .background(lit?.opacity(0.14) ?? Color(.systemBackground), in: shape)
            .overlay(shape.strokeBorder(lit ?? border, lineWidth: lit == nil ? borderWidth : 6))
            .contentShape(shape)
    }
}

/// The empty spot to fill: a dashed yellow card with a question mark, or the picked tile shown faintly.
struct GapCard: View {
    var ghost: Tile?
    /// Solved: show the tile fully.
    var solid = false
    var size: CGFloat
    var counting = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
        ZStack {
            if let ghost {
                TileArt(tile: ghost, size: size, counting: counting).opacity(solid ? 1 : 0.45)
            } else {
                Text("?")
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.orange)
            }
        }
        .frame(width: size, height: size)
        .background(Color.yellow.opacity(0.15), in: shape)
        .overlay(shape.strokeBorder(Color.yellow, style: StrokeStyle(lineWidth: 5, dash: [14, 9])))
        .accessibilityLabel("Gap")
    }
}

/// A "who am I?" clue as a picture that can't be mistaken for a tile: a paint drop for a color, the shape in
/// gray for a shape, a mouse or an elephant for a size; under a "no" sign for "not". The clue's words sit below.
struct ClueChip: View {
    var clue: Clue
    var speaking: Bool
    /// The clue the last wrong pick broke: outlined in orange, with a shake.
    var broken = false
    var shakes = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            picture
                .overlay {
                    if clue.isNot {
                        // A "no" sign: a dark ring with a slash, outlined in white so it shows on any color.
                        ZStack {
                            Circle().stroke(Color(.systemBackground), lineWidth: 12).frame(width: 90, height: 90)
                            Circle().stroke(Color.primary, lineWidth: 7).frame(width: 90, height: 90)
                            Capsule().fill(Color(.systemBackground)).frame(width: 90, height: 13).rotationEffect(.degrees(-45))
                            Capsule().fill(Color.primary).frame(width: 86, height: 7).rotationEffect(.degrees(-45))
                        }
                    }
                }
                .padding(.horizontal, 30)
                .frame(minWidth: 130, minHeight: 116)
                .background(broken ? Color.orange.opacity(0.15) : Color(.systemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(outline, lineWidth: speaking || broken ? 6 : 3))
                .contentShape(Capsule())
                .overlay(alignment: .bottom) {
                    // The clue in words too, so a grown-up (or an early reader) can follow without the sound.
                    Text(clue.short)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(broken ? Color.orange : Color.secondary)
                        .fixedSize()
                        .offset(y: 34)
                }
                .modifier(Shake(phase: CGFloat(shakes)))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 34)
        .accessibilityLabel(clue.spoken)
    }

    private var outline: Color {
        broken ? .orange : speaking ? .blue : .secondary.opacity(0.35)
    }

    @ViewBuilder
    private var picture: some View {
        switch clue.value {
        case .color(let color):
            // A drop of paint: the color, with no shape a tile could have.
            Image(systemName: "drop.fill")
                .font(.system(size: 54))
                .foregroundStyle(color.swiftUI)
                .frame(width: 60, height: 60)
        case .shape(let shape):
            // The shape in gray, a color no tile has: this shape, any color.
            TileOutline(shape: shape)
                .fill(Color.gray)
                .frame(width: 60, height: 60)
        case .size(let size):
            // A mouse for small, an elephant for big: no shape or color to mix up with the tiles.
            Text(size == .small ? "🐭" : "🐘")
                .font(.system(size: 50))
                .frame(width: 60, height: 60)
        }
    }
}

/// A side-to-side wiggle each time `phase` goes up by one.
struct Shake: GeometryEffect {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 12 * sin(phase * .pi * 6), y: 0))
    }
}
