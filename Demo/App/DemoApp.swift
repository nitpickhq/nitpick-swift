import SwiftUI
import Nitpick

@main
struct DemoApp: App {
    init() {
        // Demo settings: dry run by default. Set NITPICK_DEMO_MODE=send and NITPICK_KEY to send
        // to NITPICK_API_URL (default http://localhost:3000); then the demo also fetches its settings from there.
        // Only color and font are chosen in code; the other variables are for the tests.
        let env = ProcessInfo.processInfo.environment
        let sends = env["NITPICK_DEMO_MODE"] == "send"
        var options = NitpickOptions(
            apiURL: URL(string: env["NITPICK_API_URL"] ?? "http://localhost:3000")!,
            dryRun: !sends,
            dryRunDirectory: env["NITPICK_DRYRUN_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        )
        // NITPICK_DEMO_COLOR=RRGGBB: the accent color of this app. Without it: the standard look.
        var color = NitpickColor.standard
        if let hex = env["NITPICK_DEMO_COLOR"], let value = UInt32(hex, radix: 16), hex.count == 6 {
            color = .accent(Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255))
        }
        options.theme = NitpickTheme(color: color, fontName: env["NITPICK_DEMO_FONT"])
        if env["NITPICK_DEMO_TAB"] == "off" { options.showsTab = false }
        if env["NITPICK_DEMO_TAB"] == "left" { options.tabEdge = .left }
        if let position = env["NITPICK_DEMO_VERTICAL"].flatMap(Double.init) { options.tabVerticalPosition = position }
        // NITPICK_DEMO_SCREENS=Checkout,Settings*: the tab shows only on these screens (a comma separated list).
        if let screens = env["NITPICK_DEMO_SCREENS"] {
            options.tabScreens = screens.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        if env["NITPICK_DEMO_BRAND"] == "1" { options.showsBrand = true }
        options.language = env["NITPICK_DEMO_LANGUAGE"]
        Nitpick.configure(appKey: env["NITPICK_KEY"] ?? "npk_demo00000000000000000000", options: options)
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
