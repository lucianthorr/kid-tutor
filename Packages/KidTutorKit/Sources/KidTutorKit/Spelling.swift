import Foundation

/// A word to spell, with a sentence that shows how it's used.
public struct SpellingWord: Codable, Hashable, Identifiable, Sendable {
    public var word: String
    public var sentence: String

    public init(_ word: String, _ sentence: String) {
        self.word = word
        self.sentence = sentence
    }

    public var id: String { word }
    public var letters: [String] { word.lowercased().map(String.init) }

    /// "Spell friend. My friend came over to play. Friend."
    public var prompt: String { "Spell \(word). \(sentence) \(word.prefix(1).uppercased() + word.dropFirst())." }

    /// Letter names, capitalized so speech says "F" rather than the sound: "F, R, I, E, N, D."
    public var spelledOut: String { letters.map { $0.uppercased() }.joined(separator: ", ") + "." }
}

/// Built-in words until lessons come from the iCloud lesson folder. Common first-grade
/// sight words and short words, roughly easiest first: short-vowel words, sight words, then words with
/// sh, ch, blends and long vowels. "school", "friend" and "because" stay last as the hardest.
public enum StarterWords {
    public static let spelling: [SpellingWord] = [
        .init("cat", "The cat is asleep."),
        .init("dog", "The dog wags its tail."),
        .init("sun", "The sun is hot."),
        .init("red", "My hat is red."),
        .init("big", "That is a big truck."),
        .init("run", "I can run fast."),
        .init("can", "I can jump high."),
        .init("see", "I see a bird."),
        .init("the", "The ball is round."),
        .init("and", "Mom and Dad are home."),
        .init("play", "Let's play outside."),
        .init("look", "Look at the moon."),
        .init("said", "She said hello."),
        .init("was", "It was a sunny day."),
        .init("they", "They are my friends."),
        .init("have", "I have a blue cup."),
        .init("come", "Come and sit with me."),
        .init("what", "What is your name?"),
        .init("where", "Where is my shoe?"),
        .init("little", "The little bug is green."),
        .init("hat", "I wear a hat in the sun."),
        .init("map", "We look at the map."),
        .init("bag", "My lunch is in my bag."),
        .init("fan", "The fan keeps us cool."),
        .init("man", "The man drives a bus."),
        .init("bed", "I sleep in my bed."),
        .init("hen", "The hen lays an egg."),
        .init("pen", "I write with a pen."),
        .init("ten", "I have ten toes."),
        .init("wet", "The grass is wet."),
        .init("leg", "The frog has long legs."),
        .init("pig", "The pig rolls in the mud."),
        .init("sit", "Please sit down."),
        .init("six", "A bug has six legs."),
        .init("win", "I hope we win the game."),
        .init("lip", "I bit my lip."),
        .init("hot", "The soup is hot."),
        .init("top", "The cat sat on top of the box."),
        .init("mop", "Dad cleans the floor with a mop."),
        .init("box", "The toy is in the box."),
        .init("fox", "The fox has a bushy tail."),
        .init("pot", "The plant is in a pot."),
        .init("bug", "A bug is on the leaf."),
        .init("cup", "I drink milk from a cup."),
        .init("bus", "We ride the bus to school."),
        .init("mud", "My boots are covered in mud."),
        .init("hug", "Give me a big hug."),
        .init("fun", "The park is fun."),
        .init("nut", "The squirrel eats a nut."),
        .init("me", "Come and play with me."),
        .init("we", "We like to sing."),
        .init("he", "He is my brother."),
        .init("she", "She has a red bike."),
        .init("go", "It is time to go home."),
        .init("no", "No, thank you."),
        .init("my", "This is my book."),
        .init("you", "I love you."),
        .init("not", "The cat is not sleepy."),
        .init("but", "I am small but strong."),
        .init("get", "Can you get the ball?"),
        .init("yes", "Yes, I can help."),
        .init("all", "We ate all the grapes."),
        .init("are", "We are best friends."),
        .init("for", "This gift is for you."),
        .init("of", "I want a glass of water."),
        .init("one", "I have one nose."),
        .init("two", "A bike has two wheels."),
        .init("like", "I like apples."),
        .init("make", "Let's make a cake."),
        .init("ride", "I can ride my bike."),
        .init("went", "We went to the zoo."),
        .init("with", "Come with me."),
        .init("this", "This is my cat."),
        .init("that", "That dog is fast."),
        .init("then", "Eat your lunch, then play."),
        .init("them", "I gave them a snack."),
        .init("when", "When is lunch?"),
        .init("who", "Who is at the door?"),
        .init("why", "Why is the sky blue?"),
        .init("here", "Come here, please."),
        .init("there", "The ball is over there."),
        .init("from", "This card is from Grandma."),
        .init("good", "That was a good book."),
        .init("down", "The ball rolled down the hill."),
        .init("into", "The frog jumped into the pond."),
        .init("over", "The cow jumped over the moon."),
        .init("under", "The cat is under the bed."),
        .init("after", "We play after school."),
        .init("again", "Let's sing it again."),
        .init("could", "Could you help me?"),
        .init("would", "Would you like a snack?"),
        .init("every", "I brush my teeth every day."),
        .init("going", "We are going to the park."),
        .init("know", "I know the answer."),
        .init("please", "Please pass the bread."),
        .init("thank", "Thank you for the gift."),
        .init("want", "I want to play."),
        .init("were", "We were at the beach."),
        .init("your", "Is this your hat?"),
        .init("many", "How many fish do you see?"),
        .init("some", "I want some juice."),
        .init("very", "It is very cold."),
        .init("fish", "The fish swims fast."),
        .init("ship", "The ship sails on the sea."),
        .init("shop", "We shop for food."),
        .init("chin", "The ball hit my chin."),
        .init("chip", "I ate a potato chip."),
        .init("duck", "The duck says quack."),
        .init("frog", "The frog can hop."),
        .init("stop", "Stop at the red light."),
        .init("jump", "I can jump rope."),
        .init("hand", "Raise your hand."),
        .init("milk", "I drink milk at lunch."),
        .init("tree", "The bird is in the tree."),
        .init("green", "Grass is green."),
        .init("rain", "The rain makes puddles."),
        .init("snow", "We play in the snow."),
        .init("night", "The moon comes out at night."),
        .init("house", "My house has a red door."),
        .init("happy", "The puppy is happy."),
        .init("school", "We read books at school."),
        .init("friend", "My friend came over to play."),
        .init("because", "I smiled because I was happy."),
    ]
}

