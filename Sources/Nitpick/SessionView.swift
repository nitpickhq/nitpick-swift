import SwiftUI

struct SessionView: View {
    @Bindable var session: FeedbackSession
    @Environment(\.self) private var environment

    var body: some View {
        let palette = NitpickPalette.resolve(session.look.theme.color, in: environment)
        ZStack {
            switch session.phase {
            case .picking:
                PickingLayer(session: session, palette: palette)
            case .panel, .sent, .unavailable:
                PanelLayer(session: session, palette: palette)
            }
        }
        .tint(palette.fill)
        // The panel follows the chosen language, not the direction of the app.
        .environment(\.layoutDirection, NitpickLanguage.layoutDirection(for: session.language))
    }
}

/// The animation of the panel: 280 ms, calm, no overshoot.
private let slideAnimation = Animation.timingCurve(0.22, 1, 0.36, 1, duration: NitpickStyle.slideDuration)
/// Closing: the same 280 ms, but it starts gently and leaves faster (ease in, like the Expo component).
private let closeAnimation = Animation.timingCurve(0.32, 0, 0.67, 0, duration: NitpickStyle.slideDuration)

// MARK: Pointing

private struct PickingLayer: View {
    @Bindable var session: FeedbackSession
    let palette: NitpickPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .global) { session.handleTap($0) }
                .accessibilityIdentifier("nitpick.pointing-layer")
                .accessibilityLabel(Text(verbatim: session.texts.pointBanner))
                .ignoresSafeArea()

            // The frames and the tap spot are in window coordinates, which are physical. `.position` counts from the
            // leading edge, so in a right-to-left panel (Arabic) they would be mirrored without this.
            Group {
            ForEach(Array(session.outlines.enumerated()), id: \.offset) { _, frame in
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(palette.fill.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            }
            if let frame = session.highlightFrame {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(NitpickStyle.marker, lineWidth: 3)
                    .frame(width: frame.width + 6, height: frame.height + 6)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
            }
            if let tap = session.highlightTap {
                TapMarker(color: NitpickStyle.marker)
                    .position(tap)
                    .allowsHitTesting(false)
            }
            }
            .environment(\.layoutDirection, .leftToRight)
            .ignoresSafeArea()

            pill
        }
        .onAppear { withAnimation(slideAnimation) { shown = true } }
    }

    /// A compact pill in the middle at the top, under the status bar and inside the safe area, so it never cuts off
    /// the title of the app: what to do, and Cancel.
    private var pill: some View {
        let look = session.look
        return HStack(spacing: 16) {
            Text(verbatim: session.texts.pointBanner)
                .font(look.heading(.subheadline, weight: .semibold))
                .foregroundStyle(NitpickStyle.label.color)
                .fixedSize(horizontal: false, vertical: true)
            Button { session.cancelPicking() } label: {
                Text(verbatim: session.texts.cancel)
                    .font(look.heading(.subheadline))
                    .foregroundStyle(NitpickStyle.secondary.color)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("nitpick.cancel-pointing")
        }
        .padding(.leading, 18)
        .padding(.trailing, 16)
        .frame(minHeight: 44)
        // The shadow belongs to the surface alone: on the whole pill it would also be cast by the text.
        .background {
            Capsule().fill(NitpickStyle.surface.color)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .overlay(Capsule().strokeBorder(NitpickStyle.hairline.color, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(session.highlightTap == nil && shown ? 1 : 0)
        // It fades in from above; with Reduce Motion only the fade stays.
        .offset(y: shown || reduceMotion ? 0 : -16)
    }
}

struct TapMarker: View {
    let color: Color
    var diameter: CGFloat = 34
    @State private var grown = false

    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: diameter < 20 ? 2 : 3).frame(width: diameter, height: diameter)
                .scaleEffect(grown ? 1 : 1.7).opacity(grown ? 1 : 0.2)
            Circle().fill(color).frame(width: diameter * 0.3, height: diameter * 0.3)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.25)) { grown = true } }
    }
}

// MARK: Panel

/// A row of the panel: a light mark while it is pressed.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? NitpickStyle.hairline.color : Color.clear)
    }
}

