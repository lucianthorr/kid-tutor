import CoreGraphics
import Foundation
import ImageIO

/// Draws ink as a black-on-white square image, centered and scaled to fit:
/// the input for text recognition, trained classifiers and thumbnails.
public enum InkRenderer {
    /// The app's Core ML recognizer and the training-image exporter must agree on these.
    public static let trainingImageSize = 128
    public static let trainingPadding = 0.15

    public static func render(
        _ ink: Ink,
        size: Int = trainingImageSize,
        padding: Double = trainingPadding,
        lineWidthFraction: Double = 0.07
    ) -> CGImage? {
        guard let bounds = ink.bounds, size > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        let side = Double(size)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))

        // Ink coordinates grow downward; Core Graphics grows upward.
        context.translateBy(x: 0, y: side)
        context.scaleBy(x: 1, y: -1)

        let available = side * (1 - 2 * padding)
        let extent = max(bounds.width, bounds.height, 1)
        let scale = available / extent
        let offsetX = (side - bounds.width * scale) / 2 - bounds.minX * scale
        let offsetY = (side - bounds.height * scale) / 2 - bounds.minY * scale
        func place(_ p: InkPoint) -> CGPoint {
            CGPoint(x: p.x * scale + offsetX, y: p.y * scale + offsetY)
        }

        let lineWidth = side * lineWidthFraction
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in ink.strokes {
            guard let first = stroke.points.first else { continue }
            if stroke.points.count == 1 {
                let c = place(first)
                context.fillEllipse(in: CGRect(x: c.x - lineWidth / 2, y: c.y - lineWidth / 2, width: lineWidth, height: lineWidth))
                continue
            }
            context.beginPath()
            context.move(to: place(first))
            for p in stroke.points.dropFirst() { context.addLine(to: place(p)) }
            context.strokePath()
        }
        return context.makeImage()
    }

    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
