import Testing
import SwiftUI
import UIKit
@testable import Nitpick

@MainActor
@Suite("Kleur en lipje")
struct LookTests {
    let environment = EnvironmentValues()

    /// The 24-bit value a color resolves to in an environment.
    func rgb(_ color: Color, in env: EnvironmentValues) -> UInt32 {
        let resolved = color.resolve(in: env)
        func byte(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return byte(resolved.red) << 16 | byte(resolved.green) << 8 | byte(resolved.blue)
    }

    @Test func blackOnLightColorsAndWhiteOnDarkOnes() {
        func onColor(_ color: Color) -> Color { NitpickContrast.onColor(for: color, in: environment) }
        #expect(onColor(Color(red: 1, green: 0.9, blue: 0)) == .black, "yellow")
        #expect(onColor(Color(red: 0.95, green: 0.95, blue: 0.95)) == .black, "light grey")
        #expect(onColor(.white) == .black, "white")
        #expect(onColor(Color(red: 0.05, green: 0.1, blue: 0.5)) == .white, "dark blue")
        #expect(onColor(Color(red: 0.4, green: 0.05, blue: 0.1)) == .white, "dark red")
        #expect(onColor(.black) == .white, "black")
    }

    @Test func theChoiceAlwaysHasTheHigherContrast() {
        for step in 0...20 {
            let value = Double(step) / 20
            let color = Color(red: value, green: value, blue: value)
            let luminance = NitpickContrast.luminance(of: color, in: environment)
            let againstBlack = (luminance + 0.05) / 0.05
            let againstWhite = 1.05 / (luminance + 0.05)
            let black = NitpickContrast.onColor(for: color, in: environment) == .black
            #expect(black == (againstBlack > againstWhite), "grey \(value)")
            #expect(max(againstBlack, againstWhite) >= 4.5, "grey \(value) has contrast below 4.5")
        }
    }

    @Test func accentColorBecomesTheFillAndStandardIsLabelOnBackground() {
        let accent = NitpickPalette.resolve(.accent(Color(red: 1, green: 0.9, blue: 0)), in: environment)
        #expect(accent.onFill == .black)
        // Standard is ink: near black with white on it in light, near white with black on it in dark.
        for (scheme, ink, onInk) in [(ColorScheme.light, UInt32(0x111111), UInt32(0xFFFFFF)), (.dark, 0xF2F2F2, 0x000000)] {
            var env = EnvironmentValues()
            env.colorScheme = scheme
            let standard = NitpickPalette.resolve(.standard, in: env)
            #expect(rgb(standard.fill, in: env) == ink, "fill \(scheme)")
            #expect(rgb(standard.onFill, in: env) == onInk, "on fill \(scheme)")
        }
    }

    @Test func tabSitsOnTheChosenEdgeAtTheChosenFraction() {
        let window = CGSize(width: 393, height: 852), tab = CGSize(width: 32, height: 96)
        let right = TabGeometry.rect(in: window, tab: tab, edge: .right, verticalPosition: 0.5)
        #expect(right == CGRect(x: 393 - 32, y: 852 / 2 - 48, width: 32, height: 96))
        let left = TabGeometry.rect(in: window, tab: tab, edge: .left, verticalPosition: 0.5)
        #expect(left.minX == 0)
        #expect(left.midY == right.midY)
        let quarter = TabGeometry.rect(in: window, tab: tab, edge: .right, verticalPosition: 0.25)
        #expect(quarter.midY == 852 * 0.25)
    }

    @Test func tabStaysAtLeast60PointsFromTopAndBottom() {
        let window = CGSize(width: 393, height: 852), tab = CGSize(width: 32, height: 96)
        for fraction in [0.0, 0.01, -3.0] {
            #expect(TabGeometry.rect(in: window, tab: tab, edge: .right, verticalPosition: fraction).minY >= 60)
        }
        for fraction in [0.99, 1.0, 7] {
            #expect(TabGeometry.rect(in: window, tab: tab, edge: .right, verticalPosition: fraction).maxY <= 852 - 60)
        }
        let top = TabGeometry.rect(in: window, tab: tab, edge: .right, verticalPosition: 0)
        let bottom = TabGeometry.rect(in: window, tab: tab, edge: .right, verticalPosition: 1)
        #expect(top.minY == 60)
        let expectedBottom: CGFloat = 852 - 60
        #expect(bottom.maxY == expectedBottom, "maxY \(bottom.maxY) vs \(expectedBottom) diff \(bottom.maxY - expectedBottom)")
    }

    @Test func theTabIsNarrowToSeeAndEasyToHit() {
        #expect(TabGeometry.visibleWidth == 22)
        #expect(TabGeometry.length == 76)
        #expect(TabGeometry.size.width >= 44 && TabGeometry.size.height >= 76, "the area that takes a tap is at least 44 by 76 points")
    }

    @Test func accentColor6E56CFGetsWhiteBecauseThatHasTheHigherContrast() {
        let accent = Color(red: 0x6E / 255.0, green: 0x56 / 255.0, blue: 0xCF / 255.0)
        let luminance = NitpickContrast.luminance(of: accent, in: environment)
        #expect(!NitpickContrast.prefersBlack(onLuminance: luminance))
        #expect(NitpickContrast.onColor(for: accent, in: environment) == .white)
        #expect(1.05 / (luminance + 0.05) >= 4.5, "white on #6E56CF is at least 4.5:1")
        let palette = NitpickPalette.resolve(.accent(accent), in: environment)
        #expect(palette.onFill == .white)
    }
}

/// The fixed colors of Papier, in light and dark, as in `docs/ontwerp/component/papier.md`.
@MainActor
@Suite("Vaste kleuren van Papier")
struct PapierColorTests {
    /// Relative luminance of a 24-bit sRGB color.
    func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    @Test func theValuesAreTheOnesInTheDesign() {
        let light = false, dark = true
        #expect(NitpickStyle.surface.value(darkMode: light) == .init(hex: 0xFFFFFF, alpha: 1))
        #expect(NitpickStyle.surface.value(darkMode: dark) == .init(hex: 0x1C1C1E, alpha: 1))
        #expect(NitpickStyle.hairline.value(darkMode: light) == .init(hex: 0x000000, alpha: 0.12))
        #expect(NitpickStyle.hairline.value(darkMode: dark) == .init(hex: 0xFFFFFF, alpha: 0.14))
        #expect(NitpickStyle.label.value(darkMode: light) == .init(hex: 0x111111, alpha: 1))
        #expect(NitpickStyle.label.value(darkMode: dark) == .init(hex: 0xF2F2F2, alpha: 1))
        #expect(NitpickStyle.secondary.value(darkMode: light) == .init(hex: 0x5C5C5C, alpha: 1))
        #expect(NitpickStyle.secondary.value(darkMode: dark) == .init(hex: 0xA1A1A6, alpha: 1))
        #expect(NitpickStyle.dim.value(darkMode: light) == .init(hex: 0x000000, alpha: 0.28))
        #expect(NitpickStyle.dim.value(darkMode: dark) == .init(hex: 0x000000, alpha: 0.48))
        #expect(NitpickStyle.ink.value(darkMode: light) == .init(hex: 0x111111, alpha: 1))
        #expect(NitpickStyle.onInk.value(darkMode: light) == .init(hex: 0xFFFFFF, alpha: 1))
        #expect(NitpickStyle.ink.value(darkMode: dark) == .init(hex: 0xF2F2F2, alpha: 1))
        #expect(NitpickStyle.onInk.value(darkMode: dark) == .init(hex: 0x000000, alpha: 1))
        #expect(NitpickStyle.markerShade.value(darkMode: light) == .init(hex: 0xFF3B30, alpha: 1))
        #expect(NitpickStyle.markerShade.value(darkMode: dark) == .init(hex: 0xFF3B30, alpha: 1))
    }

