import SwiftUI
import Nitpick

/// A `TabView` whose two tabs keep a marked card on the same place: the one on Home is large, the one on Settings is
/// smaller. A tab that is not selected can stay mounted, so its card could win the tap; the focus of each screen
/// keeps it out. NITPICK_DEMO_TABS_FOCUS=off leaves the focus out, to measure what pointing does without it.
struct TabsScreen: View {
    private enum Tab: Hashable { case home, settings }

    @State private var selection: Tab = .home
    private let passesFocus = ProcessInfo.processInfo.environment["NITPICK_DEMO_TABS_FOCUS"] != "off"

    var body: some View {
        TabView(selection: $selection) {
            card(title: "Water the plants", id: "tabs.home-card", element: "tabs.home_card", height: 160)
                .nitpickScreen("Tabs home", focused: !passesFocus || selection == .home)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)
            card(title: "Profile", id: "tabs.settings-card", element: "tabs.settings_card", height: 70)
                .nitpickScreen("Tabs settings", focused: !passesFocus || selection == .settings)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .navigationTitle("Tabs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card(title: String, id: String, element: String, height: CGFloat) -> some View {
        VStack {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier(id)
                .nitpickElement(element)
            Spacer()
        }
        .padding(20)
    }
}
