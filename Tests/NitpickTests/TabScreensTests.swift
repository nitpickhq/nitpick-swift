import Testing
import Foundation
@testable import Nitpick

@Suite("Lipje alleen op gekozen schermen: de regels")
struct TabScreenRuleTests {
    @Test func withoutAListTheTabShowsOnEveryScreenAlsoOneWithoutAName() {
        #expect(TabScreens.allows(screen: "Checkout", list: nil))
        #expect(TabScreens.allows(screen: "", list: nil))
        #expect(TabScreens.allows(screen: nil, list: nil))
        #expect(NitpickOptions().tabScreens == nil)
    }

    @Test func aRuleMustBeExactlyEqualAndCapitalsCount() {
        #expect(TabScreens.allows(screen: "Checkout", list: ["Checkout"]))
        #expect(!TabScreens.allows(screen: "checkout", list: ["Checkout"]))
        #expect(!TabScreens.allows(screen: "Checkout 2", list: ["Checkout"]))
        #expect(!TabScreens.allows(screen: "Check", list: ["Checkout"]))
        #expect(TabScreens.allows(screen: "Map", list: ["Home", "Map"]))
    }

    @Test func aStarAtTheEndMatchesEveryNameThatStartsWithTheRest() {
        #expect(TabScreens.allows(screen: "Checkout", list: ["Checkout*"]))
        #expect(TabScreens.allows(screen: "Checkout payment", list: ["Checkout*"]))
        #expect(TabScreens.allows(screen: "/settings/profile", list: ["/settings/*"]))
        #expect(!TabScreens.allows(screen: "/settings", list: ["/settings/*"]))
        #expect(!TabScreens.allows(screen: "checkout payment", list: ["Checkout*"]))
        #expect(!TabScreens.allows(screen: "My Checkout", list: ["Checkout*"]))
        // A star only counts at the end.
        #expect(!TabScreens.allows(screen: "Checkout", list: ["*out"]))
        #expect(TabScreens.allows(screen: "*out", list: ["*out"]))
    }

    @Test func withAListAScreenWithoutANameNeverShowsTheTab() {
        #expect(!TabScreens.allows(screen: nil, list: ["Checkout"]))
        #expect(!TabScreens.allows(screen: nil, list: ["*"]))
        #expect(!TabScreens.allows(screen: nil, list: []))
    }

    @Test func anEmptyListMeansNowhere() {
        #expect(!TabScreens.allows(screen: "Checkout", list: []))
    }
}

extension SharedState {
@MainActor
@Suite("Lipje alleen op gekozen schermen: het component", .serialized)
struct TabScreensTests {
    func controller(_ options: NitpickOptions) -> NitpickController {
        NitpickRegistry.shared.reset()
        let controller = NitpickController()
        var options = options
        options.dryRun = true
        controller.configure(appKey: "npk_test", options: options)
        return controller
    }

    func show(_ name: String, focused: Bool = true) -> UUID {
        let id = UUID()
        NitpickRegistry.shared.screenAppeared(id: id, name: name, focused: focused)
        return id
    }

    @Test func withoutAListTheTabIsWantedAlsoWithoutAScreen() {
        let controller = controller(NitpickOptions())
        defer { NitpickRegistry.shared.reset() }
        #expect(controller.wantsTab)
        _ = show("Anything")
        #expect(controller.wantsTab)
    }

    @Test func theTabFollowsTheCurrentScreenAgainstTheList() {
        let controller = controller(NitpickOptions(tabScreens: ["Checkout", "Settings*"]))
        defer { NitpickRegistry.shared.reset() }
        #expect(!controller.wantsTab, "no screen with a name yet")
        let home = show("Home")
        #expect(!controller.wantsTab)
        let checkout = show("Checkout")
        #expect(controller.wantsTab)
        NitpickRegistry.shared.screenDisappeared(id: checkout)
        #expect(!controller.wantsTab, "back on Home")
        let settings = show("Settings / profile")
        #expect(controller.wantsTab)
        NitpickRegistry.shared.screenDisappeared(id: settings)
        NitpickRegistry.shared.screenDisappeared(id: home)
        #expect(!controller.wantsTab)
    }

