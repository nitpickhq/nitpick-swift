import SwiftUI

/// Where the tab sits, from the window size alone, so the SwiftUI layout and the window's
/// touch filter agree without sharing state. The size of the tab depends on its style (`TabMetrics`).
enum TabGeometry {
    static let margin: CGFloat = 60

    /// Where the tab sits: the middle at `verticalPosition` (a fraction of the height, 0...1), but at least
    /// `margin` points from the top and bottom edge. The edge is physical.
    static func rect(in bounds: CGSize, tab: CGSize, edge: NitpickTabEdge, verticalPosition: Double) -> CGRect {
        let fraction = verticalPosition.isNaN ? 0.5 : min(max(verticalPosition, 0), 1)
        let y = min(max(bounds.height * fraction - tab.height / 2, margin), max(margin, bounds.height - tab.height - margin))
        let x = edge == .right ? bounds.width - tab.width : 0
        return CGRect(x: x, y: y, width: tab.width, height: tab.height)
    }
}

/// The vertical tab on the screen edge. Hosted in its own window, so it never lands in the picture.
/// The builder chooses the style (`NitpickTheme.tabStyle`); every style sits flush with the edge, is rounded only on
/// the two inner corners, and has a touch area of at least 44 by 76 points (docs/ontwerp/lipje/README.md).
struct EdgeTabLayer: View {
    let look: NitpickLook
    let label: String
    let edge: NitpickTabEdge
    let verticalPosition: Double
    let action: () -> Void

    @Environment(\.self) private var environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let metrics = TabMetrics.measured(label: label, look: look)
        let palette = self.palette(for: metrics.style)
        GeometryReader { proxy in
            let hit = TabGeometry.rect(in: proxy.size, tab: metrics.hitSize, edge: edge, verticalPosition: verticalPosition)
            // The button is as big as the touch area at rest; the icon tab grows inward past it while it is touched.
            let box = metrics.hitSize
            tab(metrics: metrics, palette: palette, box: box)
                .frame(width: box.width, height: box.height)
                .position(x: edge == .right ? proxy.size.width - box.width / 2 : box.width / 2, y: hit.midY)
        }
        .ignoresSafeArea()
        // Physical: the tab sits on the left or the right of the screen, also in an app that runs from right to left.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func palette(for style: NitpickTabStyle) -> TabPalette {
        let dark = colorScheme == .dark
        let accent = TabPalette.accentRGB(of: look.theme.color, in: environment, dark: dark)
        return TabPalette.make(style: style, accent: accent, dark: dark, reduceTransparency: reduceTransparency)
    }

    private func tab(metrics: TabMetrics, palette: TabPalette, box: CGSize) -> some View {
        Button(action: action) { Color.clear }
            .buttonStyle(TabButtonStyle(metrics: metrics, palette: palette, look: look, label: label, edge: edge, box: box))
            .accessibilityIdentifier("nitpick.tab")
            .accessibilityLabel(Text(verbatim: label))
    }
}

/// Draws the tab for the pressed and the resting state; the touch itself is the button's.
struct TabButtonStyle: ButtonStyle {
    let metrics: TabMetrics
    let palette: TabPalette
    let look: NitpickLook
    let label: String
    let edge: NitpickTabEdge
    let box: CGSize

    func makeBody(configuration: Configuration) -> some View {
        TabFace(metrics: metrics, palette: palette, look: look, label: label, edge: edge, isPressed: configuration.isPressed)
            .frame(width: box.width, height: box.height, alignment: edge == .right ? .trailing : .leading)
            .contentShape(Rectangle())
    }
}

/// One style of the tab, at rest or pressed. Solid, ink and icon take an 8 percent veil of the text color when pressed
/// (90 ms), the frosted tab one of the theme color. The text never scales or fades; only the icon tab moves: it grows inward
/// to "Feedback" and shows the label.
struct TabFace: View {
    let metrics: TabMetrics
    let palette: TabPalette
    let look: NitpickLook
    let label: String
    let edge: NitpickTabEdge
    let isPressed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isIcon: Bool { metrics.style == .icon }
    private var width: CGFloat { isIcon && isPressed ? metrics.expandedWidth : metrics.visibleWidth }
    private var height: CGFloat { metrics.visibleHeight }
    private var alignment: Alignment { edge == .right ? .trailing : .leading }

