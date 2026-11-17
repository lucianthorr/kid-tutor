/// Which character sets the child is practicing.
public struct Alphabet: Codable, Hashable, Sendable {
    public var lowercase: Bool
    public var uppercase: Bool
    public var digits: Bool

    public init(lowercase: Bool = true, uppercase: Bool = false, digits: Bool = true) {
        self.lowercase = lowercase
        self.uppercase = uppercase
        self.digits = digits
    }

    public static let all = Alphabet(lowercase: true, uppercase: true, digits: true)

    static let lowercaseLetters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
    static let uppercaseLetters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
    static let digitCharacters = "0123456789".map(String.init)

    public var characters: [String] {
        (lowercase ? Self.lowercaseLetters : [])
            + (uppercase ? Self.uppercaseLetters : [])
            + (digits ? Self.digitCharacters : [])
    }
}

public enum CharacterLabel {
    /// A folder-safe name for a character. macOS volumes are usually case-insensitive,
    /// so "a" and "A" can't share a folder namespace when exporting training images.
    public static func folderName(for character: String) -> String {
        guard character.count == 1, let c = character.first else {
            return "other_" + character.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
        }
        if c.isLowercase { return "lower_\(c)" }
        if c.isUppercase { return "upper_\(c)" }
        if c.isNumber { return "digit_\(c)" }
        return "other_" + c.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }

    /// Inverse of `folderName(for:)`; also how a trained classifier's class labels map back to characters.
    public static func character(fromFolderName name: String) -> String? {
        let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[1].count == 1 else { return nil }
        switch parts[0] {
        case "lower", "upper", "digit": return parts[1]
        default: return nil
        }
    }

    /// What the app says to ask for a character. Speech engines read a lone capital as its
    /// letter name, so lowercase letters are spoken as "lowercase B" rather than "b" (which can come out as "buh").
    public static func spokenPrompt(for character: String) -> String {
        "Write \(spokenName(for: character))."
    }

    /// "a lowercase B", "a capital B", "the number 3".
    public static func spokenName(for character: String) -> String {
        guard let c = character.first else { return "" }
        if c.isNumber { return "the number \(character)" }
        if c.isUppercase { return "a capital \(character)" }
        if c.isLowercase { return "a lowercase \(character.uppercased())" }
        return character
    }

    /// Text recognizers read words; this keeps the first character of what they read and
    /// fixes up case and common letter/digit look-alikes, keeping only characters we asked about.
    public static func labels(fromOCRText text: String, among candidates: Set<String>) -> [String] {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return [] }
        let raw = String(first)
        let lookAlikes: [String: [String]] = [
            "0": ["o", "O"], "o": ["0"], "O": ["0"],
            "1": ["l", "I"], "l": ["1", "I"], "I": ["l", "1"], "|": ["l", "1", "I"],
            "5": ["s", "S"], "2": ["z", "Z"],
        ]
        var options = [raw, raw.lowercased(), raw.uppercased()]
        options += lookAlikes[raw] ?? []
        var seen = Set<String>()
        return options.filter { candidates.contains($0) && seen.insert($0).inserted }
    }
}
