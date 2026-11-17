import SpriteKit
import SwiftUI
import KidTutorKit

/// The claw machine: spend a token, move the claw over a toy, drop. Opened from Home's Rewards button.
struct RewardsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scene: ClawScene = {
        let scene = ClawScene(size: CGSize(width: 900, height: 700))
        return scene
    }()
    @State private var dropping = false
    @State private var won: Plush?
    @State private var showingChest = false

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                RoundIconButton(systemImage: "house.fill", label: "Home") { dismiss() }
                RoundIconButton(systemImage: "speaker.wave.2.fill", label: "Say it again") { sayWelcome() }
                TokenBadge(count: model.rewards.tokens)
                Spacer()
                Button {
                    showingChest = true
                } label: {
                    Label("Toy chest", systemImage: "shippingbox.fill")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.horizontal, 24)
                        .frame(minHeight: 84)
                }
                .buttonStyle(.bordered)
                .tint(.brown)
                .disabled(dropping)
            }

            SpriteView(scene: scene)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.red.opacity(0.8), lineWidth: 10))
                .accessibilityLabel("Claw machine with \(model.rewards.prizes.map(\.name).joined(separator: ", "))")

            HStack(spacing: 48) {
                arrowButton("arrowtriangle.left.fill", label: "Move left", dx: -0.012)
                Button(action: drop) {
                    Text("Drop!")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 64)
                        .frame(minHeight: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(dropping || model.rewards.tokens == 0)
                arrowButton("arrowtriangle.right.fill", label: "Move right", dx: 0.012)
            }
        }
        .padding(32)
        .overlay {
            if let won { WinCard(plush: won) { self.won = nil; afterWin() } }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .navigationDestination(isPresented: $showingChest) { ToyChestView() }
        .onAppear {
            Log.info(.rewards, "claw machine open tokens=\(model.rewards.tokens) prizes=\(model.rewards.prizes.map(\.id).joined(separator: ",")) missStreak=\(model.rewards.missStreak)")
            scene.show(pile: model.rewards.pile, missStreak: model.rewards.missStreak)
            scene.onMove = { [weak speaker = model.speaker] in speaker?.stop() }
            sayWelcome()
            // `-openToyChest` opens the chest; `-clawDrop 0.55` moves the claw there and drops (for screenshots and testing).
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-openToyChest") { showingChest = true }
            if let i = args.firstIndex(of: "-clawDrop"), i + 1 < args.count, let x = Double(args[i + 1]) {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    scene.move(to: x)
                    try? await Task.sleep(for: .seconds(1))
                    drop()
                }
            }
        }
    }

    private func arrowButton(_ systemImage: String, label: String, dx: Double) -> some View {
        Button {
            scene.nudge(by: dx)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 52))
                .frame(width: 140, height: 110)
        }
        .buttonStyle(.bordered)
        .buttonRepeatBehavior(.enabled)
        .disabled(dropping)
        .accessibilityLabel(label)
    }

    private func sayWelcome() {
        let tokens = model.rewards.tokens
        if tokens == 0 {
            model.speaker.say("You need a token to play. Finish some practice to earn one!")
        } else {
            model.speaker.say("You have \(TokenText.count(tokens)). Move the claw over a toy, then press Drop.")
        }
    }

    private func drop() {
        guard !dropping, !scene.isBusy else { return }
        guard let result = model.dropClaw(at: scene.clawX) else {
            sayWelcome()
            return
        }
        dropping = true
        model.speaker.stop()
        scene.play(result) {
            dropping = false
            if let plush = result.caught {
                won = plush
                model.speaker.say("You got the \(plush.name)! It's going in your toy chest.")
            } else {
                scene.show(pile: model.rewards.pile, missStreak: model.rewards.missStreak)
                let more = model.rewards.tokens > 0 ? " The claw will grab better next time." : " Finish some practice to earn more tokens."
                if case .slipped = result.grab {
                    model.speaker.say("Ooh, it slipped out! Try grabbing a toy right in the middle." + more)
                } else {
                    model.speaker.say("Oops, nothing there." + more)
                }
            }
        }
    }

    private func afterWin() {
        scene.show(pile: model.rewards.pile, missStreak: model.rewards.missStreak)
        if model.rewards.tokens == 0 {
            model.speaker.say("That was your last token. Finish some practice to earn more!")
        }
    }
}

/// Shown over the machine when a toy is won: the toy, big, and one button to carry on.
private struct WinCard: View {
    var plush: Plush
    var onDone: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 28) {
                PlushView(plush: plush, size: 260)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared ? 0 : -30))
                Text("You got the \(plush.name)!")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                Button(action: onDone) {
                    Text("Yay!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .padding(.horizontal, 64)
                        .frame(minHeight: 96)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
            }
            .padding(56)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { appeared = true }
        }
    }
}