    /// The shape reaches 2 points past the screen edge and is clipped there, so only the two inner corners are
    /// rounded and no line shows at the edge itself.
    private let overshoot: CGFloat = 2

    private var shape: UnevenRoundedRectangle {
        let r = metrics.radius
        return switch edge {
        case .right: UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
        case .left: UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        }
    }

    /// The shape at the current width, flush with the screen edge, with the overshoot hanging off it.
    private func shaped<V: View>(_ drawing: V) -> some View {
        // The extra points hang off the screen edge, so the shape is held at the side of the app.
        drawing.frame(width: width + overshoot, height: height).frame(width: width, height: height, alignment: edge == .right ? .leading : .trailing)
    }

    var body: some View {
        ZStack(alignment: alignment) {
            fill
            shaped(shape.fill(palette.veil.color.opacity(isPressed ? palette.veilAlpha : 0)))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: isPressed)
            if let line = palette.line {
                shaped(shape.strokeBorder(line.color.color.opacity(line.alpha), lineWidth: line.width))
            }
            content
        }
        .frame(width: width, height: height, alignment: alignment)
        .clipShape(Rectangle())
        .background(alignment: alignment) { shadow }
        .animation(reduceMotion ? nil : (isPressed ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.18) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.14)), value: isPressed)
        .accessibilityHidden(true)
    }

    /// The fill: the color, or for the frosted tab the blurred backdrop with the protective tint on it.
    @ViewBuilder private var fill: some View {
        if palette.usesBlur {
            ZStack {
                shaped(shape.fill(.ultraThinMaterial))
                shaped(shape.fill(palette.fill.color.opacity(palette.fillAlpha)))
            }
        } else {
            shaped(shape.fill(palette.fill.color))
        }
    }

    /// The shadow falls only outside the shape, so it does not show through a frosted fill.
    private var shadow: some View {
        let margin: CGFloat = 24
        return shaped(shape.fill(Color.black))
            .shadow(color: .black.opacity(palette.shadow.opacity), radius: palette.shadow.radius,
                    x: edge == .right ? palette.shadow.x : -palette.shadow.x, y: palette.shadow.y)
            .padding(margin)
            .mask {
                Rectangle().overlay { shaped(shape.fill(Color.black)).padding(margin).blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .padding(-margin)
    }

    @ViewBuilder private var content: some View {
        if isIcon {
            iconContent
        } else {
            ZStack {
                labelText
                    .frame(width: metrics.labelLength, height: TabMetrics.lineHeight)
                    .rotationEffect(.degrees(edge == .right ? -90 : 90))
                    .offset(y: -metrics.labelLift)
            }
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                // The bar of the ink tab: 10 by 2 points, its center 10 points from the bottom.
                if metrics.style == .ink, let bar = palette.bar {
                    Capsule().fill(bar.color).frame(width: 10, height: 2).padding(.bottom, 9)
                }
            }
        }
    }

    private var labelText: some View {
        Text(verbatim: label)
            .font(look.heading(fixedSize: metrics.fontSize, weight: .semibold))
            .tracking(metrics.tracking)
            .foregroundStyle(palette.foreground.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// The glyph sits 14 points from the screen edge; the label shows between 10 points inside and 32 outside.
    private var iconContent: some View {
        let glyphX: CGFloat = edge == .right ? width - 14 : 14
        let labelWidth = max(0, width - 42)
        let labelX: CGFloat = edge == .right ? 10 + labelWidth / 2 : 32 + labelWidth / 2
        return ZStack {
            Image(systemName: "text.bubble")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(palette.foreground.color)
                .position(x: glyphX, y: height / 2)
            labelText
                .frame(width: labelWidth, height: TabMetrics.lineHeight)
                .position(x: labelX, y: height / 2)
                .opacity(isPressed ? 1 : 0)
                .animation(reduceMotion ? nil : (isPressed ? .easeOut(duration: 0.12) : .easeOut(duration: 0.09)), value: isPressed)
        }
        .frame(width: width, height: height)
    }
}
