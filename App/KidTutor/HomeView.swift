import SwiftUI
import KidTutorKit

/// The child's starting screen: six subject tiles and, top right, the grown-ups gear.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Subject] = []
    @State private var showingGrownUps = false
    @State private var showingGearHint = false
    @State private var openedFromArguments = false
    @State private var showingCalibration = false
    @State private var showingRewards = false

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 28) {
                HStack(alignment: .center) {
                    RoundIconButton(systemImage: "speaker.wave.2.fill", label: "Say it again") {
                        model.speaker.say(Subject.homePrompt)
                    }
                    Spacer()
                    Text("What do you want to practice?")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Spacer()
                    GrownUpGear(
                        onTap: {
                            showingGearHint = true
                            model.speaker.say("Ask a grown-up.")
                            Log.info(.app, "gear tapped (needs press and hold)")
                        },
                        onOpen: {
                            showingGearHint = false
                            showingGrownUps = true
                            Log.info(.app, "grown-ups opened")
                        }
                    )
                }

                Grid(horizontalSpacing: 28, verticalSpacing: 28) {
                    GridRow { tiles(Subject.allCases.prefix(3)) }
                    GridRow { tiles(Subject.allCases.dropFirst(3)) }
                }

                RewardsButton(tokens: model.rewards.tokens) {
                    Log.info(.app, "rewards tapped tokens=\(model.rewards.tokens)")
                    showingRewards = true
                }

                if showingGearHint {
                    Text("Grown-ups: press and hold the gear to open settings.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    CalibrationWarning { showingCalibration = true }
                }
            }
            .padding(40)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Subject.self) { subject in
                SubjectScreen(subject: subject)
            }
            .navigationDestination(isPresented: $showingCalibration) {
                CalibrationScreen()
            }
            .navigationDestination(isPresented: $showingRewards) {
                RewardsView()
            }
            .onAppear {
                Log.info(.app, "home appear")
                // `-openSubject spelling` at launch jumps straight to a subject (for screenshots and testing).
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-openGrownUps") || args.contains("-openSettings") || args.contains("-openProgress"), !openedFromArguments {
                    openedFromArguments = true
                    showingGrownUps = true
                    return
                }
                if args.contains("-openRewards"), !openedFromArguments {
                    openedFromArguments = true
                    showingRewards = true
                    return
                }
                if path.isEmpty, let i = args.firstIndex(of: "-openSubject"), i + 1 < args.count,
                   let subject = Subject(rawValue: args[i + 1]), !openedFromArguments {
                    openedFromArguments = true
                    path.append(subject)
                    return
                }
                model.speaker.say(Subject.homePrompt)
            }
        }
        .fullScreenCover(isPresented: $showingGrownUps) {
            GrownUpView()
        }
    }

    private func tiles(_ subjects: some Collection<Subject>) -> some View {
        ForEach(Array(subjects)) { subject in
            Button {
                Log.info(.app, "subject \(subject.rawValue)")
                model.speaker.say(subject.title + "!")
                path.append(subject)
            } label: {
                SubjectTile(subject: subject)
            }
            .buttonStyle(.plain)
        }
    }
}

struct SubjectTile: View {
    var subject: Subject

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(spacing: 14) {
            Image(systemName: subject.symbol)
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(subject.tint)
                .frame(height: 100)
            Text(subject.title)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(subject.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(subject == .mixed ? Color.yellow.opacity(0.15) : Color(.systemBackground), in: shape)
        .overlay(shape.stroke(subject == .mixed ? Color.yellow : Color.secondary.opacity(0.35), lineWidth: 3))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

extension Subject {
    var symbol: String {
        switch self {
        case .reading: "book.fill"
        case .writing: "pencil.and.scribble"
        case .spelling: "textformat.abc"
        case .math: "plus.forwardslash.minus"
        case .logic: "puzzlepiece.fill"
        case .mixed: "shuffle"
        }
    }

    var tint: Color {
        switch self {
        case .reading: .blue
        case .writing: .orange
        case .spelling: .purple
        case .math: .green
        case .logic: .teal
        case .mixed: .yellow
        }
    }
}

/// For grown-ups: shown while some letters or numbers have too few handwriting samples, because
/// Spelling and Math then misjudge answers or accept them unchecked. Tapping it opens handwriting setup.
struct CalibrationWarning: View {
    @Environment(AppModel.self) private var model
    var onOpen: () -> Void

    var body: some View {
        let missing = model.charactersNeedingCalibration
        if missing.isEmpty {
            Text(" ").font(.title3)
        } else {
            Button(action: onOpen) {
                Label {
                    Text("Handwriting setup: \(missing.count) of \(model.characters.count) letters and numbers need more samples, so answers can't be checked well yet. Tap to write them now.")
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.title3)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityHint("Opens handwriting setup")
        }
    }
}

/// The way to the claw machine, with how many tokens there are to spend.
struct RewardsButton: View {
    var tokens: Int
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Text("🧸")
                    .font(.system(size: 56))
                Text("Rewards")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                TokenBadge(count: tokens)
            }
            .padding(.horizontal, 36)
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.yellow, lineWidth: 4))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rewards, \(TokenText.count(tokens))")
    }
}

