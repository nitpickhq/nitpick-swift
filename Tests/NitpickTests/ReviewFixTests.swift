import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Nitpick

/// Fails after a short wait, so a test can close the session while the send is still running.
struct SlowFailingTransport: FeedbackTransport {
    var error: SendError
    func send(payload: Data, screenshot: Data?) async throws {
        try await Task.sleep(for: .milliseconds(150))
        throw error
    }
}

/// A plain object that stands in for a scene: a unit test cannot make a `UIWindowScene`.
final class FakeScene {}

/// The review fixes (S3 to S10). They live in the suite of the panel tests, which runs one test at a time:
/// they touch the same shared things (the availability, the developer log, the registry).
extension SharedState.SessionTests {

    // MARK: S3: present() before configure

    @Test func presentBeforeConfigureWritesOneLineAndDoesNothing() {
        let controller = NitpickController()
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        controller.present()
        #expect(lines.count == 1, "one line: \(lines)")
        #expect(lines.first?.contains("Nitpick.configure has not been called") == true)
        #expect(controller.session == nil)
        #expect(!controller.isConfigured)
    }

    @Test func presentAfterConfigureWithoutASceneStaysQuiet() {
        // Configured and available, but no scene to show a panel in (a unit test has none): no "not configured" line.
        let controller = dryRunController(directory: temporaryDirectory())
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        controller.present()
        #expect(!lines.contains { $0.contains("has not been called") }, "\(lines)")
    }

    // MARK: S5: the key of the demo app

    @Test func theDemoKeyHasTheValidShape() throws {
        let source = try String(contentsOf: Teksten.packageDirectory.appending(path: "Demo/App/DemoApp.swift"), encoding: .utf8)
        let found = try NSRegularExpression(pattern: "npk_[0-9A-Za-z_]+").matches(in: source, range: NSRange(source.startIndex..., in: source))
        let keys = found.compactMap { Range($0.range, in: source).map { String(source[$0]) } }
        #expect(!keys.isEmpty, "the demo app has a key")
        for key in keys {
            let valid = key.range(of: "^npk_[0-9A-Za-z]{24}$", options: .regularExpression) != nil
            #expect(valid, "\(key) is not npk_ plus 24 base62 characters")
        }
    }

    // MARK: S6: windows and registrations per scene

    @Test func anEntryThatBelongsToAnotherOwnerIsNeverUsed() {
        var discarded: [String] = []
        let table = SceneTable<FakeScene, String> { discarded.append($0) }
        let old = FakeScene()
        table.set("window of the old scene", for: old)
        #expect(table.value(for: old) == "window of the old scene")

        // A new scene that gets the identifier of the old one: the entry is copied under its identifier.
        let new = FakeScene()
        table.entries[ObjectIdentifier(new)] = table.entries[ObjectIdentifier(old)]
        #expect(table.value(for: new) == nil, "the old window has no scene of ours; it must not be used")
        #expect(discarded == ["window of the old scene"], "and it is discarded")
        #expect(table.entries[ObjectIdentifier(new)] == nil)
    }

    @Test func aDisconnectedSceneLosesItsEntryAndTheOtherScenesKeepTheirs() {
        var discarded: [String] = []
        let table = SceneTable<FakeScene, String> { discarded.append($0) }
        let a = FakeScene(), b = FakeScene()
        table.set("a", for: a)
        table.set("b", for: b)
        table.remove(a)
        #expect(discarded == ["a"])
        #expect(table.value(for: a) == nil)
        #expect(table.value(for: b) == "b")
        #expect(table.count == 1)
        table.remove(a)
        #expect(discarded == ["a"], "removing twice discards once")
    }

    @Test func aSceneThatIsGoneWithoutANoticeIsPruned() {
        var discarded: [String] = []
        let table = SceneTable<FakeScene, String> { discarded.append($0) }
        var scene: FakeScene? = FakeScene()
        table.set("lost", for: scene!)
        let kept = FakeScene()
        table.set("kept", for: kept)
        scene = nil
        table.prune()
        #expect(discarded == ["lost"])
        #expect(table.values == ["kept"])
    }

