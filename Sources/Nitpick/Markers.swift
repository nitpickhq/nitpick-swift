import SwiftUI

private struct NitpickScreenIDKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}

extension EnvironmentValues {
    var nitpickScreenID: UUID? {
        get { self[NitpickScreenIDKey.self] }
        set { self[NitpickScreenIDKey.self] = newValue }
    }
}

private struct NitpickScreenFocusKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False inside a screen without focus, also when that screen sits inside another screen.
    var nitpickScreenFocused: Bool {
        get { self[NitpickScreenFocusKey.self] }
        set { self[NitpickScreenFocusKey.self] = newValue }
    }
}

private struct ScreenMarker: ViewModifier {
    let name: String
    let focused: Bool
    @State private var id = UUID()
    @Environment(\.nitpickScreenFocused) private var parentFocused

    func body(content: Content) -> some View {
        let effective = focused && parentFocused
        content
            .environment(\.nitpickScreenID, id)
            .environment(\.nitpickScreenFocused, effective)
            .onAppear { NitpickRegistry.shared.screenAppeared(id: id, name: name, focused: effective) }
            .onChange(of: effective) { NitpickRegistry.shared.screenFocusChanged(id: id, focused: effective) }
            .onDisappear { NitpickRegistry.shared.screenDisappeared(id: id) }
    }
}

private struct ElementMarker: ViewModifier {
    let name: String
    let kind: MarkerKind
    @State private var id = UUID()
    @Environment(\.nitpickScreenID) private var screenID

    func body(content: Content) -> some View {
        content
            // The frame is only measured while the component is open. The measuring view sits in the
            // background, so the marked view itself keeps its identity when tracking starts or stops.
            .background {
                if NitpickRegistry.shared.isTracking {
                    Color.clear.onGeometryChange(for: CGRect.self) { proxy in
                        proxy.frame(in: .global)
                    } action: { frame in
                        NitpickRegistry.shared.updateFrame(id: id, frame: frame)
                    }
                }
            }
            .onAppear {
                NitpickRegistry.shared.registerElement(id: id, name: name, kind: kind, screenID: screenID)
            }
            .onChange(of: name) {
                NitpickRegistry.shared.registerElement(id: id, name: name, kind: kind, screenID: screenID)
            }
            .onDisappear { NitpickRegistry.shared.removeElement(id: id) }
    }
}

extension View {
    /// Names the screen this view is. The last screen that appeared, is still visible and has focus
    /// counts as the current screen. Give a sheet or full screen cover its own name.
    ///
    /// A `TabView` or a navigation stack keeps hidden screens around. Pass the focus of the screen,
    /// for example `.nitpickScreen("Settings", focused: selection == .settings)`: the elements inside
    /// a screen with `focused == false` never count when the user points. Without the option nothing changes.
    public func nitpickScreen(_ name: String, focused: Bool = true) -> some View {
        modifier(ScreenMarker(name: name, focused: focused))
    }

    /// Names an element so users can point at it. Use a stable, searchable name that leads
    /// to the code, for example `"checkout.pay_button"`.
    public func nitpickElement(_ name: String) -> some View {
        modifier(ElementMarker(name: name, kind: .element))
    }

    /// Covers this view with a black box in the picture that goes with feedback.
    /// `SecureField` is covered automatically; use this for card numbers, addresses and the like.
    public func nitpickMask() -> some View {
        modifier(ElementMarker(name: "mask", kind: .mask))
    }

    /// Optional. Makes sure the component is attached to the window scene when this view appears.
    /// `Nitpick.configure(appKey:options:)` already does that, so you can leave this out.
    public func nitpick() -> some View {
        onAppear { Nitpick.attachIfNeeded() }
    }
}
