import SwiftUI

/// Where the tab sits, from the window size alone, so the SwiftUI layout and the window's
/// touch filter agree without sharing state.
enum TabGeometry {
    /// What you see: 22 points wide and 76 high, flush with the screen edge.
    static let visibleWidth: CGFloat = 22
    static let length: CGFloat = 76
    /// What takes a tap: at least 44 by 76 points, so the tab is easy to hit although it is narrow.
    static let touchWidth: CGFloat = 44
    static let margin: CGFloat = 60

    /// The area that takes a tap. The visible tab sits against the screen edge inside it.
    static let size = CGSize(width: touchWidth, height: length)

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
/// Papier: a narrow, calm surface with a hairline, rounded (10) on the inner side, flush with the edge, the label
/// "Feedback" turned in 11 points semibold, and the chosen color as a thin rim (2 points) on the inside.
struct EdgeTabLayer: View {
    let look: NitpickLook
    let label: String
    let edge: NitpickTabEdge
    let verticalPosition: Double
    let action: () -> Void

    @Environment(\.self) private var environment

    var body: some View {
        GeometryReader { proxy in
            let rect = TabGeometry.rect(in: proxy.size, tab: TabGeometry.size, edge: edge, verticalPosition: verticalPosition)
            tab
                .frame(width: rect.width, height: rect.height, alignment: edge == .right ? .trailing : .leading)
                .position(x: rect.midX, y: rect.midY)
        }
        .ignoresSafeArea()
        // Physical: the tab sits on the left or the right of the screen, also in an app that runs from right to left.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var visibleShape: some View {
        let palette = NitpickPalette.resolve(look.theme.color, in: environment)
        return TabSurface(edge: edge, rim: palette.fill)
    }

    private var tab: some View {
        Button(action: action) {
            ZStack(alignment: edge == .right ? .trailing : .leading) {
                visibleShape
                Text(verbatim: label)
                    .font(look.heading(fixedSize: 11, weight: .semibold))
                    .foregroundStyle(NitpickStyle.label.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    // The label is turned, so its length runs along the height of the tab, with a margin at both ends.
                    .frame(width: TabGeometry.length - 16)
                    .rotationEffect(.degrees(edge == .right ? -90 : 90))
                    .frame(width: TabGeometry.visibleWidth, height: TabGeometry.length)
            }
            .frame(width: TabGeometry.touchWidth, height: TabGeometry.length, alignment: edge == .right ? .trailing : .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nitpick.tab")
        .accessibilityLabel(Text(verbatim: label))
    }
}


/// The surface of the tab: a hairline all around, and the chosen color as a rim of 2 points only on the side of the app
/// (the inside: at a tab on the right that is the left side). It reaches 2 points past the screen edge, so the edge of
/// the screen itself shows no line.
struct TabSurface: View {
    let edge: NitpickTabEdge
    let rim: Color

    static let rimWidth: CGFloat = 2

    private var shape: UnevenRoundedRectangle {
        let r: CGFloat = 10
        return switch edge {
        case .right: UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, style: .continuous)
        case .left: UnevenRoundedRectangle(bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        }
    }

    var body: some View {
        let inward: CGFloat = edge == .right ? 1 : -1   // the direction from the app side to the screen edge
        shape.fill(NitpickStyle.surface.color)
            .overlay(shape.strokeBorder(NitpickStyle.hairline.color, lineWidth: 1))
            // The rim: the shape in the chosen color where the shape moved toward the screen edge does not cover it.
            .overlay {
                shape.fill(rim)
                    .mask {
                        shape.fill(.white)
                            .overlay { shape.fill(.black).offset(x: inward * Self.rimWidth).blendMode(.destinationOut) }
                            .compositingGroup()
                    }
            }
            .shadow(color: .black.opacity(0.06), radius: 5, x: edge == .right ? -2 : 2, y: 1)
            .frame(width: TabGeometry.visibleWidth + 2, height: TabGeometry.length)
            .padding(edge == .right ? .trailing : .leading, -2)
    }
}