    @Test func discardingATabWindowHidesItAndFreesItsHostingController() {
        let controller = dryRunController(directory: temporaryDirectory())
        let window = NitpickWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let signature = NitpickController.TabSignature(look: controller.look, label: "Feedback", edge: .right, verticalPosition: 0.5)
        let entry = controller.installTab(in: window, signature: signature)
        #expect(!window.isHidden && window.rootViewController != nil)
        let scene = FakeScene()
        let table = SceneTable<FakeScene, NitpickController.TabEntry> { entry in
            entry.window.isHidden = true
            entry.window.rootViewController = nil
        }
        table.set(entry, for: scene)
        table.remove(scene)
        #expect(window.isHidden)
        #expect(window.rootViewController == nil)
    }

    @Test func clearingTheTableDiscardsEveryEntry() {
        var discarded: [String] = []
        let table = SceneTable<FakeScene, String> { discarded.append($0) }
        let a = FakeScene(), b = FakeScene()
        table.set("a", for: a)
        table.set("b", for: b)
        table.removeAll()
        #expect(discarded.sorted() == ["a", "b"])
        #expect(table.count == 0)
    }

    // MARK: S9: the tab is not rebuilt at every activation

    @Test func anActivationWithTheSameSignatureLeavesTheHostingControllerAlone() throws {
        let controller = dryRunController(directory: temporaryDirectory())
        let window = NitpickWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let signature = NitpickController.TabSignature(look: controller.look, label: "Feedback", edge: .right, verticalPosition: 0.5)
        var entry = controller.installTab(in: window, signature: signature)
        let host = try #require(window.rootViewController)
        // What attach() does at every activation of a scene that has its window already: a hundred times.
        var rebuilt = 0
        for _ in 0..<100 where controller.refreshTab(&entry, to: signature) { rebuilt += 1 }
        #expect(rebuilt == 0)
        #expect(window.rootViewController === host, "the same hosting controller")
    }

    @Test func aChangedLabelOrPositionIsPassedOnInTheSameHostingController() throws {
        let controller = dryRunController(directory: temporaryDirectory())
        let window = NitpickWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let signature = NitpickController.TabSignature(look: controller.look, label: "Feedback", edge: .right, verticalPosition: 0.5)
        var entry = controller.installTab(in: window, signature: signature)
        let host = try #require(window.rootViewController as? UIHostingController<EdgeTabLayer>)
        var changed = signature
        changed.label = "Terugkoppeling"
        #expect(controller.refreshTab(&entry, to: changed))
        #expect(window.rootViewController === host, "the controller stays, its view changes")
        #expect(host.rootView.label == "Terugkoppeling")
        #expect(entry.signature == changed)
        changed.edge = .left
        changed.verticalPosition = 0.2
        #expect(controller.refreshTab(&entry, to: changed))
        #expect(host.rootView.edge == .left && host.rootView.verticalPosition == 0.2)
        // The touch filter follows: the tab now sits on the left.
        let areaOf = try #require(window.interactiveArea)
        let area = areaOf(window.bounds.size)
        #expect(area.minX == 0)
    }

    // MARK: S7: pointing cannot get stuck

    func pointingSession() -> FeedbackSession {
        let session = FeedbackSession(controller: dryRunController(directory: temporaryDirectory()), scene: nil, settings: .dryRun)
        session.phase = .picking
        return session
    }

    @Test func whenThereIsNoAppWindowTheLightGoesOutAndPointingStays() {
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        let session = pointingSession()
        session.highlightTap = CGPoint(x: 10, y: 10)
        session.highlightFrame = CGRect(x: 0, y: 0, width: 20, height: 20)
        session.finishPick(point: CGPoint(x: 10, y: 10), result: HitResult(element: nil, match: .none), screenName: nil)
        #expect(session.highlightTap == nil && session.highlightFrame == nil, "a new tap is accepted again")
        #expect(session.phase == .picking, "still pointing, so Cancel is there")
        #expect(lines.contains { $0.contains("no picture was taken") })
        // A tap is accepted again.
        session.handleTap(CGPoint(x: 5, y: 5))
        #expect(session.highlightTap == CGPoint(x: 5, y: 5))
        session.end()
    }

