import Foundation

// MARK: - Tiles

/// Puzzles are built from picture tiles that differ in a few things a child can see and name.
public enum TileShape: String, CaseIterable, Codable, Sendable {
    case circle, square, triangle, star
}

public enum TileColor: String, CaseIterable, Codable, Sendable {
    case red, blue, yellow, green
}

public enum TileSize: String, CaseIterable, Codable, Sendable {
    case small, big

    var other: TileSize { self == .small ? .big : .small }
}

public enum TileFeature: String, CaseIterable, Codable, Sendable {
    case shape, color, size, count

    /// "Look at the shapes."
    var plural: String {
        switch self {
        case .shape: "shapes"
        case .color: "colors"
        case .size: "sizes"
        case .count: "numbers"
        }
    }
}

/// One tile: a shape (or a few of them, for counting), in one color and size.
public struct Tile: Hashable, Codable, Sendable {
    public var shape: TileShape
    public var color: TileColor
    public var size: TileSize
    /// How many shapes are drawn on the tile (growing patterns, counting grids).
    public var count: Int

    public init(_ shape: TileShape, _ color: TileColor, _ size: TileSize = .big, count: Int = 1) {
        self.shape = shape
        self.color = color
        self.size = size
        self.count = count
    }

    /// Every one-shape tile.
    public static let all: [Tile] = TileShape.allCases.flatMap { shape in
        TileColor.allCases.flatMap { color in TileSize.allCases.map { Tile(shape, color, $0) } }
    }

    public func value(_ feature: TileFeature) -> String {
        switch feature {
        case .shape: shape.rawValue
        case .color: color.rawValue
        case .size: size.rawValue
        case .count: String(count)
        }
    }

    /// What the app calls the tile, saying only `features`: "big blue square", "three red stars",
    /// "red" (color only), "three" (count only).
    public func name(showing features: Set<TileFeature>, plural: Bool = false) -> String {
        var words: [String] = []
        if features.contains(.count) { words.append(Spoken.number(count)) }
        if features.contains(.size) { words.append(size.rawValue) }
        if features.contains(.color) { words.append(color.rawValue) }
        if features.contains(.shape) || words.isEmpty {
            words.append(plural || count > 1 ? shape.rawValue + "s" : shape.rawValue)
        }
        return words.joined(separator: " ")
    }

    /// How `features` read after "That's" or "is": "a triangle", "a red triangle", "yellow", "three".
    func phrase(_ features: Set<TileFeature>) -> String {
        let name = name(showing: features)
        return features.contains(.shape) && !features.contains(.count) ? "a " + name : name
    }
}

/// Words the app says.
enum Spoken {
    static func number(_ n: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(n) ? words[n] : String(n)
    }

