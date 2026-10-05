import SwiftUI
import UIKit

/// An opaque sRGB color (0...1), for the contrast arithmetic of the tab. No SwiftUI in it, so it can be tested.
struct TabRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    static let black = TabRGB(hex: 0x000000)
    static let white = TabRGB(hex: 0xFFFFFF)

    /// The nearest 8 bit value, as 0xRRGGBB.
    var hex: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((v * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    /// This color moved `amount` (0...1) toward `other`.
    func mixed(with other: TabRGB, amount: Double) -> TabRGB {
        TabRGB(r: r + (other.r - r) * amount, g: g + (other.g - g) * amount, b: b + (other.b - b) * amount)
    }

    /// WCAG contrast ratio, 1...21.
    static func contrast(_ a: TabRGB, _ b: TabRGB) -> Double {
        let high = max(a.luminance, b.luminance), low = min(a.luminance, b.luminance)
        return (high + 0.05) / (low + 0.05)
    }

    /// Pure black or pure white, whichever has the higher contrast on `background`. At least 4.58:1 on any opaque color.
    static func readable(on background: TabRGB) -> TabRGB {
        contrast(.black, background) > contrast(.white, background) ? .black : .white
    }
}

/// One line around the tab: three sides, inside the shape.
struct TabLine: Equatable, Sendable {
    var color: TabRGB
    var alpha: Double
    var width: Double
}

struct TabShadow: Equatable, Sendable {
    var opacity: Double
    var radius: Double
    /// Toward the screen edge: negative on a tab on the right. Mirrored on the left.
    var x: Double
    var y: Double
}

/// The colors of one style of the tab, in light or dark (docs/ontwerp/lipje/README.md). All values are opaque except
/// the alphas that are named.
struct TabPalette: Equatable, Sendable {
    var style: NitpickTabStyle
    var fill: TabRGB
    /// 1 for an opaque fill; the frosted tab (`.material`) tints the blurred backdrop with this alpha.
    var fillAlpha: Double
    /// Whether the fill sits on a blur of what is behind it.
    var usesBlur: Bool
    var foreground: TabRGB
    var line: TabLine?
    /// The accent bar of `.ink`.
    var bar: TabRGB?
    var veil: TabRGB
    var veilAlpha: Double
    var shadow: TabShadow

    /// The Papier surface that a transparent accent is laid on first.
    static func backdrop(dark: Bool) -> TabRGB { dark ? TabRGB(hex: 0x1C1C1E) : .white }

    /// The accent of the builder as one opaque color: composed over Papier, so a transparent accent has a definite
    /// contrast. `nil` for `.standard`.
    static func accentRGB(of color: NitpickColor, in environment: EnvironmentValues, dark: Bool) -> TabRGB? {
        guard case .accent(let accent) = color else { return nil }
        let resolved = accent.resolve(in: environment)
        let alpha = Double(min(max(resolved.opacity, 0), 1))
        let over = TabRGB(r: Double(resolved.red), g: Double(resolved.green), b: Double(resolved.blue))
        return over.composited(alpha: alpha, over: backdrop(dark: dark))
    }

    /// The most that a veil of `veil` at `base` alpha may show over `fill` while `foreground` keeps `minimum` contrast.
    static func veilAlpha(fill: TabRGB, veil: TabRGB, foreground: TabRGB, base: Double = 0.08, minimum: Double = 4.5) -> Double {
        var alpha = base
        while alpha > 0 {
            if TabRGB.contrast(foreground, fill.mixed(with: veil, amount: alpha)) >= minimum { return alpha }
            alpha -= 0.005
        }
        return 0
    }

    /// `accent` is the opaque accent (`nil` for `.standard`).
    static func make(style: NitpickTabStyle, accent: TabRGB?, dark: Bool, reduceTransparency: Bool = false) -> TabPalette {
        let ink = TabRGB(hex: dark ? 0xF2F2F2 : 0x111111)
        let onInk = TabRGB(hex: dark ? 0x111111 : 0xFFFFFF)
        switch style {
        case .accent, .icon:
            let fill = accent ?? ink
            // `.standard` is ink with white (black in dark) on it; an accent gets pure black or white by contrast.
            let foreground = accent.map { TabRGB.readable(on: $0) } ?? TabRGB(hex: dark ? 0x000000 : 0xFFFFFF)
            return TabPalette(
                style: style, fill: fill, fillAlpha: 1, usesBlur: false, foreground: foreground,
                line: TabLine(color: foreground, alpha: 0.2, width: 1), bar: nil,
                veil: foreground, veilAlpha: veilAlpha(fill: fill, veil: foreground, foreground: foreground),
                shadow: TabShadow(opacity: 0.12, radius: 4, x: -1, y: 1)
            )
        case .material:
            let foreground = ink
            let tint = dark ? TabRGB(hex: 0x1C1C1E) : TabRGB.white
            let resting = backdrop(dark: dark)
            let fill = reduceTransparency ? TabRGB(hex: dark ? 0x242426 : 0xF2F2F7) : tint
            // Resting, the surface is neutral; the color of the theme shows only when it is pressed.
            let veil = accent ?? ink
            let nominal = reduceTransparency ? fill : resting
            return TabPalette(
                style: style, fill: fill, fillAlpha: reduceTransparency ? 1 : (dark ? 0.80 : 0.72), usesBlur: !reduceTransparency, foreground: foreground,
                line: TabLine(color: dark ? .white : .black, alpha: dark ? 0.24 : 0.18, width: 0.5), bar: nil,
                veil: veil, veilAlpha: veilAlpha(fill: nominal, veil: veil, foreground: foreground),
                shadow: TabShadow(opacity: 0.08, radius: 3, x: -1, y: 1)
            )
        case .ink:
            let fill = ink
            // The bar: the accent, moved toward white (light) or black (dark) until it is 3:1 against the fill.
            let bar = accent.map { barColor(accent: $0, fill: fill, towardWhite: !dark) } ?? onInk
            return TabPalette(
                style: style, fill: fill, fillAlpha: 1, usesBlur: false, foreground: onInk,
                line: nil, bar: bar,
                veil: onInk, veilAlpha: veilAlpha(fill: fill, veil: onInk, foreground: onInk),
                shadow: TabShadow(opacity: 0.08, radius: 2, x: -1, y: 0)
            )
        }
    }

    /// The smallest move of `accent` toward white or black that gives `minimum` contrast against the fill.
    static func barColor(accent: TabRGB, fill: TabRGB, towardWhite: Bool, minimum: Double = 3) -> TabRGB {
        let target: TabRGB = towardWhite ? .white : .black
        var amount = 0.0
        while amount <= 1 {
            let candidate = accent.mixed(with: target, amount: amount)
            if TabRGB.contrast(candidate, fill) >= minimum { return candidate }
            amount += 0.01
        }
        return target
    }
}

extension TabRGB {
    /// This color at `alpha` laid over an opaque background, as one opaque color.
    func composited(alpha: Double, over background: TabRGB) -> TabRGB {
        background.mixed(with: self, amount: min(max(alpha, 0), 1))
    }
}

/// Sizes of one style of the tab, from the style and the width of the label (docs/ontwerp/lipje/README.md). Points.
struct TabMetrics: Equatable, Sendable {
    var style: NitpickTabStyle
    /// What you see at rest.
    var visibleWidth: CGFloat
    var visibleHeight: CGFloat
    /// What takes a touch at rest: at least 44 by 76.
    var hitSize: CGSize
    /// The visible width while it is touched (only `.icon` grows; the others stay the same).
    var expandedWidth: CGFloat
    /// The radius of the two inner corners.
    var radius: CGFloat
    var fontSize: CGFloat
    var tracking: CGFloat
    /// The length that the turned label has along the height of the tab.
    var labelLength: CGFloat
    /// The label sits this far above the geometric center (ink: 5, the bar sits below it).
    var labelLift: CGFloat

    static let lineHeight: CGFloat = 14
    static let touchWidth: CGFloat = 44
    /// The tab grows to this height before the text shrinks.
    static let growLimit: CGFloat = 120
    static let minimumFontSize: CGFloat = 9.5

    static func baseFontSize(for style: NitpickTabStyle) -> CGFloat { style == .ink ? 10.5 : 11 }
    static func tracking(for style: NitpickTabStyle) -> CGFloat { style == .material ? 0.15 : 0.10 }

    /// `textWidth` is the width of the whole label at the base font size of the style.
    static func make(style: NitpickTabStyle, textWidth: CGFloat) -> TabMetrics {
        let base = baseFontSize(for: style)
        let tracking = tracking(for: style)
        switch style {
        case .icon:
            // Accessible height: the line plus 10 above and below. Expanded width: 10 inside, 32 outside the label.
            let height = max(44, lineHeight + 20)
            return TabMetrics(
                style: style, visibleWidth: 28, visibleHeight: height, hitSize: CGSize(width: touchWidth, height: max(76, height)),
                expandedWidth: max(100, textWidth + 42), radius: 10, fontSize: base, tracking: tracking, labelLength: textWidth, labelLift: 0
            )
        case .accent, .material, .ink:
            let width: CGFloat = style == .accent ? 22 : (style == .material ? 24 : 20)
            let baseHeight: CGFloat = style == .material ? 88 : 80
            let extra: CGFloat = style == .ink ? 28 : 16
            let radius: CGFloat = style == .accent ? 7 : (style == .material ? 9 : 5)
            // Grow to 120 before shrinking the text, never below 9.5 points; then grow further.
            var size = base
            var length = textWidth
            var height = max(baseHeight, textWidth + extra)
            if height > growLimit {
                size = max(minimumFontSize, base * (growLimit - extra) / max(textWidth, 1))
                length = textWidth * size / base
                height = max(growLimit, length + extra)
            }
            return TabMetrics(
                style: style, visibleWidth: width, visibleHeight: height, hitSize: CGSize(width: touchWidth, height: max(baseHeight, height)),
                expandedWidth: width, radius: radius, fontSize: size, tracking: tracking,
                labelLength: height - extra, labelLift: style == .ink ? 5 : 0
            )
        }
    }

    /// The width of the label in the font of the look, at the base size of the style, rounded up to half a point.
    static func labelWidth(_ label: String, look: NitpickLook, style: NitpickTabStyle) -> CGFloat {
        let size = baseFontSize(for: style)
        let font = look.customFontName.flatMap { UIFont(name: $0, size: size) } ?? UIFont.systemFont(ofSize: size, weight: .semibold)
        let width = (label as NSString).size(withAttributes: [.font: font, .kern: tracking(for: style)]).width
        return (width * 2).rounded(.up) / 2
    }

    static func measured(label: String, look: NitpickLook) -> TabMetrics {
        let style = look.theme.tabStyle
        return make(style: style, textWidth: labelWidth(label, look: look, style: style))
    }
}
