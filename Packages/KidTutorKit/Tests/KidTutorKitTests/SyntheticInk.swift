import Foundation
@testable import KidTutorKit

/// Deterministic random numbers so jittered test letters are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Crude letters drawn on a 100×100 box, the way a child might.
enum SyntheticInk {
    typealias Stroke = [(Double, Double)]

    static func line(_ from: (Double, Double), _ to: (Double, Double), steps: Int = 12) -> Stroke {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            return (from.0 + (to.0 - from.0) * t, from.1 + (to.1 - from.1) * t)
        }
    }

    static func arc(center: (Double, Double), radius: Double, from start: Double, to end: Double, steps: Int = 24) -> Stroke {
        (0...steps).map { i in
            let angle = (start + (end - start) * Double(i) / Double(steps)) * .pi / 180
            return (center.0 + radius * cos(angle), center.1 + radius * sin(angle))
        }
    }

    static let letters: [String: [Stroke]] = [
        "l": [line((50, 10), (50, 90))],
        "i": [line((50, 40), (50, 90)), [(50, 20)]],
        "o": [arc(center: (50, 65), radius: 25, from: 0, to: 360)],
        "c": [arc(center: (50, 65), radius: 25, from: 45, to: 315)],
        "b": [line((30, 10), (30, 90)), arc(center: (50, 70), radius: 20, from: 180, to: 540)],
        "d": [line((70, 10), (70, 90)), arc(center: (50, 70), radius: 20, from: 0, to: 360)],
        "x": [line((25, 40), (75, 90)), line((75, 40), (25, 90))],
        "t": [line((50, 10), (50, 90)), line((25, 35), (75, 35))],
    ]

    /// A letter with hand-like wobble, a random size and a random position.
    static func ink(_ letter: String, seed: UInt64, reversed: Bool = false) -> Ink {
        var rng = SeededGenerator(seed: seed)
        let scale = Double.random(in: 0.8...1.2, using: &rng)
        let dx = Double.random(in: -10...10, using: &rng)
        let dy = Double.random(in: -10...10, using: &rng)
        var strokes = letters[letter]!.map { stroke in
            InkStroke(points: stroke.map { x, y in
                InkPoint(
                    x: x * scale + dx + Double.random(in: -1.5...1.5, using: &rng),
                    y: y * scale + dy + Double.random(in: -1.5...1.5, using: &rng)
                )
            })
        }
        if reversed {
            strokes = strokes.reversed().map { InkStroke(points: $0.points.reversed()) }
        }
        return Ink(strokes: strokes, canvasWidth: 100, canvasHeight: 100)
    }

    static func samples(_ letters: [String], perLetter: Int, seedBase: UInt64 = 1) -> [InkSample] {
        letters.enumerated().flatMap { index, letter in
            (0..<perLetter).map { n in
                let seed = seedBase + UInt64(index * 100 + n)
                return InkSample(source: .calibration, ink: ink(letter, seed: seed), expected: letter, confirmedLabel: letter)
            }
        }
    }
}