/// Which letters are blank at each level: level n blanks n letters, chosen at random, until the
/// whole word is blank and the child writes it from memory in one wide box.
public enum SpellingScaffold {
    /// The whole-word level for a word.
    public static func topLevel(for word: String) -> Int { max(word.count, 1) }

    /// First tries in a row at a level before the word moves up.
    public static let passesToLevelUp = 2

    /// Indexes of the letters the child writes, `level` of them at random positions.
    public static func blanks(in word: String, level: Int) -> [Int] {
        var rng = SystemRandomNumberGenerator()
        return blanks(in: word, level: level, using: &rng)
    }

    public static func blanks(in word: String, level: Int, using rng: inout some RandomNumberGenerator) -> [Int] {
        let n = word.count
        let count = min(max(level, 1), n)
        return Array((0..<n).shuffled(using: &rng).prefix(count)).sorted()
    }

    /// At the top level the whole word is written in one wide box instead of a box per letter.
    public static func isWholeWord(_ word: String, level: Int) -> Bool {
        level >= topLevel(for: word)
    }
}

/// How the child is doing on one item with levels: a spelling word, a letter or word to write.
public struct WordProgress: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        /// Every letter right on the first try.
        case firstTry
        /// Right after fixing at least one letter.
        case retried
        /// Needed a shown letter (help, or a second miss) to finish.
        case hinted
    }

    /// First tries in a row at the top level that make an item mastered.
    public static let passesToMaster = 2

    public var level = 1
    public var attempts = 0
    /// First tries in a row at the current level.
    public var passes = 0
    public private(set) var isMastered = false
    public var lastPracticed: Date?
    /// Letters missed in this item, with how often.
    public var missedLetters: [String: Int] = [:]

    public init() {}

    /// A first try counts toward the next level (`passesToLevelUp` in a row move up); a retry
    /// starts the count again; needing a hint moves down a level. At `topLevel`, `passesToMaster`
    /// first tries in a row master the item, and only a hint takes that away.
    public mutating func record(
        _ outcome: Outcome,
        missed: [String],
        topLevel: Int,
        passesToLevelUp: Int,
        at date: Date = Date()
    ) {
        attempts += 1
        lastPracticed = date
        for letter in missed { missedLetters[letter, default: 0] += 1 }
        level = min(level, topLevel)
        switch outcome {
        case .firstTry:
            passes += 1
            if level >= topLevel {
                if passes >= Self.passesToMaster { isMastered = true }
            } else if passes >= passesToLevelUp {
                level += 1
                passes = 0
            }
        case .retried:
            passes = 0
        case .hinted:
            level = max(1, level - 1)
            passes = 0
            isMastered = false
        }
    }

    enum CodingKeys: String, CodingKey {
        case level, attempts, passes, isMastered, lastPracticed, missedLetters
        /// Before levels counted blanks: first tries at the old whole-word level.
        case topLevelPasses
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 1
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        let oldTopPasses = try c.decodeIfPresent(Int.self, forKey: .topLevelPasses) ?? 0
        passes = try c.decodeIfPresent(Int.self, forKey: .passes) ?? oldTopPasses
        isMastered = try c.decodeIfPresent(Bool.self, forKey: .isMastered) ?? (oldTopPasses >= Self.passesToMaster)
        lastPracticed = try c.decodeIfPresent(Date.self, forKey: .lastPracticed)
        missedLetters = try c.decodeIfPresent([String: Int].self, forKey: .missedLetters) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(level, forKey: .level)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(passes, forKey: .passes)
        try c.encode(isMastered, forKey: .isMastered)
        try c.encodeIfPresent(lastPracticed, forKey: .lastPracticed)
        try c.encode(missedLetters, forKey: .missedLetters)
    }
}

