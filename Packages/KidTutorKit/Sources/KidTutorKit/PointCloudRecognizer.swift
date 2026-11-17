/// The $P point-cloud recognizer (Vatavu, Anthony & Wobbrock, 2012), trained on the child's own samples.
///
/// $P ignores stroke order and direction, which suits children: they rarely form a letter the same way twice.
/// It keeps orientation, so mirror pairs like b/d and p/q stay distinct.
/// It normalizes size and position, so shapes that differ only by size or placement (o/O, c/C, s/S) look alike;
/// limit `candidates` to the expected character set to avoid those mix-ups.
public struct PointCloudRecognizer: CharacterRecognizer {
    public let id = "pdollar"
    public let name = "Personal ($P)"

    public static let pointCount = 32

    struct CloudPoint: Hashable, Sendable {
        var x: Double
        var y: Double
        var strokeID: Int
    }

    struct Template: Sendable {
        var label: String
        var points: [CloudPoint]
    }

    let templates: [Template]

    /// Uses every sample that has a confirmed label as a template.
    public init(samples: [InkSample]) {
        templates = samples.compactMap { sample in
            guard let label = sample.confirmedLabel, let points = Self.normalize(sample.ink) else { return nil }
            return Template(label: label, points: points)
        }
    }

    public var templateCount: Int { templates.count }

    public var labels: Set<String> { Set(templates.map(\.label)) }

    /// How many examples of `label` the recognizer has.
    public func templateCount(for label: String) -> Int {
        templates.reduce(0) { $0 + ($1.label == label ? 1 : 0) }
    }

    public func recognize(_ ink: Ink, among candidates: Set<String>) async -> [RecognitionCandidate] {
        classify(ink, among: candidates)
    }

    /// Best matching labels first. Each label's score comes from its closest template.
    public func classify(_ ink: Ink, among candidates: Set<String>? = nil, limit: Int = 3) -> [RecognitionCandidate] {
        guard let points = Self.normalize(ink) else { return [] }
        var best: [String: Double] = [:]
        for template in templates where candidates?.contains(template.label) ?? true {
            let distance = Self.greedyCloudMatch(points, template.points)
            best[template.label] = min(best[template.label] ?? .infinity, distance)
        }
        return best
            .sorted { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(limit)
            .map { RecognitionCandidate(label: $0.key, score: 1 / (1 + $0.value)) }
    }

    // MARK: - Normalization

    static func normalize(_ ink: Ink) -> [CloudPoint]? {
        guard let bounds = ink.bounds else { return nil }
        let diagonal = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
        // Dots (the top of i and j) have no length, so $P would give them no points at all.
        // Stretch each one into a short tick so it counts.
        let tick = max(diagonal * 0.05, 1)
        var points: [CloudPoint] = []
        for (strokeID, stroke) in ink.strokes.enumerated() where !stroke.points.isEmpty {
            var strokePoints = stroke.points.map { CloudPoint(x: $0.x, y: $0.y, strokeID: strokeID) }
            if pathLength(strokePoints) < tick, let first = strokePoints.first {
                strokePoints = [
                    CloudPoint(x: first.x, y: first.y - tick / 2, strokeID: strokeID),
                    CloudPoint(x: first.x, y: first.y + tick / 2, strokeID: strokeID),
                ]
            }
            points += strokePoints
        }
        guard !points.isEmpty else { return nil }
        return translateToOrigin(scale(resample(points, n: pointCount)))
    }

    static func resample(_ input: [CloudPoint], n: Int) -> [CloudPoint] {
        let interval = pathLength(input) / Double(n - 1)
        guard interval > 0 else { return Array(repeating: input[0], count: n) }
        var points = input
        var result = [points[0]]
        var accumulated = 0.0
        var i = 1
        while i < points.count {
            let a = points[i - 1], b = points[i]
            if a.strokeID == b.strokeID {
                let d = distance(a, b)
                if accumulated + d >= interval, d > 0 {
                    let r = (interval - accumulated) / d
                    let q = CloudPoint(x: a.x + r * (b.x - a.x), y: a.y + r * (b.y - a.y), strokeID: b.strokeID)
                    result.append(q)
                    points.insert(q, at: i)
                    accumulated = 0
                } else {
                    accumulated += d
                }
            }
            i += 1
        }
        // Floating-point rounding can leave the last point off, or add one too many.
        while result.count < n { result.append(points[points.count - 1]) }
        return Array(result.prefix(n))
    }

    static func scale(_ points: [CloudPoint]) -> [CloudPoint] {
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min()!, minY = ys.min()!
        let size = max(xs.max()! - minX, ys.max()! - minY)
        let s = size > 0 ? size : 1
        return points.map { CloudPoint(x: ($0.x - minX) / s, y: ($0.y - minY) / s, strokeID: $0.strokeID) }
    }

    static func translateToOrigin(_ points: [CloudPoint]) -> [CloudPoint] {
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        return points.map { CloudPoint(x: $0.x - cx, y: $0.y - cy, strokeID: $0.strokeID) }
    }

    // MARK: - Matching

    static func greedyCloudMatch(_ points: [CloudPoint], _ template: [CloudPoint]) -> Double {
        let n = points.count
        let step = max(1, Int(Double(n).squareRoot()))  // n^(1 - ε) with ε = 0.5
        var best = Double.infinity
        for start in stride(from: 0, to: n, by: step) {
            best = min(best, cloudDistance(points, template, start: start), cloudDistance(template, points, start: start))
        }
        return best
    }

    static func cloudDistance(_ a: [CloudPoint], _ b: [CloudPoint], start: Int) -> Double {
        let n = a.count
        var matched = [Bool](repeating: false, count: n)
        var sum = 0.0
        var i = start
        repeat {
            var index = -1
            var nearest = Double.infinity
            for j in 0..<n where !matched[j] {
                let d = distance(a[i], b[j])
                if d < nearest {
                    nearest = d
                    index = j
                }
            }
            matched[index] = true
            let weight = 1 - Double((i - start + n) % n) / Double(n)
            sum += weight * nearest
            i = (i + 1) % n
        } while i != start
        return sum
    }

    static func pathLength(_ points: [CloudPoint]) -> Double {
        var length = 0.0
        for i in points.indices.dropFirst() where points[i].strokeID == points[i - 1].strokeID {
            length += distance(points[i - 1], points[i])
        }
        return length
    }

    static func distance(_ a: CloudPoint, _ b: CloudPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
