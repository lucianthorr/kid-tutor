import Foundation
import Testing
@testable import KidTutorKit

/// Every kind at every level, over many seeds.
private func everyPuzzle(seeds: Int = 200) -> [Puzzle] {
    PuzzleKind.allCases.flatMap { kind in
        (1...kind.maxLevel).flatMap { level in
            (0..<UInt64(seeds)).map { PuzzleMaker.make(kind, level: level, seed: $0 &* 2_654_435_761) }
        }
    }
}

struct PuzzleMakerTests {
    @Test func theSameSeedMakesTheSamePuzzle() {
        for kind in PuzzleKind.allCases {
            #expect(PuzzleMaker.make(kind, level: 2, seed: 42) == PuzzleMaker.make(kind, level: 2, seed: 42))
        }
        #expect(PuzzleMaker.make(.next, level: 9, seed: 1).level == PuzzleKind.next.maxLevel)
        #expect(PuzzleMaker.make(.next, level: 0, seed: 1).level == 1)
    }

    @Test func choicesAreDifferentPictures() {
        for puzzle in everyPuzzle() {
            guard case .group = puzzle.board else {
                #expect(Set(puzzle.choices).count == puzzle.choices.count, "\(puzzle.logDescription)")
                continue
            }
        }
    }

    @Test func whatComesNextContinuesTheRow() {
        for puzzle in everyPuzzle() where puzzle.kind == .next {
            guard case .row(let row, let pattern) = puzzle.board else { Issue.record("not a row"); continue }
            let full = row + [puzzle.answerTile]
            switch pattern {
            case .repeating(let unit):
                #expect(full.indices.allSatisfy { full[$0] == unit[$0 % unit.count] }, "\(puzzle.logDescription)")
                // The row shows the whole unit at least twice, so the pattern can be seen.
                #expect(row.count >= unit.count * 2 - 1)
            case .twoBeats(let colors, let shapes):
                #expect(full.indices.allSatisfy { full[$0].color == colors[$0 % 2] && full[$0].shape == shapes[$0 % 3] })
                #expect(row.count >= 6)
            case .growing:
                #expect(full.map(\.count) == Array(1...full.count))
            }
            #expect((3...4).contains(puzzle.choices.count))
        }
    }

    @Test func oddOneOutHasExactlyOneOddTile() {
        for puzzle in everyPuzzle() where puzzle.kind == .oddOneOut {
            #expect(puzzle.choices.count == 4)
            #expect(Puzzle.oddOnes(puzzle.choices) == [puzzle.answer], "\(puzzle.logDescription)")
            // A size difference only shows among tiles of one shape.
            if case .group(.size) = puzzle.board {
                #expect(Set(puzzle.choices.map(\.shape)).count == 1, "\(puzzle.logDescription)")
            }
        }
    }

    @Test func theSolverFindsOnlyTheAnswer() {
        for puzzle in everyPuzzle(seeds: 500) {
            #expect(PuzzleSolver.isFair(puzzle), "\(puzzle.logDescription)")
        }
    }

