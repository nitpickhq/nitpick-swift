import SwiftUI
import Nitpick

/// A `TabView` whose two tabs keep a marked card on the same place: the one on Home is large, the one on Settings is
/// smaller. A tab that is not selected can stay mounted, so its card could win the tap; the focus of each screen
/// keeps it out. NITPICK_DEMO_TABS_FOCUS=off leaves the focus out, to measure what pointing does without it.
struct TabsScreen: View {
    private enum Tab: Hashable { case home, settings }

    @State private var selection: Tab = .home
    private let passesFocus = ProcessInfo.processInfo.environment["NITPICK_DEMO_TABS_FOCUS"] != "off"
    /// NITPICK_DEMO_TABS_MASKS=1 adds the bands of the mask test: on Home a masked band, on Settings a masked band
    /// and, on the same place as the masked band of Home, an open band. A mask on a tab that is not shown must not turn the other tab black.
    private let showsMasks = ProcessInfo.processInfo.environment["NITPICK_DEMO_TABS_MASKS"] != nil
    /// NITPICK_DEMO_TABS_MASKS=zstack: the same two pages in a `ZStack` where the page that is not shown stays mounted at
    /// opacity 0 (the pattern of the docs), with two own buttons instead of a tab bar. Its views keep their frame in the window.
    private let usesZStack = ProcessInfo.processInfo.environment["NITPICK_DEMO_TABS_MASKS"] == "zstack"

    private var homePage: some View {
        card(title: "Water the plants", id: "tabs.home-card", element: "tabs.home_card", height: 160) {
            band("Home secret", id: "tabs.home-mask", color: .yellow, masked: true)
        }
        .nitpickScreen("Tabs home", focused: !passesFocus || selection == .home)
    }

    private var settingsPage: some View {
        card(title: "Profile", id: "tabs.settings-card", element: "tabs.settings_card", height: 70) {
            band("Settings secret", id: "tabs.settings-mask", color: .green, masked: true)
            band("Settings open", id: "tabs.settings-open", color: .orange, masked: false)
        }
        .nitpickScreen("Tabs settings", focused: !passesFocus || selection == .settings)
    }

    var body: some View {
        Group {
            if usesZStack {
                VStack(spacing: 0) {
                    ZStack {
                        homePage.opacity(selection == .home ? 1 : 0)
                        settingsPage.opacity(selection == .settings ? 1 : 0)
                    }
                    HStack {
                        Button("Home") { selection = .home }.accessibilityIdentifier("tabs.switch-home")
                        Spacer()
                        Button("Settings") { selection = .settings }.accessibilityIdentifier("tabs.switch-settings")
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                }
            } else {
                TabView(selection: $selection) {
                    homePage
                        .tabItem { Label("Home", systemImage: "house") }
                        .tag(Tab.home)
                    settingsPage
                        .tabItem { Label("Settings", systemImage: "gear") }
                        .tag(Tab.settings)
                }
            }
        }
        .navigationTitle("Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func band(_ title: String, id: String, color: Color, masked: Bool) -> some View {
        if showsMasks {
            if masked {
                bandView(title, id: id, color: color).nitpickMask()
            } else {
                bandView(title, id: id, color: color)
            }
        }
    }

    private func bandView(_ title: String, id: String, color: Color) -> some View {
        Text(title)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier(id)
    }

    private func card<Extra: View>(title: String, id: String, element: String, height: CGFloat, @ViewBuilder extra: () -> Extra) -> some View {
        VStack {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier(id)
                .nitpickElement(element)
            Spacer()
            extra()
        }
        .padding(20)
    }
}
