import Testing
import SwiftUI
import UIKit
@testable import Nitpick

/// The four styles of the tab (`NitpickTheme.tabStyle`): the choice, the sizes, the colors and their contrast, and what is drawn.
/// The numbers are the ones in docs/ontwerp/lipje/README.md.
@MainActor
@Suite("Stijlen van het lipje")
struct TabStyleTests {
    let environment = EnvironmentValues()

    /// Accents that cover light, dark, saturated and transparent-looking colors.
    let accents: [(String, UInt32)] = [
        ("navy", 0x293582), ("periwinkle", 0x6E7FD6), ("purple", 0x6E56CF), ("yellow", 0xFFE600), ("green", 0x1FA463), ("red", 0xE5484D),
        ("white", 0xFFFFFF), ("black", 0x000000), ("mid grey", 0x777777), ("orange", 0xF76B15), ("teal", 0x0E9AA7), ("pink", 0xFF8AC0),
    ]

    // MARK: The choice

    @Test func theDefaultStyleIsAccentAndThereAreFourStyles() {
        #expect(NitpickTheme().tabStyle == .accent)
        #expect(NitpickOptions().theme.tabStyle == .accent)
        #expect(NitpickTheme(color: .standard, fontName: nil).tabStyle == .accent, "the older call keeps working")
        #expect(NitpickTabStyle.allCases == [.accent, .material, .ink, .icon])
        #expect(NitpickTheme(tabStyle: .icon).tabStyle == .icon)
    }

    @Test func aChangedStyleChangesTheLookAndTheSignatureOfTheTab() {
        let accent = NitpickLook(theme: NitpickTheme(), language: "en")
        let ink = NitpickLook(theme: NitpickTheme(tabStyle: .ink), language: "en")
        #expect(accent != ink)
        #expect(accent == NitpickLook(theme: NitpickTheme(), language: "en"))
        let controller = NitpickController()
        let window = NitpickWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let first = NitpickController.TabSignature(look: accent, label: "Feedback", edge: .right, verticalPosition: 0.5)
        var entry = controller.installTab(in: window, signature: first)
        var changed = first
        changed.look = ink
        #expect(controller.refreshTab(&entry, to: changed), "a new style is passed on to the tab that is there")
        #expect(!controller.refreshTab(&entry, to: changed))
    }

    // MARK: Sizes

    @Test func everyStyleHasTheSizesOfTheDesign() {
        let accent = TabMetrics.make(style: .accent, textWidth: 52)
        #expect(accent.visibleWidth == 22 && accent.visibleHeight == 80 && accent.radius == 7 && accent.fontSize == 11 && accent.tracking == 0.10)
        let material = TabMetrics.make(style: .material, textWidth: 52)
        #expect(material.visibleWidth == 24 && material.visibleHeight == 88 && material.radius == 9 && material.fontSize == 11 && material.tracking == 0.15)
        let ink = TabMetrics.make(style: .ink, textWidth: 52)
        #expect(ink.visibleWidth == 20 && ink.visibleHeight == 80 && ink.radius == 5 && ink.fontSize == 10.5 && ink.tracking == 0.10 && ink.labelLift == 5)
        let icon = TabMetrics.make(style: .icon, textWidth: 52)
        #expect(icon.visibleWidth == 28 && icon.visibleHeight == 44 && icon.radius == 10 && icon.expandedWidth == 100 && icon.fontSize == 11)
    }

    @Test func theTouchAreaIsAtLeast44By76AndGrowsWithTheTab() {
        #expect(TabMetrics.make(style: .accent, textWidth: 52).hitSize == CGSize(width: 44, height: 80))
        #expect(TabMetrics.make(style: .material, textWidth: 52).hitSize == CGSize(width: 44, height: 88))
        #expect(TabMetrics.make(style: .ink, textWidth: 52).hitSize == CGSize(width: 44, height: 80))
        #expect(TabMetrics.make(style: .icon, textWidth: 52).hitSize == CGSize(width: 44, height: 76))
        for style in NitpickTabStyle.allCases {
            for width in stride(from: CGFloat(20), through: 200, by: 10) {
                let metrics = TabMetrics.make(style: style, textWidth: width)
                #expect(metrics.hitSize.width >= 44 && metrics.hitSize.height >= 76, "\(style) \(width)")
                #expect(metrics.hitSize.height >= metrics.visibleHeight, "the target grows with the visual: \(style) \(width)")
            }
        }
    }

