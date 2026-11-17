import SwiftUI
import KidTutorKit

/// Replay (left), progress dots (center), Help (right): the same on every exercise screen.
struct ExerciseTopBar: View {
    var count: Int
    var index: Int
    var currentDone: Bool
    var helpDisabled: Bool
    var onReplay: () -> Void
    var onHelp: () -> Void

    var body: some View {
        HStack {
            RoundIconButton(systemImage: "speaker.wave.2.fill", label: "Say it again", action: onReplay)
            Spacer()
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i < index || (i == index && currentDone) ? Color.green : Color.clear)
                        .stroke(i == index ? Color.primary : Color.secondary.opacity(0.4), lineWidth: 3)
                        .frame(width: 26, height: 26)
                }
            }
            .accessibilityLabel("Question \(index + 1) of \(count)")
            Spacer()
            Button(action: onHelp) {
                Label("Help", systemImage: "lightbulb.fill")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 24)
                    .frame(minHeight: 64)
            }
            .buttonStyle(.bordered)
            .disabled(helpDisabled)
        }
    }
}

/// One handwriting box for an answer: yellow while open, red after a miss, green when right,
/// with the expected character faded to trace after a second miss or Help.
/// A whole word written in one box uses a wider `aspectRatio`.
struct AnswerBoxView: View {
    @Binding var box: AnswerBox
    var expected: String
    var aspectRatio: CGFloat = AnswerBoxView.letterAspectRatio
    var onPause: () -> Void

    /// Width ÷ height of a box for one character.
    static let letterAspectRatio: CGFloat = 1 / 1.35

    var body: some View {
        WritingPad(
            ink: $box.ink,
            clearToken: box.clearToken,
            aspectRatio: aspectRatio,
            cornerRadius: 14,
            border: box.accepted ? .green : box.lastWasWrong ? .red : .yellow,
            borderWidth: 4,
            traceText: box.showTrace && !box.accepted ? expected : nil,
            onPause: onPause
        )
        .disabled(box.accepted)
        .accessibilityLabel(box.accepted ? "\(expected), correct" : "Answer box")
    }
}

/// A printed character on the writing lines, beside answer boxes.
struct GivenBox: View {
    var text: String

    var body: some View {
        ZStack {
            WritingGuides()
            GuideLetter(text: text)
        }
    }
}

/// The example to copy: printed on the writing lines inside a gray frame, so it reads as
/// "look at this", not as a box to write in.
struct ModelBox: View {
    var text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        // White paper in dark mode too, so the letter must stay dark on it.
        GivenBox(text: text)
            .environment(\.colorScheme, .light)
            .background(Color.white, in: shape)
            .clipShape(shape)
            .overlay(shape.stroke(Color.secondary.opacity(0.45), lineWidth: 4))
            .accessibilityLabel("Example: \(text)")
    }
}

/// Lays out `count` letter boxes in a row, as wide as fits (at most `maxWidth` each),
/// and hands the box size to `content`.
struct LetterRow<Content: View>: View {
    var count: Int
    var maxWidth: CGFloat = 150
    var gap: CGFloat = 14
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geo in
            let width = min(maxWidth, (geo.size.width - gap * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1)))
            HStack(spacing: gap) {
                content(CGSize(width: width, height: width / AnswerBoxView.letterAspectRatio))
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: maxWidth / AnswerBoxView.letterAspectRatio)
    }
}

struct CheckButton: View {
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Label("Check", systemImage: "checkmark")
                    .font(.title2.weight(.bold))
                    .padding(.horizontal, 28)
                    .frame(minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
            .disabled(disabled)
        }
    }
}

struct SessionFinishedView: View {
    var message: String
    /// Claw-machine tokens earned for this session.
    var tokens = 0
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "star.fill")
                .font(.system(size: 160))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            if tokens > 0 {
                TokenBadge(count: tokens, prefix: "+")
            }
            Button(action: onDone) {
                Text("All done")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.horizontal, 56)
                    .frame(minHeight: 96)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One wide handwriting box for writing a whole word from memory, about a letter box wide per letter.
/// After a second miss or Help it shows the word faded to trace.
struct WholeWordBox: View {
    @Binding var box: AnswerBox
    var word: String
    var onPause: () -> Void

    var body: some View {
        GeometryReader { geo in
            let height = min(geo.size.height, 150 / AnswerBoxView.letterAspectRatio)
            let width = min(geo.size.width, max(CGFloat(word.count), 3) * 150)
            AnswerBoxView(box: $box, expected: word, aspectRatio: width / height, onPause: onPause)
                .frame(width: width, height: height)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 150 / AnswerBoxView.letterAspectRatio)
    }
}