/// Every toy won, on shelves, with empty spots for the toys still in the machine.
struct ToyChestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24), count: 4)

    var body: some View {
        let collection = model.rewards.collection
        let empty = max(0, PlushCatalog.all.count - collection.count)
        VStack(spacing: 24) {
            HStack(spacing: 20) {
                RoundIconButton(systemImage: "chevron.backward", label: "Back to the claw machine") { dismiss() }
                RoundIconButton(systemImage: "speaker.wave.2.fill", label: "Say it again") { sayWelcome() }
                Spacer()
                Text("Your toys")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Spacer()
                Color.clear.frame(width: 84 * 2 + 20, height: 84)
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(collection, id: \.plush.id) { item in
                        Button {
                            model.speaker.say(item.count > 1 ? "\(item.count) \(item.plush.name)s!" : "The \(item.plush.name)!")
                        } label: {
                            PlushView(plush: item.plush, size: 150)
                                .overlay(alignment: .topTrailing) {
                                    if item.count > 1 {
                                        Text("\(item.count)")
                                            .font(.system(size: 26, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 12)
                                            .background(Color.yellow, in: Capsule())
                                    }
                                }
                                .shelfSpot()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.count > 1 ? "\(item.count) \(item.plush.name)s" : item.plush.name)
                    }
                    ForEach(0..<empty, id: \.self) { _ in
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 4, dash: [12, 8]))
                            .frame(width: 150, height: 150)
                            .shelfSpot()
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(32)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onAppear {
            Log.info(.rewards, "toy chest open toys=\(model.rewards.won.count)")
            sayWelcome()
        }
    }

    private func sayWelcome() {
        let count = model.rewards.won.count
        model.speaker.say(count == 0
            ? "Your toy chest is empty. Win toys in the claw machine!"
            : "Here are your toys! You have \(count).")
    }
}

private extension View {
    /// A toy sitting on a wooden shelf.
    func shelfSpot() -> some View {
        VStack(spacing: 0) {
            self.frame(height: 170, alignment: .bottom)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.brown.opacity(0.7))
                .frame(height: 18)
        }
        .padding(.bottom, 24)
    }
}

/// A toy: its face on a round colored cushion.
struct PlushView: View {
    var plush: Plush
    var size: CGFloat

    var body: some View {
        let (r, g, b) = plush.rgb
        PlushFace(plush: plush, size: size)
            .frame(width: size, height: size)
            .background(Color(red: r, green: g, blue: b), in: Circle())
            .overlay(Circle().stroke(Color(red: r * 0.75, green: g * 0.75, blue: b * 0.75), lineWidth: 4))
            .accessibilityLabel(plush.name)
    }
}

/// A toy's face: its emoji, or a drawing for a toy that has none.
struct PlushFace: View {
    var plush: Plush
    /// The cushion's size; the face fills most of it.
    var size: CGFloat

    var body: some View {
        if plush.isDrawn {
            CapybaraFace(size: size * 0.8)
        } else {
            Text(plush.emoji)
                .font(.system(size: size * 0.68))
        }
    }
}

/// A capybara's face, drawn because there's no capybara emoji: a boxy brown head, a big dark muzzle,
/// small ears and sleepy eyes, with the orange capybaras are famous for balancing on their heads.
struct CapybaraFace: View {
    var size: CGFloat

    var body: some View {
        let s = size
        let fur = Color(red: 0.66, green: 0.46, blue: 0.27)
        let dark = Color(red: 0.42, green: 0.27, blue: 0.15)
        ZStack {
            // Ears.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse().fill(dark).frame(width: s * 0.17, height: s * 0.14)
                    .offset(x: side * s * 0.27, y: -s * 0.24)
            }
            // Head.
            RoundedRectangle(cornerRadius: s * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [fur.opacity(0.8), fur], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.74, height: s * 0.64)
                .offset(y: s * 0.06)
            // Muzzle.
            RoundedRectangle(cornerRadius: s * 0.16, style: .continuous).fill(dark.opacity(0.55))
                .frame(width: s * 0.5, height: s * 0.3)
                .offset(y: s * 0.2)
            // Nostrils.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(dark).frame(width: s * 0.05, height: s * 0.08)
                    .rotationEffect(.degrees(side * -20))
                    .offset(x: side * s * 0.09, y: s * 0.15)
            }
            // Mouth.
            Path { p in
                p.move(to: CGPoint(x: s * 0.44, y: s * 0.79))
                p.addQuadCurve(to: CGPoint(x: s * 0.56, y: s * 0.79), control: CGPoint(x: s * 0.5, y: s * 0.84))
            }
            .stroke(dark, style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
            .frame(width: s, height: s)
            // Sleepy eyes.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule().fill(Color.black.opacity(0.85)).frame(width: s * 0.09, height: s * 0.05)
                    .offset(x: side * s * 0.17, y: -s * 0.03)
            }
            // The orange, with a leaf.
            Circle().fill(Color(red: 0.98, green: 0.6, blue: 0.15))
                .overlay(Circle().stroke(Color(red: 0.85, green: 0.45, blue: 0.1), lineWidth: s * 0.015))
                .frame(width: s * 0.24, height: s * 0.24)
                .offset(y: -s * 0.33)
            Ellipse().fill(Color(red: 0.3, green: 0.65, blue: 0.3))
                .frame(width: s * 0.11, height: s * 0.05)
                .rotationEffect(.degrees(-25))
                .offset(x: s * 0.06, y: -s * 0.46)
        }
        .frame(width: s, height: s)
    }
}

/// A coin with a count: "🪙 3", or "+3" for tokens just earned.
struct TokenBadge: View {
    var count: Int
    var prefix = ""

    var body: some View {
        Label {
            Text("\(prefix)\(count)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        } icon: {
            Image(systemName: "circle.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange, .yellow)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 72)
        .background(Color.yellow.opacity(0.18), in: Capsule())
        .overlay(Capsule().stroke(Color.yellow, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TokenText.count(count))
    }
}