    @Test func anEmptyListShowsNothingAndWritesOneLine() {
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil; NitpickRegistry.shared.reset() }
        let controller = controller(NitpickOptions(tabScreens: []))
        _ = show("Checkout")
        controller.attach()
        controller.attach()
        #expect(!controller.wantsTab)
        #expect(lines.count == 1, "\(lines)")
        #expect(lines.first?.contains("tabScreens is empty") == true)
    }

    @Test func aListThatIsNotEmptyWritesNoLine() {
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil; NitpickRegistry.shared.reset() }
        _ = controller(NitpickOptions(tabScreens: ["Checkout"]))
        #expect(lines.isEmpty, "\(lines)")
    }

    @Test func showsTabFalseWinsOnEveryScreenOfTheList() {
        let controller = controller(NitpickOptions(showsTab: false, tabScreens: ["Checkout"]))
        defer { NitpickRegistry.shared.reset() }
        _ = show("Checkout")
        #expect(!controller.wantsTab)
    }

    @Test func theListCanOnlyHideTheTabNeverShowItWhereItWouldNotBe() {
        let controller = controller(NitpickOptions(tabScreens: ["Checkout"]))
        defer { NitpickRegistry.shared.reset() }
        _ = show("Checkout")
        #expect(controller.wantsTab)
        controller.apply(settings: RemoteSettings(active: false, general: true, specific: true, texts: [:]))
        #expect(!controller.wantsTab, "inactive")
        controller.apply(settings: RemoteSettings(active: true, general: false, specific: false, texts: [:]))
        #expect(!controller.wantsTab, "both kinds off")
        controller.apply(settings: nil)
        #expect(!controller.wantsTab, "no settings yet")
    }

    @Test func aHiddenScreenWithoutFocusDoesNotCount() {
        let controller = controller(NitpickOptions(tabScreens: ["Tabs settings"]))
        defer { NitpickRegistry.shared.reset() }
        let home = show("Tabs home", focused: true)
        let settings = show("Tabs settings", focused: false)
        #expect(!controller.wantsTab, "the settings tab is mounted but hidden; the current screen is Tabs home")
        NitpickRegistry.shared.screenFocusChanged(id: settings, focused: true)
        NitpickRegistry.shared.screenFocusChanged(id: home, focused: false)
        #expect(controller.wantsTab)
        NitpickRegistry.shared.screenFocusChanged(id: settings, focused: false)
        #expect(!controller.wantsTab, "no screen has focus: no name, no tab")
    }

    @Test func thePanelStaysOpenWhenTheScreenChangesAndTheTabFollowsTheListAfterClosing() {
        let controller = controller(NitpickOptions(tabScreens: ["Checkout"]))
        defer { NitpickRegistry.shared.reset() }
        let checkout = show("Checkout")
        #expect(controller.wantsTab)
        controller.openSession(settings: .dryRun, in: nil)
        #expect(controller.session != nil)
        #expect(!controller.wantsTab, "closed while the panel is open")
        NitpickRegistry.shared.screenDisappeared(id: checkout)
        _ = show("Home")
        controller.attach()
        #expect(controller.session != nil, "a change of screen does not close the panel")
        controller.dismiss()
        #expect(controller.session == nil)
        #expect(!controller.wantsTab, "after closing the tab follows the list again: Home is not in it")
        _ = show("Checkout")
        #expect(controller.wantsTab)
    }

    @Test func presentWorksOutsideTheList() {
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil; NitpickRegistry.shared.reset() }
        let controller = controller(NitpickOptions(tabScreens: ["Checkout"]))
        _ = show("Home")
        #expect(!controller.wantsTab)
        controller.present()
        // No scene in a unit test, so no panel; but no guard of present() answered either: the list is not one of them.
        #expect(!lines.contains { $0.contains("present() does nothing") }, "\(lines)")
        // And a session opens outside the list as well.
        controller.openSession(settings: .dryRun, in: nil)
        #expect(controller.session != nil)
        controller.dismiss()
    }
}
}
