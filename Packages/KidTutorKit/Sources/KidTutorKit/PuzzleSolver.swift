/// Solves a puzzle from what the child can see (the row, the grid, the tiles, the clues), never from the
/// rule it was made with. `PuzzleMaker` only keeps puzzles whose one solution is the answer, so a mistake
/// in making a puzzle shows up as a puzzle that's thrown away instead of one that can't be solved.
public enum PuzzleSolver {
    /// The one choice that fits what's shown is the answer.
    public static func isFair(_ puzzle: Puzzle) -> Bool {
        solutions(puzzle) == [puzzle.answer]
    }

    /// The choices that fit what's shown. A fair puzzle has exactly one.
    public static func solutions(_ puzzle: Puzzle) -> [Int] {
        let choices = puzzle.choices
        switch puzzle.board {
        case .row(let row, _):
            guard let next = nextInRow(row) else { return [] }
            return choices.indices.filter { fits(choices[$0], next) }
        case .group:
            return Puzzle.oddOnes(choices)
        case .grid(let cells, let columns, _):
            guard let gap = fillGap(cells, columns: columns) else { return [] }
            return choices.indices.filter { fits(choices[$0], gap) }
        case .clues(let clues):
            return choices.indices.filter { i in clues.allSatisfy { $0.fits(choices[i]) } }
        }
    }

    private static func fits(_ tile: Tile, _ wanted: [TileFeature: String]) -> Bool {
        wanted.allSatisfy { tile.value($0.key) == $0.value }
    }

    // MARK: What comes next

    /// What the next tile must be, feature by feature: each one repeats on its own beat (colors can repeat
    /// every 2 while shapes repeat every 3) or, for counts, goes up by the same step. Nil if some feature
    /// does neither, so the row doesn't say what comes next.
    static func nextInRow(_ row: [Tile]) -> [TileFeature: String]? {
        var next: [TileFeature: String] = [:]
        for feature in TileFeature.allCases {
            let values = row.map { $0.value(feature) }
            if let value = repeatingNext(values) {
                next[feature] = value
            } else if feature == .count, let value = growingNext(values.compactMap { Int($0) }) {
                next[feature] = String(value)
            } else {
                return nil
            }
        }
        return next
    }

    /// The shortest beat the values repeat on, if it's been seen almost twice (ABA, AABAA), and what it
    /// says comes next.
    private static func repeatingNext(_ values: [String]) -> String? {
        guard !values.isEmpty else { return nil }
        for beat in 1...max(1, (values.count + 1) / 2)
        where values.indices.allSatisfy({ $0 < beat || values[$0] == values[$0 - beat] }) {
            return values[values.count - beat]
        }
        return nil
    }

    /// 1, 2, 3 → 4: at least three numbers going up or down by the same step.
    private static func growingNext(_ numbers: [Int]) -> Int? {
        guard numbers.count >= 3, let last = numbers.last else { return nil }
        let step = numbers[1] - numbers[0]
        guard step != 0, zip(numbers, numbers.dropFirst()).allSatisfy({ $1 - $0 == step }) else { return nil }
        return last + step
    }

    // MARK: Finish the grid

    /// What the gap must be, feature by feature: the same all along its row (every row with two or more
    /// tiles shows that feature staying the same) or else all down its column. Nil if some feature is neither.
    static func fillGap(_ cells: [Tile?], columns: Int) -> [TileFeature: String]? {
        guard columns > 0, let gap = cells.firstIndex(of: nil) else { return nil }
        let rowCount = cells.count / columns
        let rows = (0..<rowCount).map { r in (0..<columns).map { cells[r * columns + $0] } }
        let cols = (0..<columns).map { c in (0..<rowCount).map { cells[$0 * columns + c] } }
        var wanted: [TileFeature: String] = [:]
        for feature in TileFeature.allCases {
            if let value = sameAlong(rows, through: gap / columns, feature) ?? sameAlong(cols, through: gap % columns, feature) {
                wanted[feature] = value
            } else {
                return nil
            }
        }
        return wanted
    }

    /// If `feature` stays the same along every line that shows two or more tiles, the value on line `index`.
    private static func sameAlong(_ lines: [[Tile?]], through index: Int, _ feature: TileFeature) -> String? {
        let shown = lines.map { $0.compactMap { $0?.value(feature) } }
        let evidence = shown.filter { $0.count >= 2 }
        guard !evidence.isEmpty, evidence.allSatisfy({ Set($0).count == 1 }) else { return nil }
        return shown[index].first
    }
}
