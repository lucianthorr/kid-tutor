import Foundation

/// A stuffed animal the claw machine can hold. Drawn as an emoji on a colored cushion.
public struct Plush: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Empty for a toy the app draws itself because there's no emoji for it (`isDrawn`).
    public var emoji: String
    /// Cushion color, as a hex string like "#F4B6C2".
    public var color: String

    public init(id: String, name: String, emoji: String, color: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.color = color
    }

    /// No emoji exists, so the app draws the face (the capybara).
    public var isDrawn: Bool { emoji.isEmpty }
}

public enum PlushCatalog {
    /// The built-in toys, in the order the machine offers them.
    public static let all: [Plush] = [
        Plush(id: "bear", name: "teddy bear", emoji: "🐻", color: "#E8C9A0"),
        // Early in the list so it's in the machine as soon as it's added; there's no capybara emoji.
        Plush(id: "capybara", name: "capybara", emoji: "", color: "#CFE3C8"),
        Plush(id: "bunny", name: "bunny", emoji: "🐰", color: "#F4C6D6"),
        Plush(id: "fox", name: "fox", emoji: "🦊", color: "#F6C89B"),
        Plush(id: "frog", name: "frog", emoji: "🐸", color: "#BFE3A8"),
        Plush(id: "panda", name: "panda", emoji: "🐼", color: "#DADDE2"),
        Plush(id: "penguin", name: "penguin", emoji: "🐧", color: "#B9D4EE"),
        Plush(id: "cat", name: "kitty", emoji: "🐱", color: "#F7DFA0"),
        Plush(id: "dog", name: "puppy", emoji: "🐶", color: "#E3CDB8"),
        Plush(id: "unicorn", name: "unicorn", emoji: "🦄", color: "#E2CCF2"),
        Plush(id: "lion", name: "lion", emoji: "🦁", color: "#F5D28A"),
        Plush(id: "owl", name: "owl", emoji: "🦉", color: "#D8C3A5"),
        Plush(id: "octopus", name: "octopus", emoji: "🐙", color: "#F3B7B0"),
        Plush(id: "koala", name: "koala", emoji: "🐨", color: "#CFD6DC"),
        Plush(id: "pig", name: "piggy", emoji: "🐷", color: "#F8C9CF"),
        Plush(id: "dinosaur", name: "dinosaur", emoji: "🦕", color: "#B6E2D3"),
        Plush(id: "monkey", name: "monkey", emoji: "🐵", color: "#DDBF9F"),
        Plush(id: "chick", name: "chick", emoji: "🐥", color: "#FBE7A1"),
        Plush(id: "turtle", name: "turtle", emoji: "🐢", color: "#C5E3B5"),
        Plush(id: "tiger", name: "tiger", emoji: "🐯", color: "#F7C98B"),
        Plush(id: "cow", name: "cow", emoji: "🐮", color: "#E6E1DA"),
        Plush(id: "hamster", name: "hamster", emoji: "🐹", color: "#F2D2B0"),
        Plush(id: "mouse", name: "mouse", emoji: "🐭", color: "#D9D4E6"),
        Plush(id: "elephant", name: "elephant", emoji: "🐘", color: "#C8D3E0"),
        Plush(id: "whale", name: "whale", emoji: "🐳", color: "#A9D5F0"),
        Plush(id: "ladybug", name: "ladybug", emoji: "🐞", color: "#F5B8B0"),
        Plush(id: "bee", name: "bumblebee", emoji: "🐝", color: "#F9E08C"),
        Plush(id: "butterfly", name: "butterfly", emoji: "🦋", color: "#BFD8F5"),
        Plush(id: "hedgehog", name: "hedgehog", emoji: "🦔", color: "#E0CDB5"),
        Plush(id: "sloth", name: "sloth", emoji: "🦥", color: "#D5C7B4"),
        Plush(id: "flamingo", name: "flamingo", emoji: "🦩", color: "#F8C4D8"),
    ]

    public static func plush(id: String) -> Plush? { all.first { $0.id == id } }
}