/// Opens settings only on a press and hold, so a child tapping around doesn't land in them.
struct GrownUpGear: View {
    var onTap: () -> Void
    var onOpen: () -> Void

    var body: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 36))
            .foregroundStyle(.secondary)
            .frame(width: 84, height: 84)
            .background(Color.secondary.opacity(0.12), in: Circle())
            .contentShape(Circle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 1.5, perform: onOpen)
            .accessibilityLabel("Settings for grown-ups")
            .accessibilityHint("Press and hold to open")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Open settings", onOpen)
    }
}

struct RoundIconButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .frame(width: 84, height: 84)
                .background(Color.secondary.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel(label)
    }
}

/// Frame for every subject: a big Home button and the subject name, then the activity.
struct SubjectScreen: View {
    var subject: Subject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                RoundIconButton(systemImage: "house.fill", label: "Home") { dismiss() }
                Text(subject.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(subject.tint)
                Spacer()
            }
            .padding([.horizontal, .top], 32)

            switch subject {
            case .writing:
                WritingView()
            case .spelling:
                SpellingView()
            case .math:
                MathView()
            case .reading:
                ReadingView()
            case .logic:
                PuzzleView()
            default:
                ComingSoonView(subject: subject)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}

/// Handwriting setup opened from the home screen's note: the child copies each character that
/// still needs samples. The same screen is the grown-up area's Calibrate tab.
struct CalibrationScreen: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                RoundIconButton(systemImage: "house.fill", label: "Home") { dismiss() }
                Text("Handwriting setup")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Subject.writing.tint)
                Spacer()
            }
            .padding([.horizontal, .top], 32)
            CalibrationView()
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
    }
}

struct ComingSoonView: View {
    @Environment(AppModel.self) private var model
    var subject: Subject

    var body: some View {
        ContentUnavailableView {
            Label("\(subject.title) is coming soon!", systemImage: subject.symbol)
                .font(.system(size: 40, weight: .bold, design: .rounded))
        } description: {
            Text("Tap the house to go back.")
                .font(.title2)
        }
        .onAppear { model.speaker.say("\(subject.title) is coming soon!") }
    }
}

/// Grown-up area: the Phase 0 handwriting tools and settings.
struct GrownUpView: View {
    enum Tab { case settings, test, results, calibrate }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab = Tab.settings

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $tab) {
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
                TestView()
                    .tabItem { Label("Test", systemImage: "checkmark.circle") }
                    .tag(Tab.test)
                ResultsView()
                    .tabItem { Label("Results", systemImage: "chart.bar") }
                    .tag(Tab.results)
                CalibrationView()
                    .tabItem { Label("Calibrate", systemImage: "pencil.and.scribble") }
                    .tag(Tab.calibrate)
            }
            .onAppear {
                // Settings first, unless handwriting still needs samples. `-openSettings` and `-openProgress`
                // at launch always start on Settings (for screenshots and testing).
                let args = ProcessInfo.processInfo.arguments
                let forced = args.contains("-openSettings") || args.contains("-openProgress")
                tab = !forced && !model.charactersNeedingCalibration.isEmpty ? .calibrate : .settings
                Log.info(.app, "grown-ups opened on \(tab)")
            }
            Button("Done") {
                Log.info(.app, "grown-ups closed")
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(20)
        }
    }
}
