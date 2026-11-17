import CoreGraphics

/// One sampled point of a pen stroke, in the canvas's coordinate space (y grows downward).
public struct InkPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    /// Seconds since the stroke began.
    public var t: Double
    public var force: Double

    public init(x: Double, y: Double, t: Double = 0, force: Double = 1) {
        self.x = x
        self.y = y
        self.t = t
        self.force = force
    }
}

/// One pen-down to pen-up movement.
public struct InkStroke: Codable, Hashable, Sendable {
    public var points: [InkPoint]

    public init(points: [InkPoint]) {
        self.points = points
    }
}

/// Everything written in one box, plus the size of the box it was written in.
public struct Ink: Codable, Hashable, Sendable {
    public var strokes: [InkStroke]
    public var canvasWidth: Double
    public var canvasHeight: Double

    public init(strokes: [InkStroke], canvasWidth: Double, canvasHeight: Double) {
        self.strokes = strokes
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    public static let empty = Ink(strokes: [], canvasWidth: 0, canvasHeight: 0)

    public var isEmpty: Bool {
        strokes.allSatisfy { $0.points.isEmpty }
    }

    /// Bounding box of all points, or nil when there is no ink.
    public var bounds: CGRect? {
        let points = strokes.flatMap(\.points)
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