    @Test func cancelWorksInEveryStateOfPointing() {
        let session = pointingSession()
        // Before a tap.
        session.cancelPicking()
        #expect(session.phase == .panel)
        // While the found element is lit.
        session.phase = .picking
        session.highlightTap = CGPoint(x: 1, y: 1)
        session.highlightFrame = CGRect(x: 0, y: 0, width: 5, height: 5)
        session.cancelPicking()
        #expect(session.phase == .panel)
        #expect(session.highlightTap == nil && session.highlightFrame == nil)
        // And the pointing can start again.
        session.startPicking()
        #expect(session.phase == .picking)
        session.end()
    }

    // MARK: S8: the work after a tap checks that the session is still open

    @Test func aTapWhoseSessionWasClosedTakesNoPicture() async throws {
        let saved = FeedbackSession.highlightDuration
        FeedbackSession.highlightDuration = .milliseconds(60)
        defer { FeedbackSession.highlightDuration = saved }
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }

        // Control: left alone, the work after the tap runs (here it stops at once for lack of an app window, and says so).
        let open = pointingSession()
        open.handleTap(CGPoint(x: 5, y: 5))
        await wait { open.highlightTap == nil }
        #expect(lines.contains { $0.contains("no picture was taken") }, "the control must run the work: \(lines)")
        open.end()

        // Closed within the pause: the work does nothing, and the light is out.
        lines.removeAll()
        let closed = pointingSession()
        closed.handleTap(CGPoint(x: 5, y: 5))
        #expect(closed.highlightTap != nil)
        closed.end()
        try await Task.sleep(for: .milliseconds(300))
        #expect(lines.isEmpty, "no picture, no log: \(lines)")
        #expect(closed.phase == .picking)
        #expect(closed.screenshot == nil)
    }

    @Test func closingTheControllerEndsTheSessionAndItsWaitingWork() async throws {
        let saved = FeedbackSession.highlightDuration
        FeedbackSession.highlightDuration = .milliseconds(60)
        defer { FeedbackSession.highlightDuration = saved }
        let controller = dryRunController(directory: temporaryDirectory())
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        controller.session = session
        session.phase = .picking
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        session.handleTap(CGPoint(x: 5, y: 5))
        controller.dismiss()
        #expect(session.isEnded)
        #expect(controller.session == nil)
        try await Task.sleep(for: .milliseconds(300))
        #expect(lines.isEmpty, "\(lines)")
    }

    // MARK: S10: closing while sending

    @Test func theCloseButtonIsOffWhileSending() async throws {
        let controller = dryRunController(directory: temporaryDirectory())
        controller.transportOverride = { SlowFailingTransport(error: .network("offline")) }
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        #expect(session.canClose)
        session.comment = "Hello"
        session.send()
        #expect(session.isSending)
        #expect(!session.canClose)
        await wait { session.problem != nil }
        #expect(session.problem == .sending)
        #expect(session.canClose, "after the failure the user can close again, and the draft is still there")
        #expect(session.comment == "Hello")
    }

    @Test func aFailedSendAfterTheSessionWasClosedLeavesALine() async throws {
        let controller = dryRunController(directory: temporaryDirectory())
        controller.transportOverride = { SlowFailingTransport(error: .server(503)) }
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        session.comment = "Hello"
        session.send()
        session.end()   // what the controller does when the app calls dismiss() or configure() meanwhile
        await wait { !lines.isEmpty }
        #expect(lines.contains { $0.contains("sending failed after the panel was closed") && $0.contains("did not arrive") }, "\(lines)")
        #expect(session.problem == nil, "nobody sees a message")
        #expect(!session.isSending)
    }
}