/// The claw machine's rules: where the toys sit, and what a drop does.
/// Everything is in machine units: x runs from 0 (left wall) to 1 (right wall); heights use the same
/// unit, measured up from the floor. Toys are squishy balls piled in rows.
///
/// A drop depends only on aim and on recent misses, never on chance. The claw lands on the highest toy
/// under it. Grabbed near its middle, the toy holds; grabbed off-center, it rides up and squeezes out,
/// sooner the further off the claw was.
public enum ClawMachine {
    /// How many toys the machine holds when full.
    public static let capacity = 20
    /// The open toy chest sits on the left; the claw drops a caught toy into it.
    public static let chestX = 0.13
    /// The wall between the chest and the pile: toys pile between `pileArea`'s bounds.
    public static let wallX = 0.255
    public static let pileArea = 0.27...0.975
    /// The claw can travel from over the chest to near the right wall.
    public static let clawRange = 0.07...0.95
    /// A toy's radius.
    public static let plushRadius = 0.05

    /// The claw's arms touch a toy whose middle is this close to the claw's middle.
    public static let contactReach = plushRadius * 1.2

    /// How close to a toy's middle the claw must be for the toy to hold. Starts at half a toy's radius
    /// and grows with each miss in a row; from `assistedAfter` misses it covers everything the claw can
    /// touch, so any drop onto a toy wins: every few tokens is a sure win.
    public static func secureReach(missStreak: Int) -> Double {
        min(plushRadius * (0.5 + 0.35 * Double(max(missStreak, 0))), contactReach)
    }
    public static let assistedAfter = 2

    /// A toy's resting place: its middle, in machine units.
    public struct Spot: Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    // MARK: Piling

    /// Where a toy dropped straight down at `x` comes to rest on `others`: it falls until it touches the
    /// floor or a toy, rolls off that toy away from its middle, and stops once it rests on two things
    /// (two toys, a toy and the floor, or a toy and a wall). Like a real pile, it's a mess, but the same
    /// drops always make the same pile.
    public static func settle(x: Double, on others: [Spot]) -> Spot {
        let r = plushRadius
        let d = 2 * r
        let lo = pileArea.lowerBound + r
        let hi = pileArea.upperBound - r
        var p = Spot(x: min(max(x, lo), hi), y: .infinity)

        func touching(_ q: Spot, except: Int) -> Int? {
            others.indices.first { $0 != except && hypot(others[$0].x - q.x, others[$0].y - q.y) < d - 1e-9 }
        }

        for _ in 0..<50 {
            // Fall straight down onto the highest toy under it, or the floor.
            var support: Int?
            var restY = r
            for (j, o) in others.enumerated() where abs(o.x - p.x) < d - 1e-9 {
                let y = o.y + sqrt(d * d - (o.x - p.x) * (o.x - p.x))
                if y > restY {
                    restY = y
                    support = j
                }
            }
            p.y = restY
            guard var a = support else { return p }

            // Roll around the toy it landed on, downhill, until something stops it.
            let direction: Double = p.x > others[a].x ? -1 : p.x < others[a].x ? 1 : (p.x < (lo + hi) / 2 ? -1 : 1)
            var angle = atan2(p.y - others[a].y, p.x - others[a].x)
            var rolledOff = false
            var steps = 0
            rolling: while steps < 1000 {
                steps += 1
                let next = angle + direction * 0.01
                // Past level with the toy it rolls on: it drops off the side and falls again.
                if next <= 0 || next >= .pi {
                    rolledOff = true
                    break rolling
                }
                let q = Spot(x: others[a].x + d * cos(next), y: others[a].y + d * sin(next))
                if q.y < r || q.x < lo || q.x > hi { return p }
                if let b = touching(q, except: a) {
                    // Resting on two toys, one each side: it stays. Otherwise it rolls on over the other one.
                    if (others[b].x - p.x) * (others[a].x - p.x) <= 0 { return p }
                    a = b
                    angle = atan2(p.y - others[a].y, p.x - others[a].x)
                    continue
                }
                p = q
                angle = next
            }
            if rolledOff {
                // Level with the toy it rolled on, then off the side and falling again.
                let side = Spot(x: others[a].x + (direction > 0 ? -d : d), y: others[a].y)
                if side.x < lo || side.x > hi || touching(side, except: a) != nil { return p }
                p = side
            }
        }
        return p
    }