struct PanelLayer: View {
    @Bindable var session: FeedbackSession
    let palette: NitpickPalette
    /// Tests draw the panel in its place at once, without waiting for the slide.
    var startsShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var iconBox: CGFloat = 32
    @State private var shown: Bool
    @State private var headerHeight: CGFloat = 56
    @State private var contentHeight: CGFloat = 300
    @State private var bottomHeight: CGFloat = 80

    init(session: FeedbackSession, palette: NitpickPalette, startsShown: Bool = false) {
        self.session = session
        self.palette = palette
        self.startsShown = startsShown
        _shown = State(initialValue: startsShown)
    }

    var body: some View {
        // The size excludes the keyboard, so the panel never grows behind it.
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                NitpickStyle.dim.color
                    .ignoresSafeArea()
                    .opacity(shown ? 1 : 0)
                    .onTapGesture { if !session.isSending { session.close() } }
                    .accessibilityHidden(true)
                // It slides up and back down as one piece (a transition); with Reduce Motion it only fades.
                if shown {
                    Group {
                        switch session.phase {
                        case .sent: sent
                        case .unavailable: unavailable
                        default: card(availableHeight: proxy.size.height)
                        }
                    }
                    .frame(maxWidth: 560)
                    .background {
                        // Dense: no material, no transparency. It reaches under the home indicator and past the screen.
                        let shape = UnevenRoundedRectangle(topLeadingRadius: NitpickStyle.sheetCorner, topTrailingRadius: NitpickStyle.sheetCorner, style: .continuous)
                        shape.fill(NitpickStyle.surface.color)
                            .overlay(shape.strokeBorder(NitpickStyle.hairline.color, lineWidth: 1))
                            .padding(.bottom, -(proxy.safeAreaInsets.bottom + 80))
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    // A view that leaves keeps its place above the dim layer while it moves.
                    .zIndex(1)
                }
            }
        }
        .onAppear { withAnimation(slideAnimation) { shown = true } }
        // Closing moves the same way back: down (with Reduce Motion only fading), the dim layer fades with it.
        .onChange(of: session.isClosing) { _, closing in
            if closing { withAnimation(closeAnimation) { shown = false } }
        }
    }

    // MARK: Thanks and unavailable

    private var sent: some View {
        VStack(spacing: 4) {
            VStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(NitpickStyle.label.color, lineWidth: 1.5).frame(width: 40, height: 40)
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(NitpickStyle.label.color)
                }
                // Literal text: the thank-you of the app is never read as Markdown or HTML.
                Text(verbatim: session.texts.thanks)
                    .font(session.look.heading(.subheadline, weight: .semibold))
                    .foregroundStyle(NitpickStyle.label.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("nitpick.sent")
            Button { session.close() } label: {
                Text(verbatim: session.texts.close)
                    .font(session.look.heading(.subheadline))
                    .foregroundStyle(NitpickStyle.secondary.color)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("nitpick.sent-close")
        }
        .padding(.horizontal, NitpickStyle.sheetPadding)
        .padding(.top, 28)
        .padding(.bottom, 12)
    }

    /// The platform said `app_inactive` or `monthly_limit`: one sentence and Close. No Try again.
    private var unavailable: some View {
        VStack(spacing: 20) {
            Text(verbatim: session.texts.unavailable)
                .font(session.look.text(.subheadline))
                .foregroundStyle(NitpickStyle.label.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("nitpick.unavailable")
            HStack {
                Spacer(minLength: 0)
                sendButton(session.texts.close, id: "nitpick.unavailable-close") { session.close() }
            }
        }
        .padding(NitpickStyle.sheetPadding)
        .padding(.top, 8)
    }

    // MARK: The panel and the forms

    /// The header and the footer stay; what is between them scrolls, so Send and the line under it are never hidden
    /// by the keyboard or by a large text size.
    private func card(availableHeight: CGFloat) -> some View {
        let room = availableHeight - 24 - headerHeight - bottomHeight
        return VStack(spacing: 0) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            ScrollView {
                content
                    .padding(.horizontal, NitpickStyle.sheetPadding)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            // As high as its content, but never higher than the room above the keyboard.
            .frame(height: max(96, min(contentHeight, room)))
            bottom
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
    }

    /// The two choices, until one is chosen; pointing without a tap yet shows them again.
    private var choosing: Bool {
        session.showsChoice || (session.kind == .specific && session.pick == nil)
    }

    /// Title on the left, Close (the panel) or Cancel (a form) on the right, a hairline under it.
    private var header: some View {
        let look = session.look
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(verbatim: session.texts.title)
                    .font(look.heading(.headline, weight: .semibold))
                    .foregroundStyle(NitpickStyle.label.color)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { session.close() } label: {
                    Text(verbatim: choosing ? session.texts.close : session.texts.cancel)
                        .font(look.heading(.subheadline))
                        .foregroundStyle(NitpickStyle.secondary.color)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                // While sending, closing would hide a failure the user never sees.
                .disabled(!session.canClose)
                .accessibilityIdentifier("nitpick.close")
            }
            .padding(.horizontal, NitpickStyle.sheetPadding)
            .padding(.top, 8)
            Rectangle().fill(NitpickStyle.hairline.color).frame(height: 1)
                .padding(.horizontal, NitpickStyle.sheetPadding)
        }
    }

    /// What is between the header and the footer: the two rows, or a form.
    @ViewBuilder
    var content: some View {
        if choosing {
            rows
        } else {
            VStack(alignment: .leading, spacing: 0) {
                switch session.kind {
                case .general: commentField(label: session.texts.commentGeneral)
                case .specific: specific
                }
            }
        }
    }

    // MARK: The two rows

    private var rows: some View {
        VStack(spacing: 0) {
            if session.settings.general {
                row(.general, symbol: "bubble.left", title: session.texts.general, hint: session.texts.commentGeneral, id: "nitpick.kind.general")
                if session.settings.specific { hairline }
            }
            if session.settings.specific {
                row(.specific, symbol: "scope", title: session.texts.specific, hint: session.texts.pointHint, id: "nitpick.kind.specific")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nitpick.kind")
    }

    private var hairline: some View {
        Rectangle().fill(NitpickStyle.hairline.color).frame(height: 1)
    }

    /// The row Point at something starts pointing at once; General opens its form. The marks are in the main text color:
    /// the chosen color is for the rim of the tab and for Send.
    private func row(_ kind: FeedbackSession.Kind, symbol: String, title: String, hint: String, id: String) -> some View {
        let look = session.look
        return Button { session.choose(kind) } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(NitpickStyle.label.color)
                    .frame(width: iconBox, height: iconBox)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(NitpickStyle.hairline.color, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(look.heading(.subheadline, weight: .semibold))
                        .foregroundStyle(NitpickStyle.label.color)
                    Text(verbatim: hint)
                        .font(look.text(.footnote))
                        .foregroundStyle(NitpickStyle.secondary.color)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NitpickStyle.secondary.color)
                    .frame(height: iconBox)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .frame(minHeight: NitpickStyle.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier(id)
    }

    // MARK: Pointing form

    /// Preview with the tap spot, next to it two quiet buttons (remove the image, point again); then the question as a label,
    /// and the field. No name of an element: the preview shows what was pointed at; the name stays in the payload.
    @ViewBuilder
    private var specific: some View {
        let look = session.look
        if let pick = session.pick {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    if let image = session.screenshotImage {
                        PreviewImage(image: image, pick: pick)
                            .accessibilityIdentifier("nitpick.preview")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        if session.screenshotImage != nil {
                            quietButton(session.texts.removeImage, id: "nitpick.removeImage") { session.removeImage() }
                        }
                        quietButton(session.texts.pointStart, id: "nitpick.pointAgain") { session.startPicking() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                if session.imageRemoved && session.screenshotImage == nil {
                    Text(verbatim: session.texts.imageRemoved)
                        .font(look.text(.footnote))
                        .foregroundStyle(NitpickStyle.secondary.color)
                        .padding(.bottom, 8)
                        .accessibilityIdentifier("nitpick.imageRemoved")
                }
                commentField(label: session.texts.commentSpecific)
            }
        }
    }

    /// A calm text button, not a box.
    private func quietButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(session.look.heading(.footnote, weight: .semibold))
                .foregroundStyle(NitpickStyle.label.color)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 40, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }

    private func commentField(label: String) -> some View {
        let look = session.look
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: label)
                .font(look.text(.footnote, weight: .semibold))
                .foregroundStyle(NitpickStyle.secondary.color)
                .padding(.top, 10)
            TextField("", text: $session.comment, axis: .vertical)
                .lineLimit(3...6)
                .font(look.text(.subheadline))
                .foregroundStyle(NitpickStyle.label.color)
                .tint(NitpickStyle.label.color)
                .padding(12)
                .background(NitpickStyle.surface.color, in: RoundedRectangle(cornerRadius: NitpickStyle.fieldCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NitpickStyle.fieldCorner, style: .continuous).strokeBorder(NitpickStyle.hairline.color, lineWidth: 1))
                .accessibilityLabel(Text(verbatim: label))
                .accessibilityIdentifier("nitpick.comment")
        }
    }

    // MARK: Send and the line under it

    /// General feedback always has a comment and Send; the form for pointing only after a tap.
    private var showsSend: Bool { !choosing }

    private var bottom: some View {
        let look = session.look
        return VStack(spacing: 10) {
            if showsSend {
                if let message = session.errorMessage {
                    // The red `#FF3B30` has only 3.6:1 on white, so the red is the mark and the words are ink.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(look.text(.footnote))
                            .foregroundStyle(NitpickStyle.marker)
                            .accessibilityHidden(true)
                        Text(verbatim: message)
                            .font(look.text(.footnote))
                            .foregroundStyle(NitpickStyle.label.color)
                            .accessibilityIdentifier("nitpick.error")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                let failed = session.problem == .sending
                HStack {
                    Spacer(minLength: 0)
                    sendButton(
                        session.isSending ? session.texts.sending : (failed ? session.texts.retry : session.texts.send),
                        id: failed ? "nitpick.retry" : "nitpick.send",
                        enabled: !session.isSending
                    ) { session.send() }
                }
            }
            // Literal text: the line of the app is never read as Markdown or HTML. At most 3 lines.
            Text(verbatim: session.texts.footer)
                .font(look.text(.caption))
                .foregroundStyle(NitpickStyle.secondary.color)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("nitpick.footer")
            if session.showsBrand {
                BrandMark()
            }
        }
        .padding(.horizontal, NitpickStyle.sheetPadding)
        .padding(.top, showsSend ? 8 : 4)
        .padding(.bottom, 16)
    }

    /// A refined button: 44 points high, fully rounded, at least 112 wide, in the chosen color.
    private func sendButton(_ title: String, id: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(session.look.heading(.subheadline, weight: .semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(minWidth: NitpickStyle.sendMinWidth, minHeight: NitpickStyle.sendHeight)
                .foregroundStyle(palette.onFill)
                .background(palette.fill.opacity(enabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: NitpickStyle.sendHeight / 2, style: .continuous))
        }
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
}

/// A small mark with the Nitpick domain. Only shown when the app asks for it (`showsBrand`).
struct BrandMark: View {
    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(Color.white)
                Circle().strokeBorder(Color(red: 1.0, green: 0.29, blue: 0.11), lineWidth: 1.2)
                Circle().fill(Color(red: 1.0, green: 0.29, blue: 0.11)).frame(width: 5.5, height: 5.5)
            }
            .frame(width: 12, height: 12)
            Text(verbatim: NitpickBrand.domain)
                .font(.system(.caption2))
                .foregroundStyle(NitpickStyle.secondary.color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nitpick.brand")
    }
}

private struct PreviewImage: View {
    let image: UIImage
    let pick: PickedTarget

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let sx = proxy.size.width / max(pick.viewport.width, 1)
                    let sy = proxy.size.height / max(pick.viewport.height, 1)
                    if let frame = pick.element?.frame {
                        RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(NitpickStyle.marker, lineWidth: 1.5)
                            .frame(width: frame.width * sx, height: frame.height * sy)
                            .position(x: frame.midX * sx, y: frame.midY * sy)
                    }
                    TapMarker(color: NitpickStyle.marker, diameter: 12)
                        .position(x: pick.tap.x * sx, y: pick.tap.y * sy)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(NitpickStyle.hairline.color, lineWidth: 1))
            .frame(maxWidth: 64, maxHeight: 128)
            // The picture is physical: the tap spot and the frame are in window coordinates, also for right to left.
            .environment(\.layoutDirection, .leftToRight)
    }
}
