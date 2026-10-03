import SwiftUI
import Nitpick

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Screens") {
                    NavigationLink("Checkout form") { CheckoutScreen() }
                        .accessibilityIdentifier("nav.checkout")
                        .nitpickElement("home.checkout_link")
                    NavigationLink("Sheet") { SheetScreen() }
                        .accessibilityIdentifier("nav.sheet")
                        .nitpickElement("home.sheet_link")
                    NavigationLink("Map") { MapScreen() }
                        .accessibilityIdentifier("nav.map")
                        .nitpickElement("home.map_link")
                    NavigationLink("Web page") { WebScreen() }
                        .accessibilityIdentifier("nav.web")
                        .nitpickElement("home.web_link")
                    NavigationLink("Video") { VideoScreen() }
                        .accessibilityIdentifier("nav.video")
                        .nitpickElement("home.video_link")
                    NavigationLink("Tabs") { TabsScreen() }
                        .accessibilityIdentifier("nav.tabs")
                        .nitpickElement("home.tabs_link")
                    NavigationLink("200 rows (eager)") { PerfEagerScreen() }
                        .accessibilityIdentifier("nav.perfeager")
                        .nitpickElement("home.perf_eager_link")
                    NavigationLink("200 rows") { PerfScreen() }
                        .accessibilityIdentifier("nav.perf")
                        .nitpickElement("home.perf_link")
                }
                Section("Your own button") {
                    // Hidden while the component has nothing to offer (no settings yet, inactive, or both kinds off).
                    if Nitpick.isAvailable {
                        Button("Open feedback from my button") { Nitpick.present() }
                            .accessibilityIdentifier("demo.own-button")
                            .nitpickElement("home.own_button")
                    } else {
                        Text(verbatim: "Feedback is not available").foregroundStyle(.secondary)
                            .accessibilityIdentifier("demo.own-button-hidden")
                    }
                }
                Section("Appearance of this app") {
                    // Sets the style of the app's own window; the component's panel must follow it.
                    Button("App window: light") { AppWindowStyle.set(.light) }
                        .accessibilityIdentifier("demo.style-light")
                    Button("App window: dark") { AppWindowStyle.set(.dark) }
                        .accessibilityIdentifier("demo.style-dark")
                }
                Section("Status") {
                    DiagText()
                }
            }
            .navigationTitle("Nitpick Demo")
            .safeAreaInset(edge: .bottom) {
                // A small element at the start of the row: on the left in a left-to-right app, on the right in a
                // right-to-left app. The tests use it to see where the component draws its frames.
                HStack {
                    Text(verbatim: "Beta")
                        .font(.footnote.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.3), in: Capsule())
                        .accessibilityIdentifier("demo.badge")
                        .nitpickElement("home.badge")
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
        .modifier(OptionalNitpickModifier())
        .nitpickScreen("Home")
    }
}

/// Light or dark for the app's own window (not for the component's windows), so the tests can show that the
/// component follows the app's window and not only the system.
enum AppWindowStyle {
    @MainActor static func set(_ style: UIUserInterfaceStyle) {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.windowLevel == .normal { window.overrideUserInterfaceStyle = style }
        }
    }
}

/// `.nitpick()` is optional. NITPICK_DEMO_NO_MODIFIER=1 leaves it out to prove that `configure` alone is enough.
private struct OptionalNitpickModifier: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.environment["NITPICK_DEMO_NO_MODIFIER"] == "1" {
            content
        } else {
            content.nitpick()
        }
    }
}

/// Shows what the component measures, so tests can read it.
struct DiagText: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.4)) { _ in
            let d = Nitpick.diagnostics
            Text(verbatim: "elements=\(d.registeredElements) updates=\(d.frameUpdates) screen=\(d.currentScreen ?? "-") pick_ms=\(fmt(d.lastPickMilliseconds)) capture_ms=\(fmt(d.lastCaptureMilliseconds)) shot=\(d.lastScreenshotPixels ?? "-")/\(d.lastScreenshotBytes ?? 0) complete=\(d.lastCaptureComplete.map { String($0) } ?? "-") dry=\(d.lastDryRunPath ?? "-")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("demo.diag")
        }
    }

    private func fmt(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? "-"
    }
}
