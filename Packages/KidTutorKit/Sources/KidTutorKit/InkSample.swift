import Foundation

/// One character the child wrote, kept for calibration, testing and training.
public struct InkSample: Codable, Identifiable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Written while copying a shown character; the label is trusted.
        case calibration
        /// Written during a recognition test; a grown-up confirmed the label.
        case test
        /// Written while practicing (spelling, writing); labeled with the expected letter when accepted.
        case practice
    }

    public var id: UUID
    public var createdAt: Date
    public var source: Source
    public var ink: Ink
    /// The character the child was asked to write.
    public var expected: String
    /// What the child actually wrote, as confirmed by a grown-up. Nil until reviewed.
    public var confirmedLabel: String?
    /// Top guess from each recognizer, keyed by recognizer id, recorded before the sample
    /// was added to the training set. An empty string means the recognizer had no guess.
    public var recognized: [String: String]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        source: Source,
        ink: Ink,
        expected: String,
        confirmedLabel: String?,
        recognized: [String: String] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.ink = ink
        self.expected = expected
        self.confirmedLabel = confirmedLabel
        self.recognized = recognized
    }
}

/// Saves samples as one JSON file. The app's Documents folder is visible in the Files app,
/// so the file can be copied to a Mac for training without any network.
public struct SampleStore: Sendable {
    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent("samples.json")
    }

    public func load() throws -> [InkSample] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try Self.decode(Data(contentsOf: fileURL))
    }

    public func save(_ samples: [InkSample]) throws {
        try Self.encode(samples).write(to: fileURL, options: .atomic)
    }

    public static func decode(_ data: Data) throws -> [InkSample] {
        try JSONDecoder().decode([InkSample].self, from: data)
    }

    public static func encode(_ samples: [InkSample]) throws -> Data {
        // Dates use the default encoding (seconds since 2001 as a Double), which round-trips exactly.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(samples)
    }
}
