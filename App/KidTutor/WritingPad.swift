import PencilKit
import SwiftUI
import KidTutorKit

/// One writing box on primary-school ruled lines (square by default).
/// Calls `onPause` when the pencil has been lifted for the configured time.
struct WritingPad: View {
    @Environment(AppModel.self) private var model
    @Binding var ink: Ink
    var clearToken: Int
    /// Width ÷ height.
    var aspectRatio: CGFloat = 1
    var cornerRadius: CGFloat = 28
    var border: Color = Color.secondary.opacity(0.4)
    var borderWidth: CGFloat = 2
    /// A faded letter to trace over, for hints.
    var traceText: String?
    var onPause: () -> Void

    @State private var pauseTask: Task<Void, Never>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(Color.white)
            WritingGuides()
            if let traceText {
                GuideLetter(text: traceText, color: .gray.opacity(0.3))
            }
            CharacterCanvas(
                allowFingerInput: model.settings.allowFingerInput,
                clearToken: clearToken,
                onBegin: {
                    pauseTask?.cancel()
                    Log.debug(.ink, "pencil down")
                },
                onChange: { newInk in
                    ink = newInk
                    schedulePause()
                }
            )
        }
        .clipShape(shape)
        .overlay(shape.stroke(border, lineWidth: borderWidth))
        .aspectRatio(aspectRatio, contentMode: .fit)
        .onChange(of: clearToken) {
            pauseTask?.cancel()
        }
        .onDisappear {
            pauseTask?.cancel()
        }
    }

    private func schedulePause() {
        pauseTask?.cancel()
        guard model.settings.autoFinish, !ink.isEmpty else { return }
        let delay = model.settings.pauseSeconds
        pauseTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            Log.debug(.ink, "pause \(delay)s -> finished: \(ink.logSummary)")
            onPause()
        }
    }
}

/// A letter drawn on the writing guides the way a child is taught to write it: sitting on the baseline,
/// lowercase letters (a, u, n…) reaching the dashed midline, capitals and digits reaching the top line.
struct GuideLetter: View {
    var text: String
    var color: Color = .primary

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            // WritingGuides: top line at 20%, midline at 45%, baseline at 70% of the height.
            let tall = text.first.map { $0.isUppercase || $0.isNumber } ?? false
            let size = tall
                ? h * (0.70 - 0.20) / KidFont.metrics.capHeight
                : h * (0.70 - 0.45) / KidFont.metrics.xHeight
            Text(text)
                .font(KidFont.font(size: size))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(color)
                .alignmentGuide(.bottom) { $0[.lastTextBaseline] }
                .frame(width: geo.size.width, height: h * 0.70, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}

/// Top line, dashed midline and baseline, like handwriting paper.
/// Capitals and digits sit between the top line and baseline; lowercase letters reach the midline.
struct WritingGuides: View {
    var body: some View {
        Canvas { context, size in
            func line(at fraction: CGFloat) -> Path {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                return path
            }
            context.stroke(line(at: 0.2), with: .color(.blue.opacity(0.35)), lineWidth: 2)
            context.stroke(line(at: 0.45), with: .color(.red.opacity(0.4)), style: StrokeStyle(lineWidth: 2, dash: [14, 10]))
            context.stroke(line(at: 0.7), with: .color(.blue.opacity(0.6)), lineWidth: 3)
        }
        .allowsHitTesting(false)
    }
}

/// PencilKit canvas that reports its drawing as `Ink`.
struct CharacterCanvas: UIViewRepresentable {
    var allowFingerInput: Bool
    var clearToken: Int
    var onBegin: () -> Void
    var onChange: (Ink) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegin: onBegin, onChange: onChange, clearToken: clearToken)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The box is always white paper, so keep black ink in dark mode too.
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 12)
        canvas.drawingPolicy = allowFingerInput ? .anyInput : .pencilOnly
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = allowFingerInput ? .anyInput : .pencilOnly
        let coordinator = context.coordinator
        coordinator.onBegin = onBegin
        coordinator.onChange = onChange
        if coordinator.clearToken != clearToken {
            coordinator.clearToken = clearToken
            // Clearing is caused by SwiftUI state, so don't report it back during this update.
            coordinator.isClearing = true
            canvas.drawing = PKDrawing()
            coordinator.isClearing = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onBegin: () -> Void
        var onChange: (Ink) -> Void
        var clearToken: Int
        var isClearing = false

        init(onBegin: @escaping () -> Void, onChange: @escaping (Ink) -> Void, clearToken: Int) {
            self.onBegin = onBegin
            self.onChange = onChange
            self.clearToken = clearToken
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            onBegin()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isClearing else { return }
            let ink = Ink(drawing: canvasView.drawing, size: canvasView.bounds.size)
            if ink.hasNonFiniteValues {
                Log.warning(.ink, "PencilKit gave non-finite values: \(ink.logSummary)")
            }
            onChange(ink)
        }
    }
}

extension Ink {
    init(drawing: PKDrawing, size: CGSize) {
        let strokes = drawing.strokes.map { stroke in
            let points = stroke.path.interpolatedPoints(by: .distance(3)).map { point in
                let location = point.location.applying(stroke.transform)
                return InkPoint(x: location.x, y: location.y, t: point.timeOffset, force: point.force)
            }
            return InkStroke(points: points)
        }
        self.init(strokes: strokes, canvasWidth: size.width, canvasHeight: size.height)
    }
}

/// A small picture of a sample, for lists and grids.
struct InkThumbnail: View {
    var ink: Ink

    var body: some View {
        Group {
            if let image = InkRenderer.render(ink, size: 96, padding: 0.12) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color.white
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
    }
}

/// The character being asked for, large, in a rounded face close to how children are taught to write.
struct PromptCharacter: View {
    var character: String

    var body: some View {
        Text(character)
            .font(KidFont.font(size: 110))
            .frame(minWidth: 120)
    }
}