/// Progress on every spelling word, saved as `Progress/spelling.json`.
public struct SpellingProgress: JSONFile, Hashable {
    public var words: [String: WordProgress] = [:]

    public init() {}

    public subscript(word: String) -> WordProgress {
        get { words[word] ?? WordProgress() }
        set { words[word] = newValue }
    }
}

/// Picks the words for one spelling session. A stand-in for FSRS scheduling, which comes with the core phase.
public enum SpellingPlanner {
    public static func sessionWords(
        from words: [SpellingWord],
        progress: SpellingProgress,
        count: Int = 5,
        maxLearning: Int = 6
    ) -> [SpellingWord] {
        let keys = LearningPlanner.pick(words.map(\.word), progress: progress.words, count: count, maxLearning: maxLearning)
        return keys.compactMap { key in words.first { $0.word == key } }
    }
}

/// Chooses items for a session from a list in teaching order.
public enum LearningPlanner {
    /// Items being learned come first (least recently practiced first), then new items in order while
    /// fewer than `maxLearning` are being learned, then mastered items for review.
    public static func pick(
        _ keys: [String],
        progress: [String: WordProgress],
        count: Int,
        maxLearning: Int
    ) -> [String] {
        guard count > 0 else { return [] }
        func last(_ key: String) -> Date { progress[key]?.lastPracticed ?? .distantPast }
        let started = keys.filter { progress[$0] != nil }
        let learning = started.filter { !(progress[$0]?.isMastered ?? false) }.sorted { last($0) < last($1) }
        var picked = Array(learning.prefix(count))

        let newAllowed = max(0, maxLearning - learning.count)
        let fresh = keys.filter { progress[$0] == nil }
        picked += fresh.prefix(min(newAllowed, count - picked.count))

        if picked.count < count {
            let review = started.filter { progress[$0]?.isMastered ?? false }.sorted { last($0) < last($1) }
            picked += review.prefix(count - picked.count)
        }
        return picked
    }
}

/// Decides whether a handwritten letter is the one expected.
public enum LetterCheck {
    public enum Verdict: String, Sendable {
        case correct
        case incorrect
        /// The recognizer has too few examples of this letter to judge, so the attempt is accepted
        /// (but not kept as an example; calibration adds examples).
        case unverified
    }

    /// Correct when the expected letter is the top guess, or among the top three and nearly as likely.
    /// Lenient on purpose: a misread that blocks a child is worse than a missed mistake.
    public static func verdict(
        expected: String,
        candidates: [RecognitionCandidate],
        examplesOfExpected: Int,
        minimumExamples: Int = 2,
        closeness: Double = 0.8
    ) -> Verdict {
        guard examplesOfExpected >= minimumExamples else { return .unverified }
        guard let top = candidates.first else { return .incorrect }
        if top.label == expected { return .correct }
        if let match = candidates.prefix(3).first(where: { $0.label == expected }), match.score >= top.score * closeness {
            return .correct
        }
        return .incorrect
    }
}