    @Test func aLongLabelGrowsTheTabBeforeTheTextShrinks() {
        // 90 points of text: height = text + 16 (ink: + 28), font untouched.
        let accent = TabMetrics.make(style: .accent, textWidth: 90)
        #expect(accent.visibleHeight == 106 && accent.fontSize == 11 && accent.labelLength == 90)
        #expect(TabMetrics.make(style: .material, textWidth: 90).visibleHeight == 106)
        let ink = TabMetrics.make(style: .ink, textWidth: 90)
        #expect(ink.visibleHeight == 118 && ink.fontSize == 10.5 && ink.labelLength == 90)
        #expect(TabMetrics.make(style: .icon, textWidth: 90).expandedWidth == 132, "icon: text + 42")
        // Past 120 points the text shrinks to fit 120 ...
        let shrunk = TabMetrics.make(style: .accent, textWidth: 110)
        #expect(shrunk.visibleHeight == 120 && shrunk.fontSize < 11 && shrunk.fontSize > 9.5)
        // ... never below 9.5, and then the tab grows further.
        let longest = TabMetrics.make(style: .accent, textWidth: 140)
        #expect(longest.fontSize == 9.5 && longest.visibleHeight > 120)
        #expect(longest.labelLength >= 140 * 9.5 / 11 - 0.01, "the whole label stays")
    }

    @Test(arguments: NitpickTabStyle.allCases)
    func everyOfTheTwentyLanguageLabelsFitsWholeInEveryStyle(style: NitpickTabStyle) {
        for code in GeneratedTexts.table.keys.sorted() {
            let label = GeneratedTexts.table[code]?["tabLabel"] ?? ""
            #expect(!label.isEmpty, "\(code)")
            let look = NitpickLook(theme: NitpickTheme(tabStyle: style), language: code)
            let width = TabMetrics.labelWidth(label, look: look, style: style)
            let metrics = TabMetrics.make(style: style, textWidth: width)
            let shown = width * metrics.fontSize / TabMetrics.baseFontSize(for: style)
            if style == .icon {
                #expect(metrics.expandedWidth >= width + 42, "\(code): the label does not fit the expanded tab")
            } else {
                #expect(metrics.labelLength >= shown - 0.01, "\(code): \(label) is cut (\(metrics.labelLength) < \(shown))")
                #expect(metrics.fontSize >= 9.5, "\(code)")
            }
        }
    }

    @Test func theMeasuredEnglishLabelGivesTheBaseHeights() {
        for style in [NitpickTabStyle.accent, .material, .ink] {
            let metrics = TabMetrics.measured(label: "Feedback", look: NitpickLook(theme: NitpickTheme(tabStyle: style), language: "en"))
            let base: CGFloat = style == .material ? 88 : 80
            #expect(metrics.visibleHeight == base, "\(style): \(metrics.visibleHeight)")
        }
        let french = TabMetrics.measured(label: "Commentaires", look: NitpickLook(theme: NitpickTheme(tabStyle: .accent), language: "fr"))
        #expect(french.visibleHeight > 90 && french.visibleHeight < 105, "Commentaires: \(french.visibleHeight)")
    }

    // MARK: Colors

    private func palette(_ style: NitpickTabStyle, accent: UInt32?, dark: Bool, reduceTransparency: Bool = false) -> TabPalette {
        TabPalette.make(style: style, accent: accent.map { TabRGB(hex: $0) }, dark: dark, reduceTransparency: reduceTransparency)
    }

    @Test func accentSolidUsesTheAccentAndPicksBlackOrWhite() {
        let navy = palette(.accent, accent: 0x293582, dark: false)
        #expect(navy.fill.hex == 0x293582 && navy.foreground.hex == 0xFFFFFF)
        #expect(abs(TabRGB.contrast(navy.fill, navy.foreground) - 10.90) < 0.05, "navy on white is 10.90:1")
        // The dark accent of the design: black on #6E7FD6 is 5.67:1, white would be 3.70:1.
        let light = palette(.accent, accent: 0x6E7FD6, dark: true)
        #expect(light.foreground.hex == 0x000000)
        #expect(abs(TabRGB.contrast(light.fill, light.foreground) - 5.67) < 0.05)
        #expect(abs(TabRGB.contrast(light.fill, .white) - 3.70) < 0.05)
        #expect(navy.line == TabLine(color: .white, alpha: 0.2, width: 1))
        #expect(light.line == TabLine(color: .black, alpha: 0.2, width: 1))
        #expect(navy.shadow == TabShadow(opacity: 0.12, radius: 4, x: -1, y: 1))
    }