    /// Re-settles a pile after a toy is taken out: from the bottom up, each toy drops again where it was,
    /// so toys that leaned on the missing one fall into the gap.
    public static func resettle(_ toys: [PiledToy]) -> [PiledToy] {
        var settled: [PiledToy] = []
        for toy in toys.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            let spot = settle(x: toy.x, on: settled.map(\.spot))
            // A toy that didn't need to move keeps its exact place (no tiny drifts).
            let moved = hypot(spot.x - toy.x, spot.y - toy.y) > 0.002
            settled.append(PiledToy(id: toy.id, x: moved ? spot.x : toy.x, y: moved ? spot.y : toy.y))
        }
        let order = Dictionary(uniqueKeysWithValues: toys.enumerated().map { ($1.id, $0) })
        return settled.sorted { order[$0.id]! < order[$1.id]! }
    }

    /// The pile for `prizes`: toys no longer in the machine are taken out (the rest settle), and new ones
    /// are dropped in from above at spots picked by `seed`.
    public static func arrange(_ pile: [PiledToy], prizes: [Plush], seed: UInt64) -> [PiledToy] {
        let ids = Set(prizes.map(\.id))
        var toys = pile.filter { ids.contains($0.id) }
        if toys.count < pile.count { toys = resettle(toys) }
        var random = SeededRandom(seed: seed)
        let present = Set(toys.map(\.id))
        for plush in prizes where !present.contains(plush.id) {
            let x = Double.random(in: pileArea, using: &random)
            let spot = settle(x: x, on: toys.map(\.spot))
            toys.append(PiledToy(id: plush.id, x: spot.x, y: spot.y))
        }
        return toys
    }

    /// The toys in the machine now: the next ones in catalog order not yet won in the current round.
    /// No duplicates until every toy has been won once; then a new round starts, and the machine fills up.
    public static func prizes(catalog: [Plush] = PlushCatalog.all, won: [WonPlush], count: Int = capacity) -> [Plush] {
        guard !catalog.isEmpty else { return [] }
        let counts = Dictionary(won.map { ($0.id, 1) }, uniquingKeysWith: +)
        let round = catalog.map { counts[$0.id] ?? 0 }.min() ?? 0
        return Array(catalog.filter { (counts[$0.id] ?? 0) == round }.prefix(count))
    }

    public enum Grab: Hashable, Sendable {
        /// The claw held the toy at this index.
        case caught(Int)
        /// The claw squeezed this toy but it slipped out; `lift` (0...1) is how far up it rode first.
        case slipped(Int, lift: Double)
        /// The claw touched nothing.
        case missed
    }

    /// What a claw dropped at `clawX` does: it lands on the highest toy its arms touch.
    public static func grab(clawX: Double, spots: [Spot], missStreak: Int) -> Grab {
        let touched = spots.indices.filter { abs(spots[$0].x - clawX) < contactReach }
        guard let index = touched.max(by: { spots[$0].y < spots[$1].y }) else { return .missed }
        let offset = abs(spots[index].x - clawX)
        let secure = secureReach(missStreak: missStreak)
        if offset <= secure + 1e-9 { return .caught(index) }
        let lift = 1 - (offset - secure) / max(contactReach - secure, 1e-9)
        return .slipped(index, lift: min(max(lift, 0), 1))
    }
}

/// A toy lying in the machine.
public struct PiledToy: Hashable, Codable, Sendable {
    public var id: String
    public var x: Double
    public var y: Double

    public init(id: String, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }

    public var spot: ClawMachine.Spot { ClawMachine.Spot(x: x, y: y) }
}

/// SplitMix64: the same seed always gives the same numbers, so a pile can be rebuilt exactly.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public struct WonPlush: Hashable, Codable, Sendable {
    public var id: String
    public var wonAt: Date

    public init(id: String, wonAt: Date) {
        self.id = id
        self.wonAt = wonAt
    }
}

