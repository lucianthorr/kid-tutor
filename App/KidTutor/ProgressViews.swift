import SwiftUI
import KidTutorKit

/// Settings › Progress: each subject's deck at a glance, Anki style. Tapping a subject opens its page.
struct ProgressSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false

    var body: some View {
        Section {
            ForEach(Subject.withDecks) { subject in
                let deck = model.deck(for: subject)
                NavigationLink {
                    DeckPage(subject: subject)
                } label: {
                    HStack(spacing: 20) {
                        Label(subject.title, systemImage: subject.symbol)
                            .frame(width: 150, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            PileBar(deck: deck)
                            Text(DeckPile.summaryOrder.map { "\(deck.count($0)) \($0.title.lowercased())" }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            NavigationLink {
                PuzzleProgressPage()
            } label: {
                HStack(spacing: 20) {
                    Label(Subject.logic.title, systemImage: Subject.logic.symbol)
                        .frame(width: 150, alignment: .leading)
                    Text(PuzzleKind.allCases.map { "\($0.title.lowercased()) \(model.puzzleProgress[$0].level)/\($0.maxLevel)" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Reset all progress", role: .destructive) { confirmingReset = true }
                .confirmationDialog("Reset progress in every subject?", isPresented: $confirmingReset, titleVisibility: .visible) {
                    Button("Reset all progress", role: .destructive) { model.resetAllProgress() }
                } message: {
                    Text(ResetText.message("Every card goes back to to do and puzzles back to level 1"))
                }
        } header: {
            Text("Progress")
        } footer: {
            Text("Like an Anki deck: to do is not practiced yet, in progress is practiced but not learned, learned is mastered. A hint can move a learned card back.")
        }
    }
}

/// One subject's deck: how many cards in each pile, and the cards themselves.
struct DeckPage: View {
    @Environment(AppModel.self) private var model
    var subject: Subject
    @State private var pile = DeckPile.inProgress
    @State private var confirmingReset = false

    var body: some View {
        let deck = model.deck(for: subject)
        let cards = deck.cards(in: pile)
        List {
            Section {
                HStack(spacing: 14) {
                    CountTile(title: "In the deck", count: deck.total, color: nil)
                    ForEach(DeckPile.summaryOrder) { CountTile(title: $0.title, count: deck.count($0), color: $0.color) }
                }
                PileBar(deck: deck, height: 18)
                Picker("Pile", selection: $pile) {
                    ForEach(DeckPile.allCases) { Text("\($0.title) (\(deck.count($0)))").tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(pile.explanation(for: subject))
            }
            .listRowSeparator(.hidden)

            if cards.isEmpty {
                Section { Text("Nothing here yet.").foregroundStyle(.secondary) }
            } else if deck.groups.count > 1 {
                ForEach(deck.groups, id: \.self) { group in
                    let inGroup = cards.filter { $0.group == group }
                    if !inGroup.isEmpty {
                        Section("\(group) (\(inGroup.count))") { ForEach(inGroup) { DeckCardRow(card: $0) } }
                    }
                }
            } else {
                Section { ForEach(cards) { DeckCardRow(card: $0) } }
            }

            Section {
                Button("Reset \(subject.title) progress", role: .destructive) { confirmingReset = true }
                    .disabled(deck.count(.toDo) == deck.total)
            }
        }
        .navigationTitle(subject.title)
        .confirmationDialog("Reset \(subject.title) progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset \(subject.title) progress", role: .destructive) {
                model.resetProgress(subject)
                pile = .toDo
            }
        } message: {
            Text(ResetText.message("All \(deck.total) cards go back to to do"))
        }
        .onAppear {
            // Open on the pile that has something, in progress first.
            if deck.count(.inProgress) == 0 { pile = deck.count(.learned) > 0 ? .learned : .toDo }
        }
    }
}

/// Puzzles have no deck (each puzzle is made fresh), so this shows each kind's level instead.
struct PuzzleProgressPage: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingReset = false

    var body: some View {
        let progress = model.puzzleProgress
        let available = PuzzlePlanner.availableKinds(progress)
        List {
            Section {
                ForEach(PuzzleKind.allCases, id: \.self) { kind in
                    let skill = progress[kind]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(kind.title).font(.headline)
                            Spacer()
                            Text("Level \(skill.level) of \(kind.maxLevel)").monospacedDigit()
                        }
                        ProgressView(value: Double(skill.level), total: Double(kind.maxLevel))
                            .tint(.teal)
                        Text(available.contains(kind)
                             ? "\(skill.solved) solved · \(skill.streak) first tries in a row"
                             : "Starts once What comes next reaches level \(PuzzlePlanner.gridUnlockLevel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("Puzzles have no deck: each one is made fresh at the child's level. A kind goes up a level after \(PuzzleSkill.upAfter) first tries in a row, and down after \(PuzzleSkill.downAfter) puzzles in a row that needed a retry or Help.")
            }

            Section {
                Button("Reset Puzzles progress", role: .destructive) { confirmingReset = true }
                    .disabled(progress == PuzzleProgress())
            }
        }
        .navigationTitle(Subject.logic.title)
        .confirmationDialog("Reset Puzzles progress?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset Puzzles progress", role: .destructive) { model.resetProgress(.logic) }
        } message: {
            Text(ResetText.message("Every kind goes back to level 1"))
        }
    }
}

private struct DeckCardRow: View {
    var card: DeckCard

    var body: some View {
        HStack(spacing: 16) {
            Text(card.text)
                .font(.title3.weight(.semibold))
                .frame(minWidth: 110, alignment: .leading)
            Text(card.detail)
                .foregroundStyle(.secondary)
            Spacer()
            if let date = card.lastPracticed {
                Text(date, format: .relative(presentation: .named))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CountTile: View {
    var title: String
    var count: Int
    var color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 10, height: 10) }
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(count)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Learned, then in progress, then to do, as one bar.
private struct PileBar: View {
    var deck: Deck
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(DeckPile.summaryOrder) { pile in
                    pile.color.frame(width: geo.size.width * CGFloat(deck.count(pile)) / CGFloat(max(deck.total, 1)))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

private enum ResetText {
    static func message(_ what: String) -> String {
        "\(what). Tokens and won toys stay. A copy of the old progress is kept in On My iPad › Kid Tutor › Progress › Backups."
    }
}

extension Subject {
    /// Subjects whose cards make a deck (Puzzles are made fresh each time).
    static let withDecks: [Subject] = [.reading, .writing, .spelling, .math]
}

extension DeckPile {
    /// Learned first, as the bar fills from the left.
    static let summaryOrder: [DeckPile] = [.learned, .inProgress, .toDo]

    var color: Color {
        switch self {
        case .learned: .green
        case .inProgress: .orange
        case .toDo: Color(.systemGray4)
        }
    }

    func explanation(for subject: Subject) -> String {
        switch self {
        case .toDo: "Not practiced yet, in the order they'll be taught."
        case .inProgress: "Practiced but not learned yet, hardest first."
        case .learned:
            switch subject {
            case .reading, .math: "Three more first-try answers than hints. They still come back now and then for review."
            default: "Two first tries in a row at the top level (from memory). They still come back now and then for review."
            }
        }
    }
}

extension AppModel {
    func deck(for subject: Subject) -> Deck {
        switch subject {
        case .reading: DeckReport.reading(progress: readingProgress)
        case .writing: DeckReport.writing(progress: writingProgress)
        case .spelling: DeckReport.spelling(progress: spellingProgress)
        case .math: DeckReport.math(mathProgress)
        case .logic, .mixed: Deck(cards: [])
        }
    }
}
