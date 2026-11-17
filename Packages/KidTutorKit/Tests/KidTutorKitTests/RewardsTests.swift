import Foundation
import Testing
@testable import KidTutorKit

struct ClawMachineTests {
    private let r = ClawMachine.plushRadius
    private var full: [ClawMachine.Spot] { RewardsState().pile.map(\.spot) }

    @Test func catalogHasUniqueToysAndMoreThanTheMachineHolds() {
        #expect(Set(PlushCatalog.all.map(\.id)).count == PlushCatalog.all.count)
        #expect(PlushCatalog.all.count >= ClawMachine.capacity + 10)
        // Only toys the app knows how to draw go without an emoji.
        #expect(PlushCatalog.all.filter(\.isDrawn).map(\.id) == ["capybara"])
    }

    @Test func aToyFallsRollsAndRestsOnTwoThings() {
        let floor = ClawMachine.settle(x: 0.5, on: [])
        #expect(floor == .init(x: 0.5, y: r))
        // Dropped right on top of another, it rolls off and lands on the floor beside it.
        let beside = ClawMachine.settle(x: 0.5, on: [floor])
        #expect(abs(beside.y - r) < 1e-9 && abs(abs(beside.x - 0.5) - 2 * r) < 0.002)
        // Dropped between two, it sits in the dip between them.
        let pair: [ClawMachine.Spot] = [.init(x: 0.55, y: r), .init(x: 0.67, y: r)]
        let dip = ClawMachine.settle(x: 0.58, on: pair)
        #expect(dip.y > r * 2 && abs(dip.x - 0.61) < 0.01)
        // Against the wall, it stops there.
        let wall = ClawMachine.settle(x: 0, on: [])
        #expect(wall.x == ClawMachine.pileArea.lowerBound + r)
    }

    @Test func theFullPileIsAMessyStablePileBehindTheWall() {
        let pile = full
        #expect(pile.count == ClawMachine.capacity)
        #expect(pile == RewardsState().pile.map(\.spot), "the same every time")
        for (i, p) in pile.enumerated() {
            #expect(p.x - r >= ClawMachine.pileArea.lowerBound - 1e-9 && p.x + r <= ClawMachine.pileArea.upperBound + 1e-9)
            #expect(p.x - r > ClawMachine.wallX)
            for q in pile[(i + 1)...] {
                #expect(hypot(p.x - q.x, p.y - q.y) >= 2 * r - 1e-6)
            }
            // Resting on the floor or on a toy below.
            let supported = p.y <= r + 1e-6 || pile.contains { q in q.y < p.y && abs(hypot(p.x - q.x, p.y - q.y) - 2 * r) < 0.003 }
            #expect(supported, "toy \(i) at \(p)")
        }
        // Not tidy rows: many different heights, and toys stacked at least three deep.
        #expect(Set(pile.map { ($0.y * 1000).rounded() }).count >= 6)
        #expect(pile.map(\.y).max()! > r * 4)
    }

    @Test func takingAToyOutLetsTheOnesOnItFall() {
        let bottom = [PiledToy(id: "a", x: 0.5, y: r), PiledToy(id: "b", x: 0.61, y: r)]
        let topSpot = ClawMachine.settle(x: 0.55, on: bottom.map(\.spot))
        let pile = bottom + [PiledToy(id: "c", x: topSpot.x, y: topSpot.y)]
        let catalog = ["b", "c"].map { Plush(id: $0, name: $0, emoji: "x", color: "#FFFFFF") }
        let after = ClawMachine.arrange(pile, prizes: catalog, seed: 1)
        #expect(after.map(\.id) == ["b", "c"])
        #expect(after[0] == pile[1], "untouched toys stay exactly put")
        #expect(abs(after[1].y - r) < 1e-9)
    }

    @Test func theClawLandsOnTheHighestToyUnderIt() {
        let pile = full
        let top = pile.indices.max { pile[$0].y < pile[$1].y }!
        #expect(ClawMachine.grab(clawX: pile[top].x, spots: pile, missStreak: 0) == .caught(top))
        #expect(ClawMachine.grab(clawX: ClawMachine.chestX, spots: pile, missStreak: 5) == .missed)
    }

    @Test func offCenterGrabsSlipAndFurtherOffSlipsSooner() {
        let spot: [ClawMachine.Spot] = [.init(x: 0.5, y: r)]
        #expect(ClawMachine.grab(clawX: 0.5 + r * 0.4, spots: spot, missStreak: 0) == .caught(0))
        guard case .slipped(0, let near) = ClawMachine.grab(clawX: 0.5 + r * 0.7, spots: spot, missStreak: 0),
              case .slipped(0, let far) = ClawMachine.grab(clawX: 0.5 + r * 1.1, spots: spot, missStreak: 0)
        else {
            Issue.record("expected slips")
            return
        }
        #expect(near > far && near <= 1 && far >= 0)
        #expect(ClawMachine.grab(clawX: 0.5 + r * 1.3, spots: spot, missStreak: 0) == .missed)
    }