/// Tokens and won toys, saved as `Progress/rewards.json`. Tokens are only earned by practicing,
/// never expire, and nothing won is ever taken away.
public struct RewardsState: JSONFile, Hashable {
    public var tokens = 0
    public var totalEarned = 0
    public var won: [WonPlush] = []
    /// Drops in a row that caught nothing; improves the claw's grip (`ClawMachine.secureReach`).
    public var missStreak = 0
    /// Where the toys lie. Saved, so the pile looks the same next time; `fillMachine()` keeps it in step
    /// with `prizes`.
    public var pile: [PiledToy] = []

    public init() {
        fillMachine()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try c.decodeIfPresent(Int.self, forKey: .tokens) ?? 0
        totalEarned = try c.decodeIfPresent(Int.self, forKey: .totalEarned) ?? 0
        won = try c.decodeIfPresent([WonPlush].self, forKey: .won) ?? []
        missStreak = try c.decodeIfPresent(Int.self, forKey: .missStreak) ?? 0
        pile = try c.decodeIfPresent([PiledToy].self, forKey: .pile) ?? []
        fillMachine()
    }

    public mutating func earn(_ count: Int) {
        guard count > 0 else { return }
        tokens += count
        totalEarned += count
    }

    public var prizes: [Plush] { ClawMachine.prizes(won: won) }

    /// Takes won toys out of the pile and drops new ones in. Different wins make different piles.
    public mutating func fillMachine() {
        let prizes = prizes
        guard pile.count != prizes.count || Set(pile.map(\.id)) != Set(prizes.map(\.id)) else { return }
        pile = ClawMachine.arrange(pile, prizes: prizes, seed: UInt64(won.count) &* 7919 &+ 1)
    }

    public struct Drop: Hashable, Sendable {
        /// What happened; indexes refer to `pile` as it was before the drop.
        public var grab: ClawMachine.Grab
        /// The toy the claw squeezed, caught or slipped.
        public var toyID: String?
        public var caught: Plush?
    }

    /// Spends a token and decides the drop at `clawX`. Returns nil (and spends nothing) without a token.
    /// The result is recorded at once, so leaving mid-animation never loses a won toy.
    public mutating func drop(at clawX: Double, at date: Date = Date()) -> Drop? {
        guard tokens > 0 else { return nil }
        fillMachine()
        let grab = ClawMachine.grab(clawX: clawX, spots: pile.map(\.spot), missStreak: missStreak)
        tokens -= 1
        switch grab {
        case .caught(let index):
            let id = pile[index].id
            won.append(WonPlush(id: id, wonAt: date))
            missStreak = 0
            fillMachine()
            return Drop(grab: grab, toyID: id, caught: PlushCatalog.plush(id: id))
        case .slipped(let index, _):
            missStreak += 1
            return Drop(grab: grab, toyID: pile[index].id, caught: nil)
        case .missed:
            missStreak += 1
            return Drop(grab: grab, toyID: nil, caught: nil)
        }
    }

    /// Won toys, one entry per kind in the order first won, with how many of each.
    public var collection: [(plush: Plush, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for w in won {
            if counts[w.id] == nil { order.append(w.id) }
            counts[w.id, default: 0] += 1
        }
        return order.compactMap { id in PlushCatalog.plush(id: id).map { ($0, counts[id]!) } }
    }
}

/// What the app says about tokens.
public enum TokenText {
    /// "1 token", "3 tokens".
    public static func count(_ n: Int) -> String { n == 1 ? "1 token" : "\(n) tokens" }

    /// Said at the end of a session; empty when none were earned (a grown-up set 0 per session).
    public static func earned(_ n: Int) -> String {
        n > 0 ? " You earned \(count(n)) for the claw machine!" : ""
    }
}

extension Plush {
    /// The cushion color as red, green, blue from 0 to 1 (gray if the hex string is malformed).
    public var rgb: (red: Double, green: Double, blue: Double) {
        let hex = color.hasPrefix("#") ? String(color.dropFirst()) : color
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return (0.8, 0.8, 0.8) }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}