    @Test func theColorsFollowLightAndDarkOfTheWindow() {
        for (shade, name) in [(NitpickStyle.surface, "surface"), (NitpickStyle.label, "label"), (NitpickStyle.secondary, "secondary"), (NitpickStyle.hairline, "hairline"), (NitpickStyle.dim, "dim")] {
            for isDark in [false, true] {
                let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                shade.uiColor.resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                let expected = shade.value(darkMode: isDark)
                let hex = UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
                #expect(hex == expected.hex, "\(name) \(isDark ? "dark" : "light")")
                #expect(abs(Double(alpha) - expected.alpha) < 0.005, "\(name) alpha \(isDark ? "dark" : "light")")
            }
        }
    }

    @Test func swiftUIResolvesTheSameValuesInLightAndDark() {
        for (scheme, surface, label) in [(ColorScheme.light, UInt32(0xFFFFFF), UInt32(0x111111)), (.dark, 0x1C1C1E, 0xF2F2F2)] {
            var env = EnvironmentValues()
            env.colorScheme = scheme
            func byte(_ value: Float) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
            let s = NitpickStyle.surface.color.resolve(in: env), l = NitpickStyle.label.color.resolve(in: env)
            #expect(byte(s.red) << 16 | byte(s.green) << 8 | byte(s.blue) == surface, "surface \(scheme)")
            #expect(byte(l.red) << 16 | byte(l.green) << 8 | byte(l.blue) == label, "label \(scheme)")
        }
    }

    @Test func everyTextHasAtLeast4Point5ToOneOnTheSurface() {
        for isDark in [false, true] {
            let surface = NitpickStyle.surface.value(darkMode: isDark).hex
            for (shade, name) in [(NitpickStyle.label, "label"), (NitpickStyle.secondary, "secondary")] {
                #expect(contrast(shade.value(darkMode: isDark).hex, surface) >= 4.5, "\(name) \(isDark ? "dark" : "light")")
            }
            // Send in standard: the text on the ink.
            #expect(contrast(NitpickStyle.onInk.value(darkMode: isDark).hex, NitpickStyle.ink.value(darkMode: isDark).hex) >= 4.5, "send \(isDark ? "dark" : "light")")
        }
    }

    @Test func theThankYouStaysFor2Point5Seconds() {
        #expect(NitpickStyle.thanksDuration == .milliseconds(2500))
        #expect(NitpickStyle.slideDuration == 0.28)
    }
}
