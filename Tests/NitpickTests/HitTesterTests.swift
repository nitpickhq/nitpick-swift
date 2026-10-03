import Testing
import CoreGraphics
import Foundation
@testable import Nitpick

private func element(_ name: String, _ frame: CGRect, kind: MarkerKind = .element, screen: UUID? = nil) -> MarkedElement {
    MarkedElement(id: UUID(), name: name, kind: kind, frame: frame, screenID: screen)
}

@Suite("Aanwijzen: welk element is geraakt")
struct HitTesterTests {
    let button = element("pay", CGRect(x: 100, y: 200, width: 120, height: 44))

    @Test func exactAsTapIsInsideTheFrame() {
        let result = HitTester.match(tap: CGPoint(x: 150, y: 220), in: [button])
        #expect(result.match == .exact)
        #expect(result.element?.name == "pay")
    }

    @Test func nearestWithin44Points() {
        // 30 points to the right of the frame (maxX = 220).
        let result = HitTester.match(tap: CGPoint(x: 250, y: 220), in: [button])
        #expect(result.match == .nearest)
        #expect(result.element?.name == "pay")
    }

    @Test func noneBeyond44Points() {
        let result = HitTester.match(tap: CGPoint(x: 280, y: 220), in: [button])
        #expect(result.match == .none)
        #expect(result.element == nil)
    }

    @Test func boundaryIs44Inclusive() {
        #expect(HitTester.match(tap: CGPoint(x: 264, y: 220), in: [button]).match == .nearest)
        #expect(HitTester.match(tap: CGPoint(x: 264.5, y: 220), in: [button]).match == .none)
    }

    @Test func smallestOfNestedElementsWins() {
        let card = element("card", CGRect(x: 0, y: 0, width: 300, height: 300))
        let inner = element("card.title", CGRect(x: 20, y: 20, width: 100, height: 30))
        let result = HitTester.match(tap: CGPoint(x: 40, y: 30), in: [card, inner])
        #expect(result.element?.name == "card.title")
        let swapped = HitTester.match(tap: CGPoint(x: 40, y: 30), in: [inner, card])
        #expect(swapped.element?.name == "card.title")
    }

    @Test func outerElementWinsWhereTheInnerOneIsNot() {
        let card = element("card", CGRect(x: 0, y: 0, width: 300, height: 300))
        let inner = element("card.title", CGRect(x: 20, y: 20, width: 100, height: 30))
        #expect(HitTester.match(tap: CGPoint(x: 250, y: 250), in: [card, inner]).element?.name == "card")
    }

    @Test func nearestPicksTheCloserOfTwo() {
        let a = element("a", CGRect(x: 0, y: 0, width: 50, height: 50))
        let b = element("b", CGRect(x: 120, y: 0, width: 50, height: 50))
        let result = HitTester.match(tap: CGPoint(x: 100, y: 20), in: [a, b])
        #expect(result.match == .nearest)
        #expect(result.element?.name == "b")
    }

    @Test func masksNeverMatch() {
        let mask = element("mask", CGRect(x: 0, y: 0, width: 100, height: 100), kind: .mask)
        #expect(HitTester.match(tap: CGPoint(x: 50, y: 50), in: [mask]).match == .none)
    }

    @Test func emptyFramesAreIgnored() {
        let ghost = element("ghost", .zero)
        #expect(HitTester.match(tap: .zero, in: [ghost]).match == .none)
    }

    @Test func distanceToCorner() {
        let d = HitTester.distance(from: CGPoint(x: 0, y: 0), to: CGRect(x: 3, y: 4, width: 10, height: 10))
        #expect(abs(d - 5) < 0.0001)
    }
}

extension SharedState {
@MainActor
@Suite("Bijhouden van kaders en schermen", .serialized)
struct RegistryTests {
    @Test func currentScreenIsTheLastOneThatAppeared() {
        let registry = NitpickRegistry(tracking: true)
        let home = UUID(), sheet = UUID()
        registry.screenAppeared(id: home, name: "Home")
        #expect(registry.currentScreen?.name == "Home")
        registry.screenAppeared(id: sheet, name: "Checkout")
        #expect(registry.currentScreen?.name == "Checkout")
        registry.screenDisappeared(id: sheet)
        #expect(registry.currentScreen?.name == "Home")
        registry.screenDisappeared(id: home)
        #expect(registry.currentScreen == nil)
    }

