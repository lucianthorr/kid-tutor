import SpriteKit
import SwiftUI
import UIKit
import KidTutorKit

/// The glass case: a rail along the top, the claw on a cable, a messy pile of squishy toy balls, and on
/// the left an open treasure chest behind a low glass wall. It only draws and animates; `ClawMachine` (KidTutorKit) decides where toys sit and what a
/// drop does, before the animation starts.
final class ClawScene: SKScene {
    /// The claw's position in machine units (0 = left wall, 1 = right wall).
    private(set) var clawX = 0.6
    private(set) var isBusy = false
    /// Called when the child takes hold of the claw, so the screen can stop speaking.
    var onMove: (() -> Void)?

    private var pile: [PiledToy] = []
    private var missStreak = 0

    private let claw = SKNode()
    private let cable = SKSpriteNode(color: UIColor(white: 0.45, alpha: 1), size: CGSize(width: 6, height: 1))
    private let head = SKNode()
    private let leftProng = SKShapeNode()
    private let rightProng = SKShapeNode()
    /// Toy nodes by plush id; each has a "body" child that squashes and stretches.
    private var toys: [String: SKNode] = [:]
    private let decor = SKNode()
    /// `super.init(size:)` already reports a size change; lay out only once the nodes are in place.
    private var isSetUp = false

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.89, green: 0.95, blue: 0.99, alpha: 1)
        addChild(decor)
        cable.anchorPoint = CGPoint(x: 0.5, y: 1)
        claw.addChild(cable)
        claw.addChild(head)
        claw.zPosition = 10
        addChild(claw)
        isSetUp = true
        layout()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Geometry (points, from the scene size)

    private var unit: CGFloat { size.width }
    private var railY: CGFloat { size.height - 26 }
    private var restY: CGFloat { size.height * 0.72 }
    private var floorY: CGFloat { size.height * 0.06 }
    private var radius: CGFloat { px(ClawMachine.plushRadius) }
    private var prongLength: CGFloat { unit * 0.085 }
    private var hubHeight: CGFloat { unit * 0.035 }
    private func px(_ x: Double) -> CGFloat { CGFloat(x) * unit }
    private func point(_ spot: ClawMachine.Spot) -> CGPoint { CGPoint(x: px(spot.x), y: floorY + px(spot.y)) }

    override func didChangeSize(_ oldSize: CGSize) {
        guard isSetUp, size.width > 0, size.height > 0 else { return }
        layout()
    }

    // MARK: - Updates from the screen

    /// Shows the toys now in the machine: toys still there settle into their new places (falling if a toy
    /// under them was won), and new ones drop in from above.
    func show(pile: [PiledToy], missStreak: Int) {
        self.pile = pile
        self.missStreak = missStreak
        guard size.width > 0 else { return }
        settleToys(animated: true)
        openProngs(animated: true)
    }

    func move(to x: Double) {
        guard !isBusy else { return }
        clawX = min(max(x, ClawMachine.clawRange.lowerBound), ClawMachine.clawRange.upperBound)
        claw.position.x = px(clawX)
    }

    func nudge(by dx: Double) { move(to: clawX + dx) }

    // MARK: - Drawing

    private func layout() {
        decor.removeAllChildren()

        let rail = SKShapeNode(rectOf: CGSize(width: size.width - 40, height: 12), cornerRadius: 6)
        rail.fillColor = UIColor(white: 0.55, alpha: 1)
        rail.strokeColor = .clear
        rail.position = CGPoint(x: size.width / 2, y: railY + 4)
        decor.addChild(rail)

        let floor = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size.width, height: floorY))
        floor.fillColor = UIColor(red: 0.80, green: 0.30, blue: 0.27, alpha: 1)
        floor.strokeColor = .clear
        decor.addChild(floor)

        drawChest()

        // The glass wall that keeps the pile out of the chest.
        let wallWidth = unit * 0.014
        let wallHeight = size.height * 0.42
        let wall = SKShapeNode(rect: CGRect(x: px(ClawMachine.wallX) - wallWidth / 2, y: floorY, width: wallWidth, height: wallHeight), cornerRadius: wallWidth / 2)
        wall.fillColor = UIColor(white: 1, alpha: 0.55)
        wall.strokeColor = UIColor(red: 0.55, green: 0.68, blue: 0.78, alpha: 1)
        wall.lineWidth = 3
        wall.zPosition = 25
        decor.addChild(wall)

        // Head: a round hub with a light on top, and two arms.
        head.removeAllChildren()
        let hub = SKShapeNode(rectOf: CGSize(width: unit * 0.07, height: hubHeight), cornerRadius: hubHeight / 2)
        hub.fillColor = UIColor(white: 0.35, alpha: 1)
        hub.strokeColor = .clear
        head.addChild(hub)
        let light = SKShapeNode(circleOfRadius: hubHeight * 0.22)
        light.fillColor = .systemYellow
        light.strokeColor = .clear
        head.addChild(light)
        for (prong, side) in [(leftProng, -1.0), (rightProng, 1.0)] {
            prong.path = prongPath(side: CGFloat(side))
            prong.strokeColor = UIColor(white: 0.35, alpha: 1)
            prong.lineWidth = max(6, unit * 0.009)
            prong.lineCap = .round
            prong.lineJoin = .round
            prong.position = CGPoint(x: CGFloat(side) * unit * 0.02, y: -hubHeight * 0.3)
            head.addChild(prong)
        }

        claw.position = CGPoint(x: px(clawX), y: 0)
        head.position = CGPoint(x: 0, y: restY)
        cable.position = CGPoint(x: 0, y: railY)
        toys.values.forEach { $0.removeFromParent() }
        toys = [:]
        settleToys(animated: false)
        openProngs(animated: false)
    }

    /// An open treasure chest: the lid leans back, the dark inside shows, and the front has gold bands and
    /// a lock. A caught toy falls in behind the front.
    private func drawChest() {
        let cx = px(ClawMachine.chestX)
        let w = unit * 0.17
        let h = w * 0.62
        let wood = UIColor(red: 0.62, green: 0.38, blue: 0.20, alpha: 1)
        let darkWood = UIColor(red: 0.42, green: 0.24, blue: 0.12, alpha: 1)
        let gold = UIColor(red: 0.96, green: 0.76, blue: 0.22, alpha: 1)

        let lidPath = CGMutablePath()
        lidPath.move(to: CGPoint(x: cx - w / 2, y: floorY + h))
        lidPath.addLine(to: CGPoint(x: cx + w / 2, y: floorY + h))
        lidPath.addLine(to: CGPoint(x: cx + w / 2 - w * 0.06, y: floorY + h + h * 0.85))
        lidPath.addQuadCurve(to: CGPoint(x: cx - w / 2 + w * 0.06, y: floorY + h + h * 0.85),
                             control: CGPoint(x: cx, y: floorY + h + h * 1.15))
        lidPath.closeSubpath()
        let lid = SKShapeNode(path: lidPath)
        lid.fillColor = wood
        lid.strokeColor = darkWood
        lid.lineWidth = 4
        lid.zPosition = 2
        decor.addChild(lid)
        let lidBand = SKShapeNode(rect: CGRect(x: cx - w * 0.07, y: floorY + h, width: w * 0.14, height: h * 0.95))
        lidBand.fillColor = gold
        lidBand.strokeColor = .clear
        lidBand.zPosition = 2.1
        decor.addChild(lidBand)

        let inside = SKShapeNode(rect: CGRect(x: cx - w / 2 + 6, y: floorY + h - 10, width: w - 12, height: 22), cornerRadius: 8)
        inside.fillColor = UIColor(red: 0.18, green: 0.10, blue: 0.05, alpha: 1)
        inside.strokeColor = .clear
        inside.zPosition = 3
        decor.addChild(inside)

        let front = SKShapeNode(rect: CGRect(x: cx - w / 2, y: floorY, width: w, height: h), cornerRadius: 8)
        front.fillColor = wood
        front.strokeColor = darkWood
        front.lineWidth = 4
        front.zPosition = 22
        decor.addChild(front)
        for y in [floorY + h * 0.12, floorY + h * 0.78] {
            let band = SKShapeNode(rect: CGRect(x: cx - w / 2, y: y, width: w, height: h * 0.1))
            band.fillColor = gold
            band.strokeColor = .clear
            band.zPosition = 22.1
            decor.addChild(band)
        }
        let lock = SKShapeNode(rectOf: CGSize(width: w * 0.16, height: h * 0.3), cornerRadius: 4)
        lock.fillColor = gold
        lock.strokeColor = darkWood
        lock.lineWidth = 2
        lock.position = CGPoint(x: cx, y: floorY + h * 0.62)
        lock.zPosition = 22.2
        decor.addChild(lock)
        let keyhole = SKShapeNode(circleOfRadius: w * 0.022)
        keyhole.fillColor = darkWood
        keyhole.strokeColor = .clear
        keyhole.position = CGPoint(x: cx, y: floorY + h * 0.64)
        keyhole.zPosition = 22.3
        decor.addChild(keyhole)
    }

    /// The top of the chest's open front, where a toy disappears inside.
    private var chestTop: CGFloat { floorY + unit * 0.17 * 0.62 }

    /// One arm hanging straight down with its tip hooked inward; rotating it about the hub opens the claw.
    private func prongPath(side: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: side * prongLength * 0.12, y: -prongLength * 0.75))
        path.addLine(to: CGPoint(x: -side * prongLength * 0.12, y: -prongLength))
        return path
    }

    /// The claw opens wider as its grip gets better after misses, so the help is visible.
    private func openAngle() -> CGFloat {
        let tipSpread = px(ClawMachine.secureReach(missStreak: missStreak)) + radius * 0.6
        return asin(min(tipSpread / prongLength, 0.97))
    }

    private func setProngs(angle: CGFloat, duration: TimeInterval) -> SKAction {
        SKAction.run { [self] in
            if duration == 0 {
                leftProng.zRotation = -angle
                rightProng.zRotation = angle
            } else {
                leftProng.run(.rotate(toAngle: -angle, duration: duration, shortestUnitArc: true))
                rightProng.run(.rotate(toAngle: angle, duration: duration, shortestUnitArc: true))
            }
        }
    }

    private func openProngs(animated: Bool) {
        run(setProngs(angle: openAngle(), duration: animated ? 0.4 : 0))
    }

    // MARK: - Toys

    private func settleToys(animated: Bool) {
        let ids = Set(pile.map(\.id))
        for (id, node) in toys where !ids.contains(id) {
            node.removeFromParent()
            toys[id] = nil
        }
        var newcomers = 0
        for toy in pile {
            let target = point(toy.spot)
            if let node = toys[toy.id] {
                if hypot(node.position.x - target.x, node.position.y - target.y) > 1 { fall(node, to: target, delay: 0) }
            } else if let plush = PlushCatalog.plush(id: toy.id) {
                let node = Self.plushNode(plush, radius: radius)
                toys[toy.id] = node
                addChild(node)
                if animated {
                    // New toys tumble in from above the pile, one after another.
                    node.position = CGPoint(x: target.x, y: restY - radius)
                    node.alpha = 0
                    node.run(.fadeIn(withDuration: 0.15))
                    fall(node, to: target, delay: 0.08 * Double(newcomers))
                    newcomers += 1
                } else {
                    node.position = target
                }
            }
            // Higher toys draw in front, like a real pile.
            toys[toy.id]?.zPosition = 5 + CGFloat(toy.y * 10)
        }
    }

    private func fall(_ node: SKNode, to target: CGPoint, delay: TimeInterval) {
        let drop = SKAction.move(to: target, duration: max(0.2, Double(node.position.y - target.y) / Double(size.height) * 1.1))
        drop.timingMode = .easeIn
        node.run(.sequence([.wait(forDuration: delay), drop, .run { [self] in squash(node) }]))
    }

    /// Landing: flattens, bounces back a little taller, then settles. Scaled about the toy's bottom.
    private func squash(_ node: SKNode) {
        guard let body = node.childNode(withName: "body") else { return }
        body.removeAction(forKey: "squish")
        body.run(.sequence([
            scale(x: 1.2, y: 0.78, duration: 0.07),
            scale(x: 0.92, y: 1.08, duration: 0.1),
            scale(x: 1.03, y: 0.97, duration: 0.08),
            scale(x: 1, y: 1, duration: 0.08),
        ]), withKey: "squish")
    }

    /// Squeezed by the claw: narrower and taller.
    private func squeeze(_ node: SKNode, _ on: Bool) {
        guard let body = node.childNode(withName: "body") else { return }
        body.removeAction(forKey: "squish")
        body.run(on ? scale(x: 0.82, y: 1.12, duration: 0.3) : scale(x: 1, y: 1, duration: 0.15), withKey: "squish")
    }

    private func scale(x: CGFloat, y: CGFloat, duration: TimeInterval) -> SKAction {
        let action = SKAction.group([.scaleX(to: x, duration: duration), .scaleY(to: y, duration: duration)])
        action.timingMode = .easeOut
        return action
    }

    /// A toy: its face on a round colored cushion. The cushion and face sit in a "body" node anchored at
    /// the toy's bottom, so squashing keeps it resting on the toys below.
    static func plushNode(_ plush: Plush, radius: CGFloat) -> SKNode {
        let node = SKNode()
        let body = SKNode()
        body.name = "body"
        body.position = CGPoint(x: 0, y: -radius)
        node.addChild(body)
        let (r, g, b) = plush.rgb
        let cushion = SKShapeNode(circleOfRadius: radius)
        cushion.fillColor = UIColor(red: r, green: g, blue: b, alpha: 1)
        cushion.strokeColor = UIColor(red: r * 0.75, green: g * 0.75, blue: b * 0.75, alpha: 1)
        cushion.lineWidth = 3
        cushion.position = CGPoint(x: 0, y: radius)
        body.addChild(cushion)
        let face: SKNode
        if plush.isDrawn {
            // A drawn face (no emoji exists), rendered once from SwiftUI to a picture.
            let renderer = ImageRenderer(content: PlushFace(plush: plush, size: radius * 2))
            renderer.scale = UIScreen.main.scale
            face = SKSpriteNode(texture: renderer.uiImage.map(SKTexture.init(image:)), size: CGSize(width: radius * 2, height: radius * 2))
        } else {
            let label = SKLabelNode(text: plush.emoji)
            label.fontSize = radius * 1.35
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            face = label
        }
        face.position = CGPoint(x: 0, y: radius)
        body.addChild(face)
        return node
    }

    override func update(_ currentTime: TimeInterval) {
        cable.size.height = max(1, railY - head.position.y)
    }

    // MARK: - Touch: drag the claw itself to move it

    /// While dragging, how far the claw's middle is from the finger, so the claw doesn't jump to it.
    private var dragOffset: CGFloat?

    /// The claw and its cable, with some extra room around them for a child's finger.
    private func isOnClaw(_ location: CGPoint) -> Bool {
        let halfWidth = max(unit * 0.08, 50)
        return abs(location.x - claw.position.x) <= halfWidth
            && location.y >= head.position.y - prongLength - 30
            && location.y <= railY + 30
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isBusy, let location = touches.first?.location(in: self), isOnClaw(location) else { return }
        dragOffset = claw.position.x - location.x
        onMove?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isBusy, let dragOffset, let location = touches.first?.location(in: self), size.width > 0 else { return }
        move(to: Double((location.x + dragOffset) / size.width))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { dragOffset = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { dragOffset = nil }

    // MARK: - The drop

    /// Lowers onto the toy the rules picked and squeezes it. A caught toy rides to the chest and falls in;
    /// a slipped one rides part of the way up, pops out and falls back onto the pile.
    func play(_ drop: RewardsState.Drop, completion: @escaping () -> Void) {
        guard !isBusy else { return }
        isBusy = true
        var target: (node: SKNode, home: CGPoint)?
        if let id = drop.toyID, let node = toys[id], let toy = pile.first(where: { $0.id == id }) {
            target = (node, point(toy.spot))
        }
        var slipLift: Double?
        if case .slipped(_, let lift) = drop.grab { slipLift = lift }

        // The hub stops just above the toy's middle (or, with nothing under it, near the floor).
        let grabY = (target?.home.y ?? floorY) + prongLength * 0.8
        let down = SKAction.moveTo(y: grabY, duration: Double(restY - grabY) / Double(size.height * 0.45))
        down.timingMode = .easeInEaseOut
        let up = SKAction.moveTo(y: restY, duration: down.duration)
        up.timingMode = .easeInEaseOut
        let holdAngle = asin(min(radius * 0.5 / prongLength, 0.9))

        var steps: [SKAction] = [
            .run { [head] in head.run(down) }, .wait(forDuration: down.duration),
            setProngs(angle: target == nil ? 0.05 : holdAngle, duration: 0.35),
            .run { [self] in if let target { squeeze(target.node, true) } },
            .wait(forDuration: 0.45),
        ]

        if let target, slipLift == nil {
            // Caught: carry it over the wall to the chest and let go.
            steps += [
                .run { [self] in
                    target.node.move(toParent: head)
                    head.run(up)
                },
                .wait(forDuration: up.duration),
            ]
            let toChest = SKAction.moveTo(x: px(ClawMachine.chestX), duration: max(0.4, abs(clawX - ClawMachine.chestX) * 2.2))
            toChest.timingMode = .easeInEaseOut
            steps += [
                .run { [claw] in claw.run(toChest) }, .wait(forDuration: toChest.duration + 0.2),
                setProngs(angle: openAngle(), duration: 0.3),
                .run { [self] in
                    squeeze(target.node, false)
                    target.node.move(toParent: self)
                    // Between the chest's inside and its front, so it drops in.
                    target.node.zPosition = 4
                    let fall = SKAction.group([
                        .moveTo(y: chestTop - radius * 2.2, duration: 0.6),
                        .rotate(byAngle: .pi * 0.4, duration: 0.6),
                    ])
                    fall.timingMode = .easeIn
                    target.node.run(.sequence([fall, .removeFromParent()]))
                },
                .wait(forDuration: 0.7),
            ]
            clawX = ClawMachine.chestX
        } else if let target, let slipLift {
            // Slipped: it rides up while squeezed, then squirts out and lands back where it was.
            let rideTime = max(0.15, up.duration * (0.15 + 0.85 * slipLift))
            steps += [
                .run { [self] in
                    target.node.move(toParent: head)
                    head.run(up)
                },
                .wait(forDuration: rideTime),
                .run { [self] in
                    target.node.move(toParent: self)
                    if let body = target.node.childNode(withName: "body") {
                        body.removeAction(forKey: "squish")
                        body.run(.sequence([scale(x: 1.15, y: 0.85, duration: 0.08), scale(x: 1, y: 1, duration: 0.12)]), withKey: "squish")
                    }
                    // A little pop away from the claw's middle, then down to where it was.
                    let side: CGFloat = target.home.x >= px(clawX) ? 1 : -1
                    let pop = SKAction.moveBy(x: side * radius * 0.3, y: radius * 0.2, duration: 0.12)
                    pop.timingMode = .easeOut
                    target.node.run(.sequence([pop, .run { [self] in fall(target.node, to: target.home, delay: 0) }]))
                },
                .wait(forDuration: max(0, up.duration - rideTime)),
                setProngs(angle: openAngle(), duration: 0.3),
                .wait(forDuration: 0.4),
            ]
        } else {
            steps += [
                .run { [head] in head.run(up) },
                .wait(forDuration: up.duration),
            ]
        }
        steps.append(.run { [self] in
            isBusy = false
            completion()
        })
        run(.sequence(steps), withKey: "drop")
    }
}
