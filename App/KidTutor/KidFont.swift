import CoreText
import SwiftUI
import UIKit

/// Andika (SIL, Open Font License; App/KidTutor/Fonts) is a font made for early readers: its "a" and "g"
/// have the single-story shapes children write, unlike most fonts. Used wherever the child copies or
/// reads a letter or number.
enum KidFont {
    static let regular = "Andika"
    static let bold = "Andika-Bold"

    /// Registers the bundled font files; call once at launch.
    static func register() {
        for file in ["Andika-Regular", "Andika-Bold"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") else {
                Log.error(.app, "font \(file).ttf missing from the app bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                Log.error(.app, "font \(file) not registered: \(error?.takeRetainedValue().localizedDescription ?? "unknown error")")
            }
        }
        Log.info(.app, "font \(regular) available=\(UIFont(name: regular, size: 12) != nil)")
    }

    static func font(size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? Self.bold : regular, fixedSize: size)
    }

    /// x-height and cap height as fractions of the point size, for placing letters on writing lines.
    static let metrics: (xHeight: CGFloat, capHeight: CGFloat) = {
        let font = UIFont(name: regular, size: 100) ?? .systemFont(ofSize: 100)
        return (font.xHeight / 100, font.capHeight / 100)
    }()
}
