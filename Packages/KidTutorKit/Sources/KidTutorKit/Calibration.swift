/// Decides which characters still need calibration samples.
public struct CalibrationPlan: Sendable {
    public var characters: [String]
    public var samplesPerCharacter: Int

    public init(characters: [String], samplesPerCharacter: Int) {
        self.characters = characters
        self.samplesPerCharacter = samplesPerCharacter
    }

    /// Confirmed samples per character, from any source.
    public func counts(in samples: [InkSample]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for sample in samples {
            if let label = sample.confirmedLabel { counts[label, default: 0] += 1 }
        }
        return counts
    }

    /// Characters still to write, in rounds: every character once, then every character
    /// a second time, and so on, so the child doesn't write the same letter several times in a row.
    public func remaining(given samples: [InkSample]) -> [String] {
        let counts = counts(in: samples)
        var queue: [String] = []
        for round in 0..<max(samplesPerCharacter, 0) {
            for character in characters where counts[character, default: 0] <= round {
                queue.append(character)
            }
        }
        return queue
    }

    /// Characters with fewer confirmed samples than `samplesPerCharacter`, in alphabet order.
    public func charactersNeedingSamples(given samples: [InkSample]) -> [String] {
        let counts = counts(in: samples)
        return characters.filter { counts[$0, default: 0] < samplesPerCharacter }
    }

    public func progress(given samples: [InkSample]) -> (done: Int, total: Int) {
        let total = characters.count * max(samplesPerCharacter, 0)
        return (total - remaining(given: samples).count, total)
    }
}
