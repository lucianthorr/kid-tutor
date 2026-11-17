/// What the child can choose to practice on the home screen.
/// The raw value is also the `subject` field in lesson files.
public enum Subject: String, CaseIterable, Codable, Identifiable, Sendable {
    case reading, writing, spelling, math, logic, mixed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reading: "Reading"
        case .writing: "Writing"
        case .spelling: "Spelling"
        case .math: "Math"
        case .logic: "Puzzles"
        case .mixed: "A bit of everything"
        }
    }

    /// A few words under the title, for grown-ups and early readers.
    public var subtitle: String {
        switch self {
        case .reading: "read it out loud"
        case .writing: "letters and words"
        case .spelling: "fill in the letters"
        case .math: "number facts"
        case .logic: "pick the answer"
        case .mixed: "surprise mix"
        }
    }

    /// Spoken when the home screen appears: "What do you want to practice? Reading, writing, …, or a bit of everything."
    public static var homePrompt: String {
        let names = allCases.map { $0.title.lowercased() }
        let list = names.dropLast().joined(separator: ", ") + ", or " + names.last!
        return "What do you want to practice? " + list.prefix(1).uppercased() + list.dropFirst() + "."
    }
}