    /// "a", "a and b", "a, b, and c"
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + ", and " + items.last!
        }
    }

    /// Capitalizes the first letter.
    static func sentence(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

// MARK: - Puzzles

public enum PuzzleKind: String, CaseIterable, Codable, Sendable {
    case next, oddOneOut, grid, whoAmI

    public var maxLevel: Int {
        switch self {
        case .next: 5
        case .oddOneOut: 4
        case .grid: 5
        case .whoAmI: 4
        }
    }

    /// The kind's name, for grown-ups.
    public var title: String {
        switch self {
        case .next: "What comes next"
        case .oddOneOut: "Odd one out"
        case .grid: "Finish the grid"
        case .whoAmI: "Who am I"
        }
    }

    /// The question at the top of the screen.
    public var question: String {
        switch self {
        case .next: "What comes next?"
        case .oddOneOut: "Which one doesn't belong?"
        case .grid: "Which one fills the gap?"
        case .whoAmI: "Who am I?"
        }
    }
}

/// A "who am I?" clue: "I'm not red."
public struct Clue: Hashable, Sendable {
    public enum Value: Hashable, Sendable {
        case shape(TileShape), color(TileColor), size(TileSize)
    }

    public var value: Value
    public var isNot: Bool

    public init(_ value: Value, isNot: Bool = false) {
        self.value = value
        self.isNot = isNot
    }

    public var feature: TileFeature {
        switch value {
        case .shape: .shape
        case .color: .color
        case .size: .size
        }
    }

    public func fits(_ tile: Tile) -> Bool {
        let matches = switch value {
        case .shape(let shape): tile.shape == shape
        case .color(let color): tile.color == color
        case .size(let size): tile.size == size
        }
        return matches != isNot
    }

    /// "a circle", "red", "big"
    private var words: String {
        switch value {
        case .shape(let shape): "a \(shape.rawValue)"
        case .color(let color): color.rawValue
        case .size(let size): size.rawValue
        }
    }

    /// "I'm not red."
    public var spoken: String { "I'm \(isNot ? "not " : "")\(words)." }
    /// "not red", for the praise that lists every clue.
    public var short: String { isNot ? "not \(words)" : words }
    /// "isn't red", about a tile the child picked.
    var about: String { (isNot ? "isn't " : "is ") + words }
}

/// Which line of a grid a hint points at.
public enum GridLine: Sendable {
    case row, column
}

/// What to show after a wrong pick, so the reason can be seen as well as heard.
public struct WrongCue: Equatable, Sendable {
    /// Who am I: the clue the pick breaks.
    public var clue: Int?
    /// Finish the grid: the lines through the gap the pick doesn't fit.
    public var lines: [GridLine] = []
    /// Odd one out: the tiles that go together.
    public var together: [Int] = []
}

public struct PuzzleHint: Equatable, Sendable {
    public var text: String
    /// Finish the grid: the line through the gap to light up.
    public var line: GridLine?
}

/// One puzzle: what's on the board, the tiles to choose from, and which one is right.
/// Made from a kind, a level and a seed, so the log can recreate any puzzle the child saw.
public struct Puzzle: Hashable, Sendable {
    public enum Pattern: Hashable, Sendable {
        /// The tiles that repeat: AB, AAB, ABC.
        case repeating([Tile])
        /// Colors and shapes repeat on their own beats.
        case twoBeats(colors: [TileColor], shapes: [TileShape])
        /// One more each time.
        case growing
    }

    /// Finish the grid: each row shares `rows`, each column shares `columns`.
    /// Both empty means the rows repeat.
    public struct GridRule: Hashable, Sendable {
        public var rows: Set<TileFeature>
        public var columns: Set<TileFeature>

        public var rowsRepeat: Bool { rows.isEmpty && columns.isEmpty }
    }

    public enum Board: Hashable, Sendable {
        /// What comes next: the row before the gap.
        case row([Tile], Pattern)
        /// Odd one out: the choices are the puzzle; the odd one differs in `odd`.
        case group(odd: TileFeature)
        /// Finish the grid: cells row by row, nil at the gap.
        case grid([Tile?], columns: Int, rule: GridRule)
        /// Who am I: the clues in the order they're said.
        case clues([Clue])
    }

    public var kind: PuzzleKind
    public var level: Int
    public var seed: UInt64
    public var board: Board
    public var choices: [Tile]
    public var answer: Int

    public var answerTile: Tile { choices[answer] }

    /// Features that differ somewhere in the puzzle.
    public var varying: Set<TileFeature> {
        var tiles = choices
        switch board {
        case .row(let row, _): tiles += row
        case .grid(let cells, _, _): tiles += cells.compactMap { $0 }
        default: break
        }
        return Set(TileFeature.allCases.filter { f in Set(tiles.map { $0.value(f) }).count > 1 })
    }

    /// "big blue square": shape and color always, size and count when they matter.
    public func name(of tile: Tile) -> String {
        tile.name(showing: Set([.shape, .color]).union(varying.intersection([.size, .count])))
    }

    /// Wrong choices, in the order Help takes them away.
    public var wrongChoices: [Int] { choices.indices.filter { $0 != answer } }

    /// Who am I: the first clue `choice` doesn't fit.
    public func clueRulingOut(_ choice: Int) -> Int? {
        guard case .clues(let clues) = board else { return nil }
        return clues.firstIndex { !$0.fits(choices[choice]) }
    }

    /// Odd one out: every tile that alone differs from the other three in something.
    /// A good puzzle has exactly one.
    public static func oddOnes(_ tiles: [Tile]) -> [Int] {
        tiles.indices.filter { i in
            TileFeature.allCases.contains { f in
                let others = Set(tiles.indices.filter { $0 != i }.map { tiles[$0].value(f) })
                return others.count == 1 && others.first != tiles[i].value(f)
            }
        }
    }

    // MARK: Speech

    /// Said when the puzzle appears, in parts (who am I says one clue per part).
    public var intro: [String] {
        switch board {
        case .row(let row, _):
            ["What comes next? \(Spoken.sentence(rhythm(row)))… Tap the one that comes next."]
        case .group:
            ["Three of these go together. Which one doesn't belong?"]
        case .grid(_, _, let rule):
            [rule.rowsRepeat ? "Look at the top row. Which one fills the gap?" : "Look at each row and each column. Which one fills the gap?"]
        case .clues(let clues):
            ["Listen to my clues and find me!"] + clues.map(\.spoken) + ["Who am I?"]
        }
    }

    /// Who am I: the intro part that says the first clue.
    public static let firstCluePart = 1

    /// Said for a right answer: the rule, said back.
    public var praise: String {
        let name = name(of: answerTile)
        switch board {
        case .row(let row, _):
            return "Yes! \(Spoken.sentence(rhythm(row)))… \(answerTile.name(showing: rhythmFeatures))!"
        case .group(let odd):
            let other = choices[wrongChoices[0]]
            let oddName = odd == .shape ? answerTile.shape.rawValue : "\(answerTile.value(odd)) one"
            return "Yes! The others are all \(other.name(showing: [odd], plural: true)). The \(oddName) doesn't belong."
        case .grid(_, _, let rule):
            if rule.rowsRepeat { return "Yes! The rows match. It's the \(name)!" }
            let row = ruleSentence(.row, rule.rows)
            let column = ruleSentence(.column, rule.columns)
            return "Yes! \(row), and \(column.prefix(1).lowercased() + column.dropFirst()). It's the \(name)!"
        case .clues(let clues):
            return "You found me! \(Spoken.sentence(Spoken.list(clues.map(\.short)))). The \(name)!"
        }
    }

    /// Said for a wrong answer: what the picked tile got right, and where to look.
    public func wrong(_ choice: Int) -> String {
        let picked = choices[choice]
        switch board {
        case .row(let row, _):
            return "Not quite. Listen: \(Spoken.sentence(rhythm(row)))…"
        case .group(let odd):
            return "Hmm, the \(name(of: picked)) is \(picked.phrase([odd])) like the others. Try another."
        case .grid(_, _, let rule):
            if rule.rowsRepeat { return "Not quite. Look at the top row. The bottom row is the same." }
            let rowRight = rule.rows.allSatisfy { picked.value($0) == answerTile.value($0) }
            let columnRight = rule.columns.allSatisfy { picked.value($0) == answerTile.value($0) }
            switch (rowRight, columnRight) {
            case (true, false):
                return "That's \(picked.phrase(rule.rows)), good! But look down this column. \(question(rule.columns))"
            case (false, true):
                return "That's \(picked.phrase(rule.columns)), good! But look along this row. \(question(rule.rows))"
            default:
                return "Not quite. Look along this row, and down this column."
            }
        case .clues(let clues):
            let name = name(of: picked)
            guard let failed = clues.first(where: { !$0.fits(picked) }) else { return "Try another." }
            let clue = failed.spoken.dropLast()
            let fits = clues.filter { $0.fits(picked) }.map(\.about)
            if fits.isEmpty { return "Not the \(name). Listen: \(clue)!" }
            return "The \(name) \(Spoken.list(fits))… but \(clue)!"
        }
    }

    /// What to light up after a wrong pick.
    public func wrongCue(_ choice: Int) -> WrongCue {
        let picked = choices[choice]
        switch board {
        case .row:
            return WrongCue()
        case .group:
            return WrongCue(together: wrongChoices)
        case .grid(_, _, let rule):
            if rule.rowsRepeat { return WrongCue(lines: [.row]) }
            var lines: [GridLine] = []
            if !rule.rows.allSatisfy({ picked.value($0) == answerTile.value($0) }) { lines.append(.row) }
            if !rule.columns.allSatisfy({ picked.value($0) == answerTile.value($0) }) { lines.append(.column) }
            return WrongCue(lines: lines)
        case .clues:
            return WrongCue(clue: clueRulingOut(choice))
        }
    }

    /// Said when Help is pressed; `press` counts from 0. Each press also takes away a wrong choice.
    public func hint(press: Int) -> PuzzleHint {
        switch board {
        case .row(_, .repeating(let unit)):
            return PuzzleHint(text: "Listen: it goes \(rhythm(unit)), then starts again.")
        case .row(_, .twoBeats(let colors, let shapes)):
            return press % 2 == 0
                ? PuzzleHint(text: "Look at just the colors. \(Spoken.sentence((colors + colors).map(\.rawValue).joined(separator: ", ")))…")
                : PuzzleHint(text: "Now just the shapes. \(Spoken.sentence((shapes + shapes).map(\.rawValue).joined(separator: ", ")))…")
        case .row(_, .growing):
            return PuzzleHint(text: "Count them. Each one has one more.")
        case .group(let odd):
            return press == 0
                ? PuzzleHint(text: "Look at the \(odd.plural).")
                : PuzzleHint(text: "Three of them are \(choices[wrongChoices[0]].name(showing: [odd], plural: true)).")
        case .grid(_, _, let rule):
            if rule.rowsRepeat { return PuzzleHint(text: "Look at the top row. The bottom row is the same.", line: .row) }
            return press % 2 == 0
                ? PuzzleHint(text: ruleSentence(.row, rule.rows) + ".", line: .row)
                : PuzzleHint(text: ruleSentence(.column, rule.columns) + ".", line: .column)
        case .clues(let clues):
            return PuzzleHint(text: "Listen again. " + clues.map(\.spoken).joined(separator: " "))
        }
    }

    /// What comes next: only the features that change, so the beat is easy to hear.
    private var rhythmFeatures: Set<TileFeature> {
        varying.intersection([.shape, .color, .size, .count])
    }

    private func rhythm(_ tiles: [Tile]) -> String {
        tiles.map { $0.name(showing: rhythmFeatures) }.joined(separator: ", ")
    }

    /// "This row is all triangles", "Every one in this column has three"
    private func ruleSentence(_ line: GridLine, _ features: Set<TileFeature>) -> String {
        let lineName = line == .row ? "row" : "column"
        if features == [.count] {
            return "Every one in this \(lineName) has \(Spoken.number(answerTile.count))"
        }
        return "This \(lineName) is all \(answerTile.name(showing: features, plural: true))"
    }

    private func question(_ features: Set<TileFeature>) -> String {
        if features == [.color] { return "What color are they?" }
        if features == [.shape] { return "What shape are they?" }
        if features == [.count] { return "How many does each one have?" }
        return "What are they?"
    }

    public var logDescription: String {
        let board: String = switch self.board {
        case .row(let row, _): "row=[\(row.map(name(of:)).joined(separator: ", "))]"
        case .group(let odd): "odd=\(odd.rawValue)"
        case .grid(let cells, let columns, _): "grid\(columns)=[\(cells.map { $0.map(name(of:)) ?? "_" }.joined(separator: ", "))]"
        case .clues(let clues): "clues=[\(clues.map(\.short).joined(separator: ", "))]"
        }
        return "\(kind.rawValue) L\(level) seed=\(seed) \(board) choices=[\(choices.map(name(of:)).joined(separator: ", "))] answer=\(answer)"
    }
}

// MARK: - Making puzzles

/// Builds puzzles. Everything comes from the seed, so a puzzle in the log can be made again.
public enum PuzzleMaker {
    public static func make(_ kind: PuzzleKind, level: Int, seed: UInt64) -> Puzzle {
        let level = min(max(level, 1), kind.maxLevel)
        var rng = SeededRandom(seed: seed)
        var puzzle: Puzzle
        var tries = 0
        // Keep only a puzzle the solver, looking at just what the child sees, answers with the answer.
        // If every try fails the last one comes back anyway; the app logs it as an error, and the tests
        // check that never happens for any kind or level.
        repeat {
            let (board, answer, wrong) = switch kind {
            case .next: pattern(level, &rng)
            case .oddOneOut: oddOneOut(level, &rng)
            case .grid: grid(level, &rng)
            case .whoAmI: whoAmI(level, &rng)
            }
            let choices = ([answer] + wrong).enumerated().shuffled(using: &rng)
            puzzle = Puzzle(
                kind: kind,
                level: level,
                seed: seed,
                board: board,
                choices: choices.map(\.element),
                answer: choices.firstIndex { $0.offset == 0 }!
            )
            tries += 1
        } while !PuzzleSolver.isFair(puzzle) && tries < maxTries
        return puzzle
    }

    public static let maxTries = 50

    private typealias Parts = (Puzzle.Board, Tile, [Tile])

    /// Four tiles that differ from each other in both shape and color.
    private static func distinctTiles(_ rng: inout SeededRandom) -> [Tile] {
        let shapes = TileShape.allCases.shuffled(using: &rng)
        let colors = TileColor.allCases.shuffled(using: &rng)
        return (0..<4).map { Tile(shapes[$0], colors[$0]) }
    }

    /// Levels: AB, AAB or ABB, ABC, colors and shapes on separate beats, growing by one.
    private static func pattern(_ level: Int, _ rng: inout SeededRandom) -> Parts {
        let tiles = distinctTiles(&rng)
        switch level {
        case 1, 2, 3:
            let a = tiles[0], b = tiles[1], c = tiles[2]
            let unit = switch level {
            case 1: [a, b]
            case 2: Bool.random(using: &rng) ? [a, a, b] : [a, b, b]
            default: [a, b, c]
            }
            let shown = Int.random(in: level == 1 ? 4...5 : 5...7, using: &rng)
            let answer = unit[shown % unit.count]
            let others = [a, b, c].filter { unit.contains($0) && $0 != answer }
            return (.row((0..<shown).map { unit[$0 % unit.count] }, .repeating(unit)), answer, others + [tiles[3]])
        case 4:
            let colors = [tiles[0].color, tiles[1].color]
            let shapes = [tiles[0].shape, tiles[1].shape, tiles[2].shape]
            func tile(_ i: Int) -> Tile { Tile(shapes[i % 3], colors[i % 2]) }
            let shown = Int.random(in: 6...7, using: &rng)
            let answer = tile(shown)
            let wrong = [
                Tile(shapes[(shown + 1) % 3], answer.color),
                Tile(answer.shape, colors[(shown + 1) % 2]),
                tiles[3],
            ]
            return (.row((0..<shown).map(tile), .twoBeats(colors: colors, shapes: shapes)), answer, wrong)
        default:
            let base = tiles[0]
            let shown = Int.random(in: 3...4, using: &rng)
            func tile(_ n: Int) -> Tile { Tile(base.shape, base.color, count: n) }
            return (.row((1...shown).map(tile), .growing), tile(shown + 1), [tile(shown), tile(shown + 2)])
        }
    }

    /// Levels: three the same and one different; the other features vary too; size is the difference;
    /// any feature. When size is the difference the tiles are all one shape (four stars, one small),
    /// because a small square among a big circle, triangle and star looks like just another different tile.
    private static func oddOneOut(_ level: Int, _ rng: inout SeededRandom) -> Parts {
        let odd: TileFeature = switch level {
        case 1, 2: [.shape, .color].randomElement(using: &rng)!
        case 3: .size
        default: [.shape, .color, .size].randomElement(using: &rng)!
        }
        let shapes = TileShape.allCases.shuffled(using: &rng)
        let colors = TileColor.allCases.shuffled(using: &rng)
        var tiles: [Tile]
        if level == 1 {
            tiles = Array(repeating: Tile(shapes[0], colors[0]), count: 4)
        } else {
            // Shape and color are different on every tile (except shape, for size), so they can't single one out.
            let size = TileSize.allCases.randomElement(using: &rng)!
            tiles = (0..<4).map { Tile(odd == .size ? shapes[0] : shapes[$0], colors[$0], size) }
            for i in 0..<3 {
                switch odd {
                case .shape: tiles[i].shape = shapes[0]
                case .color: tiles[i].color = colors[0]
                default: break
                }
            }
        }
        switch odd {
        case .shape: tiles[3].shape = shapes[1]
        case .color: tiles[3].color = colors[1]
        default: tiles[3].size = tiles[0].size.other
        }
        return (.group(odd: odd), tiles[3], Array(tiles[0..<3]))
    }

    /// Levels: 2×2 where the rows repeat; 2×2 with a shape per row and a color per column; the same in 3×3;
    /// 3×3 where the count grows along each row; 3×3 with the gap anywhere.
    private static func grid(_ level: Int, _ rng: inout SeededRandom) -> Parts {
        let shapes = TileShape.allCases.shuffled(using: &rng)
        let colors = TileColor.allCases.shuffled(using: &rng)
        if level == 1 {
            let a = Tile(shapes[0], colors[0]), b = Tile(shapes[1], colors[1])
            let rule = Puzzle.GridRule(rows: [], columns: [])
            return (.grid([a, b, a, nil], columns: 2, rule: rule), b, [a, Tile(shapes[2], colors[2])])
        }
        let n = level == 2 ? 2 : 3
        let counting = level == 4 || (level == 5 && Bool.random(using: &rng))
        let rule = counting
            ? Puzzle.GridRule(rows: [.shape, .color], columns: [.count])
            : Puzzle.GridRule(rows: [.shape], columns: [.color])
        func cell(_ r: Int, _ c: Int) -> Tile {
            counting ? Tile(shapes[r], colors[r], count: c + 1) : Tile(shapes[r], colors[c])
        }
        let gap = level == 5 ? Int.random(in: 0..<(n * n), using: &rng) : n * n - 1
        let (row, column) = (gap / n, gap % n)
        var cells: [Tile?] = (0..<(n * n)).map { cell($0 / n, $0 % n) }
        cells[gap] = nil
        // One right along the row, one right down the column, one right in neither.
        let wrong = [
            cell(row, (column + 1) % n),
            cell((row + 1) % n, column),
            Tile(shapes[3], colors[3], count: counting ? column + 1 : 1),
        ]
        return (.grid(cells, columns: n, rule: rule), cell(row, column), wrong)
    }

    /// Levels: 4 tiles and 2 clues; 6 tiles and 3 clues; 8 tiles; 8 tiles, and size can be a "not".
    /// Every wrong tile breaks exactly one clue, so each clue rules something out and only one tile fits them all.
    private static func whoAmI(_ level: Int, _ rng: inout SeededRandom) -> Parts {
        let tileCount = [4, 6, 8, 8][level - 1]
        let features = Array([TileFeature.shape, .color, .size].shuffled(using: &rng).prefix(level == 1 ? 2 : 3))
        while true {
            let answer = Tile.all.randomElement(using: &rng)!
            // At most one of shape and color is said outright ("I'm a circle"), or too few tiles could break the others.
            var saidOutright = false
            let clues = features.map { feature -> Clue in
                switch feature {
                case .shape, .color:
                    let outright = !saidOutright && Bool.random(using: &rng)
                    saidOutright = saidOutright || outright
                    if feature == .shape {
                        let shape = outright ? answer.shape : TileShape.allCases.filter { $0 != answer.shape }.randomElement(using: &rng)!
                        return Clue(.shape(shape), isNot: !outright)
                    }
                    let color = outright ? answer.color : TileColor.allCases.filter { $0 != answer.color }.randomElement(using: &rng)!
                    return Clue(.color(color), isNot: !outright)
                default:
                    let negated = level >= 4 && Bool.random(using: &rng)
                    return Clue(.size(negated ? answer.size.other : answer.size), isNot: negated)
                }
            }
            // Some clue says what it is, not only what it isn't: three "not"s in a row are too hard to hold.
            guard clues.contains(where: { !$0.isNot }) else { continue }
            // Share the wrong tiles out between the clues as evenly as possible.
            var quotas = Array(repeating: (tileCount - 1) / clues.count, count: clues.count)
            for i in clues.indices.shuffled(using: &rng).prefix((tileCount - 1) % clues.count) { quotas[i] += 1 }
            let pool = Tile.all.shuffled(using: &rng)
            var wrong: [Tile] = []
            for (i, clue) in clues.enumerated() {
                let breaksOnlyThis = pool.filter { tile in
                    !clue.fits(tile) && clues.indices.allSatisfy { $0 == i || clues[$0].fits(tile) }
                }
                wrong += breaksOnlyThis.prefix(quotas[i])
            }
            if wrong.count == tileCount - 1 {
                return (.clues(clues), answer, wrong)
            }
        }
    }
}

// MARK: - Progress

/// How the child is doing at one kind of puzzle.
public struct PuzzleSkill: Codable, Hashable, Sendable {
    public var level = 1
    /// First-try answers in a row at this level.
    public var streak = 0
    /// Puzzles in a row that needed a retry or Help.
    public var misses = 0
    public var solved = 0

    public init() {}

    public static let upAfter = 3
    public static let downAfter = 2

    public mutating func record(_ outcome: WordProgress.Outcome, maxLevel: Int) {
        solved += 1
        if outcome == .firstTry {
            streak += 1
            misses = 0
            if streak >= Self.upAfter, level < maxLevel {
                level += 1
                streak = 0
            }
        } else {
            misses += 1
            streak = 0
            if misses >= Self.downAfter, level > 1 {
                level -= 1
                misses = 0
            }
        }
    }
}

/// Puzzle levels, saved as `Progress/puzzles.json`.
public struct PuzzleProgress: JSONFile, Hashable {
    public var kinds: [String: PuzzleSkill] = [:]
    /// Sessions started, used to rotate which kinds come up.
    public var sessions = 0

    public init() {}

    public subscript(kind: PuzzleKind) -> PuzzleSkill {
        get { kinds[kind.rawValue] ?? PuzzleSkill() }
        set { kinds[kind.rawValue] = newValue }
    }
}

/// Picks the puzzles for one session.
public enum PuzzlePlanner {
    /// Finish the grid is the hardest kind; it joins once "what comes next?" reaches this level.
    public static let gridUnlockLevel = 3
    public static let kindsPerSession = 3

    public static func availableKinds(_ progress: PuzzleProgress) -> [PuzzleKind] {
        PuzzleKind.allCases.filter { $0 != .grid || progress[.next].level >= gridUnlockLevel }
    }

    /// `count` puzzles from up to three kinds (rotating when more are available), taking turns,
    /// each at the child's level for that kind.
    public static func session(
        _ progress: PuzzleProgress,
        count: Int = 6,
        using rng: inout some RandomNumberGenerator
    ) -> [Puzzle] {
        let available = availableKinds(progress)
        let kinds = (0..<min(kindsPerSession, available.count)).map {
            available[(progress.sessions + $0) % available.count]
        }
        return (0..<count).map { i in
            let kind = kinds[i % kinds.count]
            return PuzzleMaker.make(kind, level: progress[kind].level, seed: rng.next())
        }
    }
}