    @Test func pointableElementsFollowTheCurrentScreen() {
        let registry = NitpickRegistry(tracking: true)
        let home = UUID(), sheet = UUID()
        registry.screenAppeared(id: home, name: "Home")
        registry.screenAppeared(id: sheet, name: "Sheet")
        let underHome = UUID(), inSheet = UUID()
        registry.registerElement(id: underHome, name: "home.button", kind: .element, screenID: home)
        registry.registerElement(id: inSheet, name: "sheet.button", kind: .element, screenID: sheet)
        registry.updateFrame(id: underHome, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        registry.updateFrame(id: inSheet, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(registry.pointableElements().map(\.name) == ["sheet.button"])
    }

    /// Two tabs that are both mounted: the hidden one has the smaller element on the same place and appeared last.
    private func twoTabs(selected: String) -> (registry: NitpickRegistry, a: UUID, b: UUID) {
        let registry = NitpickRegistry(tracking: true)
        let a = UUID(), b = UUID()
        registry.screenAppeared(id: a, name: "Tab A", focused: selected == "A")
        registry.screenAppeared(id: b, name: "Tab B", focused: selected == "B")
        let big = UUID(), small = UUID()
        registry.registerElement(id: big, name: "a.card", kind: .element, screenID: a)
        registry.registerElement(id: small, name: "b.card", kind: .element, screenID: b)
        registry.updateFrame(id: big, frame: CGRect(x: 0, y: 100, width: 300, height: 160))
        registry.updateFrame(id: small, frame: CGRect(x: 20, y: 120, width: 200, height: 60))
        return (registry, a, b)
    }

    @Test func elementsOfAScreenWithoutFocusNeverCount() {
        let (registry, _, _) = twoTabs(selected: "A")
        #expect(registry.currentScreen?.name == "Tab A")
        #expect(registry.pointableElements().map(\.name) == ["a.card"])
        // The tap is inside both frames; the hidden one is smaller but does not win.
        let result = HitTester.match(tap: CGPoint(x: 50, y: 140), in: registry.pointableElements())
        #expect(result.element?.name == "a.card")
        #expect(result.match == .exact)
    }

    @Test func aTapWhereOnlyAHiddenElementLiesGivesNone() {
        let (registry, _, _) = twoTabs(selected: "A")
        // Inside the hidden element only? Its frame lies inside the visible one, so use a hidden element of its own.
        let own = UUID(), tab = UUID()
        registry.screenAppeared(id: tab, name: "Tab C", focused: false)
        registry.registerElement(id: own, name: "c.card", kind: .element, screenID: tab)
        registry.updateFrame(id: own, frame: CGRect(x: 0, y: 600, width: 100, height: 50))
        let result = HitTester.match(tap: CGPoint(x: 50, y: 625), in: registry.pointableElements())
        #expect(result.match == .none)
        #expect(result.element == nil)
    }

    @Test func changingTheFocusMovesTheCurrentScreenAndThePointableElements() {
        let (registry, a, b) = twoTabs(selected: "A")
        registry.screenFocusChanged(id: a, focused: false)
        registry.screenFocusChanged(id: b, focused: true)
        #expect(registry.currentScreen?.name == "Tab B")
        #expect(registry.pointableElements().map(\.name) == ["b.card"])
        // Back to the first tab: it appeared earlier, but the hidden one must not stay current.
        registry.screenFocusChanged(id: b, focused: false)
        registry.screenFocusChanged(id: a, focused: true)
        #expect(registry.currentScreen?.name == "Tab A")
        #expect(registry.pointableElements().map(\.name) == ["a.card"])
    }

    @Test func withoutAnyFocusedScreenOnlyElementsWithoutAScreenRemain() {
        let (registry, _, _) = twoTabs(selected: "none")
        #expect(registry.currentScreen == nil)
        let loose = UUID()
        registry.registerElement(id: loose, name: "loose", kind: .element, screenID: nil)
        registry.updateFrame(id: loose, frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(registry.pointableElements().map(\.name) == ["loose"])
    }

    @Test func screenFocusChangedForAnUnknownScreenIsIgnored() {
        let registry = NitpickRegistry(tracking: true)
        registry.screenFocusChanged(id: UUID(), focused: false)
        #expect(registry.screens.isEmpty)
    }

    @Test func aScreenWithoutTheOptionHasFocus() {
        let registry = NitpickRegistry(tracking: true)
        let id = UUID()
        registry.screenAppeared(id: id, name: "Home")
        #expect(registry.screens[id]?.focused == true)
    }

    @Test func frameReportedBeforeAppearanceIsKept() {
        let registry = NitpickRegistry(tracking: true)
        let id = UUID()
        registry.updateFrame(id: id, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(registry.pointableElements().isEmpty)
        registry.registerElement(id: id, name: "late", kind: .element, screenID: nil)
        #expect(registry.pointableElements().first?.frame == CGRect(x: 1, y: 2, width: 3, height: 4))
    }

    @Test func removedElementsAreGone() {
        let registry = NitpickRegistry(tracking: true)
        let id = UUID()
        registry.registerElement(id: id, name: "x", kind: .element, screenID: nil)
        registry.removeElement(id: id)
        #expect(registry.elements.isEmpty)
    }

    @Test func maskFramesOnlyContainMasks() {
        let registry = NitpickRegistry(tracking: true)
        let a = UUID(), b = UUID()
        registry.registerElement(id: a, name: "mask", kind: .mask, screenID: nil)
        registry.registerElement(id: b, name: "btn", kind: .element, screenID: nil)
        registry.updateFrame(id: a, frame: CGRect(x: 0, y: 0, width: 5, height: 5))
        registry.updateFrame(id: b, frame: CGRect(x: 9, y: 9, width: 5, height: 5))
        #expect(registry.maskFrames() == [CGRect(x: 0, y: 0, width: 5, height: 5)])
    }

    @Test func framesAreOnlyKeptWhileTracking() {
        let registry = NitpickRegistry()
        #expect(!registry.isTracking)
        let id = UUID()
        registry.registerElement(id: id, name: "x", kind: .element, screenID: nil)
        registry.updateFrame(id: id, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(registry.frameUpdateCount == 0)
        #expect(registry.elements[id]?.frame == .zero)
        #expect(registry.pointableElements().first?.frame == .zero)

        registry.setTracking(true)
        registry.updateFrame(id: id, frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(registry.frameUpdateCount == 1)
        #expect(registry.elements[id]?.frame == CGRect(x: 1, y: 2, width: 3, height: 4))

        // Closing drops the frames: a stale frame never matches a later tap.
        registry.setTracking(false)
        #expect(registry.elements[id]?.frame == .zero)
        registry.updateFrame(id: id, frame: CGRect(x: 9, y: 9, width: 9, height: 9))
        #expect(registry.frameUpdateCount == 1)
        #expect(registry.elements[id]?.frame == .zero)
        #expect(HitTester.match(tap: CGPoint(x: 2, y: 3), in: registry.pointableElements()).match == .none)
    }

    @Test func twoHundredElementsMatchQuickly() {
        let registry = NitpickRegistry(tracking: true)
        for i in 0..<200 {
            let id = UUID()
            registry.registerElement(id: id, name: "row.\(i)", kind: .element, screenID: nil)
            registry.updateFrame(id: id, frame: CGRect(x: 0, y: CGFloat(i) * 60, width: 390, height: 56))
        }
        let start = ContinuousClock.now
        for _ in 0..<100 {
            _ = HitTester.match(tap: CGPoint(x: 100, y: 5000), in: registry.pointableElements())
        }
        let elapsed = start.duration(to: .now)
        #expect(elapsed < .milliseconds(500), "100 rounds took \(elapsed)")
    }
}
}