    @Test func missesImproveTheGripUntilAnyDropOnAToyWins() {
        #expect(ClawMachine.secureReach(missStreak: 1) > ClawMachine.secureReach(missStreak: 0))
        let pile = full
        let xs = Array(stride(from: ClawMachine.clawRange.lowerBound, through: ClawMachine.clawRange.upperBound, by: 0.002))
        func slips(_ x: Double, _ streak: Int) -> Bool {
            if case .slipped = ClawMachine.grab(clawX: x, spots: pile, missStreak: streak) { return true }
            return false
        }
        #expect(!xs.contains { slips($0, ClawMachine.assistedAfter) })
        #expect(xs.contains { slips($0, ClawMachine.assistedAfter - 1) })
    }

    @Test func noDuplicatesUntilTheSetIsComplete() {
        let catalog = ["bear", "bunny", "fox"].compactMap(PlushCatalog.plush(id:))
        var won: [WonPlush] = []
        #expect(ClawMachine.prizes(catalog: catalog, won: won, count: 2).map(\.id) == ["bear", "bunny"])
        won.append(WonPlush(id: "bunny", wonAt: .now))
        #expect(ClawMachine.prizes(catalog: catalog, won: won, count: 2).map(\.id) == ["bear", "fox"])
        won += ["bear", "fox"].map { WonPlush(id: $0, wonAt: .now) }
        // All won once: a new round with every toy back.
        #expect(ClawMachine.prizes(catalog: catalog, won: won, count: 3).map(\.id) == ["bear", "bunny", "fox"])
    }
}

struct RewardsStateTests {
    private let r = ClawMachine.plushRadius

    @Test func dropNeedsAToken() {
        var state = RewardsState()
        #expect(state.drop(at: 0.5) == nil)
        state.earn(2)
        #expect(state.tokens == 2 && state.totalEarned == 2)
        state.earn(-5)
        #expect(state.tokens == 2)
    }

    @Test func aWinIsRecordedRefillsThePileAndResetsTheAssist() throws {
        var state = RewardsState()
        state.earn(3)
        let pile = state.pile
        let top = pile.indices.max { pile[$0].y < pile[$1].y }!
        let slipDrop = state.drop(at: pile[top].x + r * 0.9)
        let slip = try #require(slipDrop)
        #expect(slip.caught == nil && slip.toyID == pile[top].id && state.missStreak == 1 && state.tokens == 2)
        #expect(state.pile == pile, "a slipped toy lands back where it was")
        let winDrop = state.drop(at: pile[top].x)
        let win = try #require(winDrop)
        #expect(win.grab == .caught(top) && win.caught?.id == pile[top].id)
        #expect(state.missStreak == 0 && state.tokens == 1 && state.won.map(\.id) == [pile[top].id])
        #expect(state.pile.count == ClawMachine.capacity && !state.pile.contains { $0.id == pile[top].id })
        #expect(Set(state.pile.map(\.id)) == Set(state.prizes.map(\.id)))
    }

    @Test func theAssistGuaranteesAWinWithinAFewTokens() {
        var state = RewardsState()
        state.earn(10)
        // A poor aim: just inside the arms' reach of the top toy.
        let top = state.pile.max { $0.y < $1.y }!
        var tries = 0
        while state.won.isEmpty, tries < 10 {
            _ = state.drop(at: top.x + ClawMachine.contactReach * 0.98)
            tries += 1
        }
        #expect(tries == ClawMachine.assistedAfter + 1)
    }

    @Test func collectionCountsDuplicatesInOrderWon() {
        var state = RewardsState()
        state.won = ["fox", "bear", "fox", "unknown"].map { WonPlush(id: $0, wonAt: .now) }
        #expect(state.collection.map(\.plush.id) == ["fox", "bear"])
        #expect(state.collection.map(\.count) == [2, 1])
    }

    @Test func savesAndLoadsAndToleratesMissingKeys() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rewards-\(UUID()).json")
        var state = RewardsState()
        state.earn(4)
        _ = state.drop(at: state.pile[0].x)
        try state.save(to: url)
        #expect(try RewardsState.load(from: url) == state)
        // A file from before the pile was saved gets a full machine.
        let partial = try JSONDecoder().decode(RewardsState.self, from: Data(#"{"tokens": 2}"#.utf8))
        #expect(partial.tokens == 2 && partial.won.isEmpty && partial.pile.count == ClawMachine.capacity)
    }
}

struct TokenTextTests {
    @Test func countsReadNaturally() {
        #expect(TokenText.count(1) == "1 token" && TokenText.count(0) == "0 tokens")
        #expect(TokenText.earned(3) == " You earned 3 tokens for the claw machine!")
        #expect(TokenText.earned(0).isEmpty)
    }
}

struct PlushColorTests {
    @Test func parsesHexColors() {
        let plush = Plush(id: "x", name: "x", emoji: "x", color: "#FF8000")
        #expect(plush.rgb.red == 1 && plush.rgb.blue == 0 && abs(plush.rgb.green - 128.0 / 255) < 1e-9)
        #expect(Plush(id: "x", name: "x", emoji: "x", color: "nope").rgb.red == 0.8)
        #expect(PlushCatalog.all.allSatisfy { $0.rgb != (0.8, 0.8, 0.8) })
    }
}