    @Test func gridRowsAndColumnsFollowTheRule() {
        for puzzle in everyPuzzle() where puzzle.kind == .grid {
            guard case .grid(var cells, let columns, let rule) = puzzle.board else { Issue.record("not a grid"); continue }
            #expect(cells.filter { $0 == nil }.count == 1)
            cells[cells.firstIndex(of: nil)!] = puzzle.answerTile
            let tiles = cells.map { $0! }
            let rows = stride(from: 0, to: tiles.count, by: columns).map { Array(tiles[$0..<($0 + columns)]) }
            if rule.rowsRepeat {
                #expect(Set(rows).count == 1)
                continue
            }
            for row in rows {
                for f in rule.rows { #expect(Set(row.map { $0.value(f) }).count == 1, "\(puzzle.logDescription)") }
            }
            for c in 0..<columns {
                let column = rows.map { $0[c] }
                for f in rule.columns { #expect(Set(column.map { $0.value(f) }).count == 1, "\(puzzle.logDescription)") }
            }
            // Every wrong choice breaks the row rule, the column rule, or both.
            for i in puzzle.wrongChoices {
                let picked = puzzle.choices[i]
                let fitsBoth = rule.rows.union(rule.columns).allSatisfy { picked.value($0) == puzzle.answerTile.value($0) }
                #expect(!fitsBoth)
            }
        }
    }

    @Test func onlyTheAnswerFitsEveryClueAndEachClueRulesSomethingOut() {
        for puzzle in everyPuzzle() where puzzle.kind == .whoAmI {
            guard case .clues(let clues) = puzzle.board else { Issue.record("not clues"); continue }
            let fitting = puzzle.choices.indices.filter { i in clues.allSatisfy { $0.fits(puzzle.choices[i]) } }
            #expect(fitting == [puzzle.answer], "\(puzzle.logDescription)")
            let ruledOut = Set(puzzle.wrongChoices.compactMap(puzzle.clueRulingOut))
            #expect(ruledOut == Set(clues.indices), "\(puzzle.logDescription)")
            #expect(puzzle.choices.count == [4, 6, 8, 8][puzzle.level - 1])
            #expect(clues.contains { !$0.isNot }, "\(puzzle.logDescription)")
        }
    }
}

struct PuzzleSolverTests {
    private let a = Tile(.circle, .red), b = Tile(.square, .blue), c = Tile(.star, .green)

    private func puzzle(_ board: Puzzle.Board, _ choices: [Tile]) -> Puzzle {
        Puzzle(kind: .next, level: 1, seed: 0, board: board, choices: choices, answer: 0)
    }

    @Test func rowsRepeatOnTheirOwnBeats() {
        #expect(PuzzleSolver.solutions(puzzle(.row([a, b, a, b, a], .repeating([a, b])), [a, b, c])) == [1])
        #expect(PuzzleSolver.solutions(puzzle(.row([a, a, b, a, a], .repeating([a, a, b])), [a, b, c])) == [1])
        // Colors every 2, shapes every 3: red circle, blue square, red star, blue circle, red square, blue star → red circle.
        let two = [(TileShape.circle, TileColor.red), (.square, .blue), (.star, .red), (.circle, .blue), (.square, .red), (.star, .blue)].map { Tile($0, $1) }
        #expect(PuzzleSolver.solutions(puzzle(.row(two, .twoBeats(colors: [.red, .blue], shapes: [.circle, .square, .star])), [Tile(.circle, .blue), a, Tile(.square, .red)])) == [1])
        let growing = [1, 2, 3].map { Tile(.star, .red, count: $0) }
        #expect(PuzzleSolver.solutions(puzzle(.row(growing, .growing), [3, 4, 5].map { Tile(.star, .red, count: $0) })) == [1])
    }

    @Test func aRowThatNeverRepeatsHasNoAnswer() {
        #expect(PuzzleSolver.solutions(puzzle(.row([a, b, c], .repeating([a, b, c])), [a, b, c])).isEmpty)
    }

    @Test func gridsReadRowsAndColumns() {
        let rule = Puzzle.GridRule(rows: [.shape], columns: [.color])
        let cells: [Tile?] = [Tile(.circle, .red), Tile(.circle, .blue), Tile(.square, .red), nil]
        #expect(PuzzleSolver.solutions(puzzle(.grid(cells, columns: 2, rule: rule), [Tile(.square, .red), Tile(.square, .blue), Tile(.circle, .blue)])) == [1])
    }

    @Test func brokenGridsAreRejected() {
        let rule = Puzzle.GridRule(rows: [.shape], columns: [.color])
        // Row 0 keeps its shape but row 1 doesn't, and no column keeps its color either: nothing to go on.
        let contradicting: [Tile?] = [Tile(.circle, .red), Tile(.circle, .blue), Tile(.square, .green), Tile(.star, .yellow), Tile(.square, .red), nil]
        #expect(PuzzleSolver.solutions(puzzle(.grid(contradicting, columns: 3, rule: rule), [Tile(.square, .yellow), Tile(.star, .blue)])).isEmpty)
        // A grid that settles the shape but not the color lets two choices fit.
        let loose: [Tile?] = [Tile(.circle, .red), Tile(.circle, .blue), Tile(.square, .green), nil]
        #expect(PuzzleSolver.solutions(puzzle(.grid(loose, columns: 2, rule: rule), [Tile(.square, .yellow), Tile(.square, .blue), Tile(.circle, .red)])).isEmpty)
        // Two right answers among the choices.
        let fine: [Tile?] = [Tile(.circle, .red), Tile(.circle, .blue), Tile(.square, .red), nil]
        let twice = puzzle(.grid(fine, columns: 2, rule: rule), [Tile(.square, .blue), Tile(.square, .blue, .small), Tile(.square, .blue)])
        #expect(PuzzleSolver.solutions(twice).count == 2)
    }

    @Test func aRowTooShortToShowItsBeatsHasNoAnswer() {
        // Colors every 2, shapes every 3, but only 4 tiles: the shapes haven't come round once.
        let short = [Tile(.circle, .red), Tile(.square, .blue), Tile(.star, .red), Tile(.circle, .blue)]
        #expect(PuzzleSolver.solutions(puzzle(.row(short, .twoBeats(colors: [.red, .blue], shapes: [.circle, .square, .star])), [Tile(.square, .red), a])).isEmpty)
    }

    @Test func twoOddTilesIsNotAPuzzle() {
        // The blue circle is odd by color and the square by shape: two answers.
        let tiles = [Tile(.circle, .red), Tile(.circle, .red), Tile(.circle, .blue), Tile(.square, .red)]
        #expect(PuzzleSolver.solutions(puzzle(.group(odd: .shape), tiles)) == [2, 3])
        #expect(!PuzzleSolver.isFair(puzzle(.group(odd: .shape), tiles)))
    }

    @Test func twoTilesThatFitIsNotAPuzzle() {
        let clues = [Clue(.color(.red))]
        #expect(PuzzleSolver.solutions(puzzle(.clues(clues), [a, Tile(.star, .red), b])) == [0, 1])
        #expect(PuzzleSolver.solutions(puzzle(.group(odd: .shape), [a, b, c, Tile(.triangle, .yellow)])).isEmpty)
    }
}

struct PuzzleSpeechTests {
    private let red = Tile(.circle, .red), blue = Tile(.square, .blue)

    private func puzzle(_ board: Puzzle.Board, _ choices: [Tile], answer: Int, kind: PuzzleKind) -> Puzzle {
        Puzzle(kind: kind, level: 1, seed: 0, board: board, choices: choices, answer: answer)
    }

    @Test func whatComesNextSaysTheRhythm() {
        let p = puzzle(.row([red, blue, red, blue, red], .repeating([red, blue])), [red, blue, Tile(.star, .green)], answer: 1, kind: .next)
        #expect(p.intro == ["What comes next? Red circle, blue square, red circle, blue square, red circle… Tap the one that comes next."])
        #expect(p.praise == "Yes! Red circle, blue square, red circle, blue square, red circle… blue square!")
        #expect(p.hint(press: 0).text == "Listen: it goes red circle, blue square, then starts again.")

        let growing = puzzle(.row([1, 2, 3].map { Tile(.star, .red, count: $0) }, .growing),
                             [3, 4, 5].map { Tile(.star, .red, count: $0) }, answer: 1, kind: .next)
        #expect(growing.praise == "Yes! One, two, three… four!")
        #expect(growing.name(of: growing.answerTile) == "four red stars")
    }

    @Test func oddOneOutNamesTheDifference() {
        let tiles = [Tile(.circle, .red), Tile(.circle, .blue), Tile(.circle, .yellow), Tile(.triangle, .green)]
        let p = puzzle(.group(odd: .shape), tiles, answer: 3, kind: .oddOneOut)
        #expect(p.praise == "Yes! The others are all circles. The triangle doesn't belong.")
        #expect(p.wrong(1) == "Hmm, the blue circle is a circle like the others. Try another.")
        #expect(p.hint(press: 0).text == "Look at the shapes.")
        #expect(p.wrongCue(1).together == [0, 1, 2])

        let sizes = [Tile(.circle, .red), Tile(.square, .blue), Tile(.star, .yellow), Tile(.triangle, .green, .small)]
        let s = puzzle(.group(odd: .size), sizes, answer: 3, kind: .oddOneOut)
        #expect(s.praise == "Yes! The others are all big. The small one doesn't belong.")
        #expect(s.wrong(0) == "Hmm, the big red circle is big like the others. Try another.")
    }

    @Test func gridWrongAnswersSayWhatWasRightAndWhereToLook() {
        let p = PuzzleMaker.make(.grid, level: 3, seed: 7)
        guard case .grid(_, _, let rule) = p.board else { Issue.record("not a grid"); return }
        #expect(rule.rows == [.shape] && rule.columns == [.color])
        let answer = p.answerTile
        let rightShape = p.choices.firstIndex { $0.shape == answer.shape && $0.color != answer.color }!
        #expect(p.wrong(rightShape) == "That's a \(answer.shape.rawValue), good! But look down this column. What color are they?")
        #expect(p.praise == "Yes! This row is all \(answer.shape.rawValue)s, and this column is all \(answer.color.rawValue). It's the \(answer.color.rawValue) \(answer.shape.rawValue)!")
        #expect(p.hint(press: 0).line == .row && p.hint(press: 1).line == .column)
        #expect(p.wrongCue(rightShape).lines == [.column])
        let rightColor = p.choices.firstIndex { $0.color == answer.color && $0.shape != answer.shape }!
        #expect(p.wrongCue(rightColor).lines == [.row])

        let counting = PuzzleMaker.make(.grid, level: 4, seed: 7)
        #expect(counting.praise.contains("every one in this column has \(Spoken.number(counting.answerTile.count))"))
    }

    @Test func whoAmIChecksEachClueAgainstThePick() {
        let clues = [Clue(.color(.red), isNot: true), Clue(.shape(.circle), isNot: true), Clue(.size(.big))]
        let tiles = [Tile(.square, .blue), Tile(.square, .blue, .small), Tile(.circle, .red), Tile(.circle, .red, .small), Tile(.star, .red, .small)]
        let p = puzzle(.clues(clues), tiles, answer: 0, kind: .whoAmI)
        #expect(p.intro == ["Listen to my clues and find me!", "I'm not red.", "I'm not a circle.", "I'm big.", "Who am I?"])
        #expect(p.praise == "You found me! Not red, not a circle, and big. The big blue square!")
        #expect(p.wrong(1) == "The small blue square isn't red and isn't a circle… but I'm big!")
        #expect(p.wrong(3) == "Not the small red circle. Listen: I'm not red!")
        #expect(p.wrong(4) == "The small red star isn't a circle… but I'm not red!")
        #expect(p.clueRulingOut(2) == 0 && p.clueRulingOut(1) == 2)
        #expect(p.wrongCue(1).clue == 2 && p.wrongCue(3).clue == 0)
    }
}

struct PuzzleProgressTests {
    @Test func threeFirstTriesLevelUpTwoMissesLevelDown() {
        var skill = PuzzleSkill()
        for _ in 0..<3 { skill.record(.firstTry, maxLevel: 4) }
        #expect(skill.level == 2)
        skill.record(.retried, maxLevel: 4)
        #expect(skill.level == 2)
        skill.record(.hinted, maxLevel: 4)
        #expect(skill.level == 1)
        skill.record(.hinted, maxLevel: 4)
        skill.record(.hinted, maxLevel: 4)
        #expect(skill.level == 1 && skill.solved == 7)

        var top = PuzzleSkill()
        top.level = 4
        for _ in 0..<5 { top.record(.firstTry, maxLevel: 4) }
        #expect(top.level == 4)
    }

    @Test func gridWaitsForWhatComesNext() {
        var progress = PuzzleProgress()
        #expect(PuzzlePlanner.availableKinds(progress) == [.next, .oddOneOut, .whoAmI])
        progress[.next].level = PuzzlePlanner.gridUnlockLevel
        #expect(PuzzlePlanner.availableKinds(progress) == PuzzleKind.allCases)
    }

    @Test func sessionsTakeTurnsAtTheChildsLevel() {
        var progress = PuzzleProgress()
        progress[.whoAmI].level = 3
        var rng = SeededRandom(seed: 1)
        let first = PuzzlePlanner.session(progress, using: &rng)
        #expect(first.map(\.kind) == [.next, .oddOneOut, .whoAmI, .next, .oddOneOut, .whoAmI])
        #expect(first.filter { $0.kind == .whoAmI }.allSatisfy { $0.level == 3 })

        progress[.next].level = 3
        progress.sessions = 1
        let rotated = PuzzlePlanner.session(progress, using: &rng)
        #expect(rotated.map(\.kind).prefix(3) == [.oddOneOut, .grid, .whoAmI])
    }

    @Test func savesAndLoads() throws {
        var progress = PuzzleProgress()
        progress[.grid].level = 2
        progress.sessions = 4
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("puzzles-\(UUID()).json")
        try progress.save(to: url)
        #expect(try PuzzleProgress.load(from: url) == progress)
    }
}