    @Test func standardIsInkInLightAndDark() {
        for style in [NitpickTabStyle.accent, .icon] {
            let l = palette(style, accent: nil, dark: false), d = palette(style, accent: nil, dark: true)
            #expect(l.fill.hex == 0x111111 && l.foreground.hex == 0xFFFFFF, "\(style) light")
            #expect(d.fill.hex == 0xF2F2F2 && d.foreground.hex == 0x000000, "\(style) dark")
        }
    }

    @Test func materialIsNeutralAndTheThemeColorOnlyShowsWhenPressed() {
        let light = palette(.material, accent: 0x293582, dark: false), dark = palette(.material, accent: 0x293582, dark: true)
        #expect(light.fill.hex == 0xFFFFFF && light.fillAlpha == 0.72 && light.foreground.hex == 0x111111 && light.usesBlur)
        #expect(dark.fill.hex == 0x1C1C1E && dark.fillAlpha == 0.80 && dark.foreground.hex == 0xF2F2F2)
        #expect(light.line == TabLine(color: .black, alpha: 0.18, width: 0.5))
        #expect(dark.line == TabLine(color: .white, alpha: 0.24, width: 0.5))
        #expect(light.veil.hex == 0x293582, "the veil is the theme color")
        #expect(palette(.material, accent: nil, dark: false).veil.hex == 0x111111, "standard: ink")
        #expect(light.shadow == TabShadow(opacity: 0.08, radius: 3, x: -1, y: 1))
        // Reduce Transparency: opaque, no blur.
        let opaqueLight = palette(.material, accent: nil, dark: false, reduceTransparency: true)
        let opaqueDark = palette(.material, accent: nil, dark: true, reduceTransparency: true)
        #expect(opaqueLight.fill.hex == 0xF2F2F7 && opaqueLight.fillAlpha == 1 && !opaqueLight.usesBlur)
        #expect(opaqueDark.fill.hex == 0x242426 && opaqueDark.fillAlpha == 1 && !opaqueDark.usesBlur)
    }

    @Test func inkIsFixedAndKeepsABarOfTheAccent() {
        let light = palette(.ink, accent: 0x293582, dark: false), dark = palette(.ink, accent: 0x293582, dark: true)
        #expect(light.fill.hex == 0x111111 && light.foreground.hex == 0xFFFFFF && light.line == nil)
        #expect(dark.fill.hex == 0xF2F2F2 && dark.foreground.hex == 0x111111)
        #expect(abs(TabRGB.contrast(light.fill, light.foreground) - 18.88) < 0.05)
        #expect(abs(TabRGB.contrast(dark.fill, dark.foreground) - 16.87) < 0.05)
        #expect(dark.bar?.hex == 0x293582, "navy on near white is already above 3:1: unchanged")
        #expect(light.shadow == TabShadow(opacity: 0.08, radius: 2, x: -1, y: 0))
        #expect(palette(.ink, accent: nil, dark: false).bar?.hex == 0xFFFFFF, "standard: the foreground")
        #expect(palette(.ink, accent: nil, dark: true).bar?.hex == 0x111111)
    }

    @Test(arguments: NitpickTabStyle.allCases, [false, true])
    func textContrastIsAtLeast4Point5ForEveryAccentAndAfterPressing(style: NitpickTabStyle, dark: Bool) {
        let choices: [UInt32?] = [nil] + accents.map { $0.1 }
        for choice in choices {
            for reduce in [false, true] {
                let p = palette(style, accent: choice, dark: dark, reduceTransparency: reduce)
                // The fill that the text sits on: the translucent one over Papier.
                let resting = p.fill.composited(alpha: p.fillAlpha, over: TabPalette.backdrop(dark: dark))
                let name = "\(style) dark:\(dark) accent:\(choice.map { String($0, radix: 16) } ?? "standard") reduce:\(reduce)"
                #expect(TabRGB.contrast(p.foreground, resting) >= 4.5, "resting \(name)")
                let pressed = resting.mixed(with: p.veil, amount: p.veilAlpha)
                #expect(TabRGB.contrast(p.foreground, pressed) >= 4.5, "pressed \(name)")
                #expect(p.veilAlpha <= 0.08 + 1e-9, "\(name)")
            }
        }
    }

    @Test func theTextColorIsPureBlackOrWhiteWithAtLeast4Point58() {
        for (name, hex) in accents {
            let fill = TabRGB(hex: hex)
            let text = TabRGB.readable(on: fill)
            #expect(text == .black || text == .white, "\(name)")
            #expect(TabRGB.contrast(text, fill) >= 4.58 - 0.005, "\(name): \(TabRGB.contrast(text, fill))")
        }
        for step in 0...255 {
            let v = Double(step) / 255
            let fill = TabRGB(r: v, g: v, b: v)
            #expect(TabRGB.contrast(TabRGB.readable(on: fill), fill) >= 4.575, "grey \(step)")
        }
    }

