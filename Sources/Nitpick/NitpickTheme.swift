import SwiftUI
import UIKit

/// The color of the send button, the mark of the chosen row and the rim of the tab.
public enum NitpickColor: Sendable {
    /// Ink: near black in light, near white in dark.
    case standard
    /// The accent color of your app. The component picks black or white on top of it.
    case accent(Color)
}

/// The two things you choose in code: the color and the font. Everything else is fixed.
public struct NitpickTheme: Sendable {
    public var color: NitpickColor
    /// The PostScript name of a font that is already in your app. Used for headings and buttons only.
    /// `nil` uses the system font. Languages such as Arabic, Hindi, Japanese, Korean and Chinese
    /// always use the system font.
    public var fontName: String?

    public init(color: NitpickColor = .standard, fontName: String? = nil) {
        self.color = color
        self.fontName = fontName
    }
}

/// A color that is fixed in the component, with one value for light and one for dark.
/// The values are the ones in `docs/ontwerp/component/papier.md`; the panel never uses a system color.
struct NitpickShade: Sendable, Equatable {
    struct Value: Sendable, Equatable {
        var hex: UInt32
        var alpha: Double
    }

    var light: Value
    var dark: Value

    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.light = Value(hex: light, alpha: lightAlpha)
        self.dark = Value(hex: dark, alpha: darkAlpha)
    }

    func value(darkMode: Bool) -> Value { darkMode ? dark : light }

    /// Follows the light or dark style of the window the panel is in.
    var uiColor: UIColor {
        let light = light, dark = dark
        return UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value.hex >> 16) & 0xFF) / 255,
                green: CGFloat((value.hex >> 8) & 0xFF) / 255,
                blue: CGFloat(value.hex & 0xFF) / 255,
                alpha: value.alpha
            )
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

/// The fixed colors, sizes and corner radii of the design Papier.
enum NitpickStyle {
    /// The surface of the panel, the pill and the tab.
    static let surface = NitpickShade(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Lines between rows and around fields: black at 12 percent, white at 14 percent.
    static let hairline = NitpickShade(light: 0x000000, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.14)
    /// Main text.
    static let label = NitpickShade(light: 0x111111, dark: 0xF2F2F2)
    /// Second text: explanations, the footer, the labels above fields.
    static let secondary = NitpickShade(light: 0x5C5C5C, dark: 0xA1A1A6)
    /// The layer behind the panel.
    static let dim = NitpickShade(light: 0x000000, lightAlpha: 0.28, dark: 0x000000, darkAlpha: 0.48)
    /// Send in `standard`: ink, with the text on it.
    static let ink = NitpickShade(light: 0x111111, dark: 0xF2F2F2)
    static let onInk = NitpickShade(light: 0xFFFFFF, dark: 0x000000)
    /// Tap spot and element frame: always red `#FF3B30`.
    static let markerShade = NitpickShade(light: 0xFF3B30, dark: 0xFF3B30)
    static let marker = Color(red: 1.0, green: 59.0 / 255.0, blue: 48.0 / 255.0)

    static let sheetCorner: CGFloat = 20
    static let sheetPadding: CGFloat = 20
    static let fieldCorner: CGFloat = 12
    static let sendHeight: CGFloat = 44
    static let sendMinWidth: CGFloat = 112
    static let rowMinHeight: CGFloat = 56
    /// The panel slides up in 280 ms, calm, without overshoot.
    static let slideDuration: Double = 0.28
    /// The thank-you goes away by itself after this long.
    static let thanksDuration: Duration = .milliseconds(2500)
}

/// The two colors that follow from the chosen color: the fill and what is drawn on it.
struct NitpickPalette {
    var fill: Color
    var onFill: Color

    static func resolve(_ color: NitpickColor, in environment: EnvironmentValues) -> NitpickPalette {
        switch color {
        case .standard:
            return NitpickPalette(fill: NitpickStyle.ink.color, onFill: NitpickStyle.onInk.color)
        case .accent(let accent):
            return NitpickPalette(fill: accent, onFill: NitpickContrast.onColor(for: accent, in: environment))
        }
    }
}

enum NitpickContrast {
    /// Relative luminance (0 black ... 1 white) of a color in an environment.
    static func luminance(of color: Color, in environment: EnvironmentValues) -> Double {
        let resolved = color.resolve(in: environment)
        func clamp(_ value: Float) -> Double { Double(min(max(value, 0), 1)) }
        return 0.2126 * clamp(resolved.linearRed) + 0.7152 * clamp(resolved.linearGreen) + 0.0722 * clamp(resolved.linearBlue)
    }

    /// Black or white: whichever has the higher contrast ratio on a color with this luminance.
    static func prefersBlack(onLuminance luminance: Double) -> Bool {
        let againstBlack = (luminance + 0.05) / 0.05
        let againstWhite = 1.05 / (luminance + 0.05)
        return againstBlack > againstWhite
    }

    static func onColor(for color: Color, in environment: EnvironmentValues) -> Color {
        prefersBlack(onLuminance: luminance(of: color, in: environment)) ? .black : .white
    }
}

/// Fonts: the custom font only for headings and buttons; running text stays the system font.
struct NitpickLook: Equatable {
    var theme: NitpickTheme
    var language: String

    static func == (lhs: NitpickLook, rhs: NitpickLook) -> Bool { lhs.language == rhs.language && lhs.theme.fontName == rhs.theme.fontName }

    /// The custom font name when it may be used: not for the six system-font languages, and only when the app has it.
    var customFontName: String? {
        guard let name = theme.fontName, !name.isEmpty, !NitpickLanguage.systemFontOnly.contains(language) else { return nil }
        return UIFont(name: name, size: 17) == nil ? nil : name
    }

    /// A heading or button at a fixed size, for the tab (it does not grow with the text size).
    func heading(fixedSize size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = customFontName { return Font.custom(name, fixedSize: size).weight(weight) }
        return Font.system(size: size, weight: weight)
    }

    /// Headings and buttons.
    func heading(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        if let name = customFontName {
            return Font.custom(name, size: Self.size(for: style), relativeTo: style).weight(weight)
        }
        return Font.system(style).weight(weight)
    }

    /// Running text: always the system font.
    func text(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(style).weight(weight)
    }

    private static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}