    @Test func theInkBarKeeps3To1AgainstTheFillWithTheLeastChange() {
        for (name, hex) in accents {
            for dark in [false, true] {
                let accent = TabRGB(hex: hex)
                let p = palette(.ink, accent: hex, dark: dark)
                let bar = p.bar!
                #expect(TabRGB.contrast(bar, p.fill) >= 3 - 0.01, "\(name) dark:\(dark): \(TabRGB.contrast(bar, p.fill))")
                if TabRGB.contrast(accent, p.fill) >= 3 { #expect(bar == accent, "\(name): already enough, so unchanged") }
            }
        }
    }

    @Test func aTransparentAccentIsLaidOnPapierFirst() {
        var env = EnvironmentValues()
        env.colorScheme = .light
        let half = Color(red: 0, green: 0, blue: 0, opacity: 0.5)
        let onLight = TabPalette.accentRGB(of: .accent(half), in: env, dark: false)
        #expect(onLight != nil)
        #expect(abs((onLight?.r ?? 0) - 0.5) < 0.01, "half black over white is mid grey")
        let onDark = TabPalette.accentRGB(of: .accent(half), in: env, dark: true)
        #expect(abs((onDark?.r ?? 1) - (0x1C / 255.0) / 2) < 0.01, "half black over #1C1C1E")
        #expect(TabPalette.accentRGB(of: .standard, in: env, dark: false) == nil)
        let opaque = TabPalette.accentRGB(of: .accent(Color(red: 0x29 / 255.0, green: 0x35 / 255.0, blue: 0x82 / 255.0)), in: env, dark: false)
        #expect(opaque?.hex == 0x293582)
    }

    // MARK: What is drawn

    private struct Pixels {
        var width: Int
        var height: Int
        var data: [UInt8]
        func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]), Int(data[i + 3]))
        }
    }

    /// The face of the tab as pixels, one pixel to the point, in a light or dark environment.
    private func render(_ style: NitpickTabStyle, accent: UInt32? = 0x293582, edge: NitpickTabEdge = .right, dark: Bool = false, pressed: Bool = false, label: String = "Feedback") throws -> Pixels {
        let color: NitpickColor = accent.map { .accent(Color(red: Double($0 >> 16 & 0xFF) / 255, green: Double($0 >> 8 & 0xFF) / 255, blue: Double($0 & 0xFF) / 255)) } ?? .standard
        let look = NitpickLook(theme: NitpickTheme(color: color, tabStyle: style), language: "en")
        let metrics = TabMetrics.measured(label: label, look: look)
        let p = TabPalette.make(style: style, accent: accent.map { TabRGB(hex: $0) }, dark: dark, reduceTransparency: true)
        let face = TabFace(metrics: metrics, palette: p, look: look, label: label, edge: edge, isPressed: pressed)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: face)
        renderer.scale = 1
        let cgImage = try #require(renderer.uiImage?.cgImage)
        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Pixels(width: width, height: height, data: data)
    }

    @Test(arguments: [NitpickTabStyle.accent, .material, .ink, .icon])
    func theFaceHasTheVisibleSizeAndIsRoundedOnTheInnerCornersOnly(style: NitpickTabStyle) throws {
        let look = NitpickLook(theme: NitpickTheme(tabStyle: style), language: "en")
        let metrics = TabMetrics.measured(label: "Feedback", look: look)
        for edge in [NitpickTabEdge.right, .left] {
            let pixels = try render(style, edge: edge)
            #expect(pixels.width == Int(metrics.visibleWidth) && pixels.height == Int(metrics.visibleHeight), "\(style) \(edge): \(pixels.width)x\(pixels.height)")
            let inner = edge == .right ? 0 : pixels.width - 1
            let outer = edge == .right ? pixels.width - 1 : 0
            // The two inner corners are cut; the corners on the screen edge are square and filled.
            #expect(pixels.rgba(inner, 0).a < 128 && pixels.rgba(inner, pixels.height - 1).a < 128, "\(style) \(edge): inner corners are round")
            #expect(pixels.rgba(outer, 0).a > 200 && pixels.rgba(outer, pixels.height - 1).a > 200, "\(style) \(edge): outer corners are square")
            #expect(pixels.rgba(outer, pixels.height / 2).a > 200 && pixels.rgba(inner, pixels.height / 2).a > 200, "\(style) \(edge): the middle is filled")
        }
    }

    @Test func theFillIsTheAccentAndAccentAndIconHaveAKeylineOnThreeSidesOnly() throws {
        for style in [NitpickTabStyle.accent, .icon] {
            let p = try render(style)
            let mid = p.height / 2
            // Inside the keyline: the accent. On the keyline (1 pt in): white at 20% over the accent, so lighter.
            let fill = p.rgba(p.width - 3, mid), line = p.rgba(p.width - 3, 0)
            #expect(fill.r == 0x29 && fill.g == 0x35 && fill.b == 0x82, "\(style): fill \(fill)")
            #expect(line.r > fill.r + 20, "\(style): the keyline at the top is lighter: \(line)")
            let left = p.rgba(0, mid)
            #expect(left.r > fill.r + 20, "\(style): the keyline on the inner side is lighter: \(left)")
            #expect(p.rgba(1, mid).r == fill.r, "\(style): the keyline is 1 point wide")
            // Not on the screen edge: the last column is the plain fill.
            #expect(p.rgba(p.width - 1, mid).r == fill.r, "\(style): no line on the screen edge")
        }
        let ink = try render(.ink)
        #expect(ink.rgba(0, ink.height / 2).r == 0x11 || ink.rgba(1, ink.height / 2).r == 0x11, "ink has no keyline")
    }

    @Test(arguments: [false, true])
    func theInkTabHasABarOf10By2PointsCenteredTenPointsFromTheBottom(dark: Bool) throws {
        let p = try render(.ink, dark: dark)
        let fill = dark ? 0xF2 : 0x11
        let palette = palette(.ink, accent: 0x293582, dark: dark)
        let bar = palette.bar!
        // Rows 69 and 70 are the bar (center 10 from the bottom of 80); x 5 to 14.
        for y in [69, 70] {
            for x in 5..<15 {
                let px = p.rgba(x, y)
                #expect(abs(px.r - Int((bar.r * 255).rounded())) <= 2 && abs(px.b - Int((bar.b * 255).rounded())) <= 2, "bar pixel \(x),\(y): \(px)")
            }
        }
        #expect(p.rgba(2, 70).r == fill && p.rgba(17, 70).r == fill, "the bar is only 10 wide")
        #expect(p.rgba(10, 66).r == fill && p.rgba(10, 73).r == fill, "the bar is only 2 high")
    }

    @Test func theIconTabGrowsInwardWhenTouchedAndTheOuterEdgeStays() throws {
        let rest = try render(.icon), pressed = try render(.icon, pressed: true)
        #expect(rest.width == 28 && rest.height == 44)
        #expect(pressed.width == 100 && pressed.height == 44, "100 by 44 when touched: \(pressed.width)x\(pressed.height)")
        // Dark: the same shape, now with the light accent.
        #expect(try render(.icon, dark: true, pressed: true).width == 100)
        // The label shows in the pressed state: more than the fill color between the glyph and the inner side.
        var found = false
        for x in 12..<60 { for y in 10..<34 where pressed.rgba(x, y).r > 200 && pressed.rgba(x, y).g > 200 { found = true } }
        #expect(found, "the white label shows on the navy fill")
        // At rest there is no text: only the glyph near the edge.
        var textAtRest = false
        for x in 1..<5 { for y in 10..<34 where rest.rgba(x, y).r > 200 && rest.rgba(x, y).g > 200 { textAtRest = true } }
        #expect(!textAtRest, "no text at rest")
    }

    @Test func aLongerLabelWidensThePressedIconTab() throws {
        let wide = try render(.icon, pressed: true, label: "Commentaires")
        #expect(wide.width > 100, "Commentaires: \(wide.width)")
    }

    @Test func theWindowTakesTouchesInTheTouchAreaOfTheStyle() throws {
        let controller = NitpickController()
        let cases: [(NitpickTabStyle, CGFloat)] = [(.accent, 80), (.material, 88), (.ink, 80), (.icon, 76)]
        for (style, height) in cases {
            let window = NitpickWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            let look = NitpickLook(theme: NitpickTheme(tabStyle: style), language: "en")
            let signature = NitpickController.TabSignature(look: look, label: "Feedback", edge: .right, verticalPosition: 0.5)
            _ = controller.installTab(in: window, signature: signature)
            let areaOf = try #require(window.interactiveArea)
            let area = areaOf(window.bounds.size)
            #expect(area.width == 44 && area.height == height, "\(style): \(area)")
            #expect(area.maxX == 393 && area.midY == 426, "\(style): on the right edge, in the middle")
            let outside = window.hitTest(CGPoint(x: 100, y: 426), with: nil)
            #expect(outside == nil, "\(style): the rest of the screen falls through")
        }
    }
}
