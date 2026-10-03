import Testing
import Foundation
import SwiftUI
import UIKit
@testable import Nitpick

/// A transport that fails the way the platform does.
struct FailingTransport: FeedbackTransport {
    var error: SendError
    func send(payload: Data, screenshot: Data?) async throws { throw error }
}

/// Counts what is sent.
final class CountingTransport: FeedbackTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [Data] = []
    var sent: [Data] { lock.lock(); defer { lock.unlock() }; return payloads }
    func send(payload: Data, screenshot: Data?) async throws {
        record(payload)
    }
    private func record(_ payload: Data) {
        lock.lock(); payloads.append(payload); lock.unlock()
    }
}

/// Everything here touches the shared registry, the availability or the log, so the suite runs one test at a time.
extension SharedState {
@MainActor
@Suite("Paneel, opmerking, instellingen en fouten", .serialized)
struct SessionTests {
    let scratch = ScratchDefaults()

    func dryRunController(language: String = "en", directory: URL) -> NitpickController {
        let controller = NitpickController()
        controller.configure(appKey: "npk_test", options: NitpickOptions(dryRun: true, dryRunDirectory: directory, language: language))
        return controller
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "nitpick-session-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    func wait(until condition: () -> Bool, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(25)) }
    }

    // MARK: Opmerking en score

    @Test(arguments: ["", "   ", "\n\t "])
    func generalFeedbackWithoutACommentIsNotSent(_ comment: String) async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = dryRunController(language: "nl", directory: directory)
        let counting = CountingTransport()
        controller.transportOverride = { counting }
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        #expect(session.kind == .general)
        session.comment = comment
        session.send()
        try await Task.sleep(for: .milliseconds(300))
        #expect(counting.sent.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!session.isSending)
        #expect(session.problem == .comment)
        #expect(session.errorMessage == "Schrijf een korte opmerking.")
        #expect(session.phase == .panel)
        // Typing clears the message; the send button stays a send button, not Try again.
        session.comment = "x"
        #expect(session.problem == nil)
    }

    @Test func generalFeedbackWithACommentIsSentWithoutAScore() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = dryRunController(directory: directory)
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        session.comment = "  Nice app  "
        session.send()
        await wait { (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == false }
        let folder = try #require(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let data = try Data(contentsOf: folder.appending(path: "payload.json"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["kind"] as? String == "general")
        #expect(object["comment"] as? String == "Nice app")
        #expect(object["score"] == nil)
        #expect((object["sdk"] as? [String: String])?["version"] == "0.2.0")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "screenshot.jpg").path))
        await wait { session.phase == .sent }
        #expect(session.phase == .sent)
    }

    // MARK: Fouten

    @Test func theFailureTextIsFixedAndTheServerMessageGoesOnlyToTheLog() async throws {
        let directory = temporaryDirectory()
        let controller = dryRunController(language: "en", directory: directory)
        controller.transportOverride = { FailingTransport(error: .rejected("SECRET server message about the database")) }
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        session.comment = "Hello"
        session.send()
        await wait { session.problem != nil }
        #expect(session.problem == .sending)
        #expect(session.errorMessage == "Sending failed. Your feedback is still here.")
        #expect(session.errorMessage?.contains("SECRET") == false)
        #expect(lines.contains { $0.contains("SECRET server message") })
        #expect(session.comment == "Hello", "the draft is kept")
        #expect(session.phase == .panel)
    }

    @Test(arguments: [SendError.rateLimited, .server(500), .network("offline"), .tooLarge, .invalidKey])
    func otherFailuresShowTheFixedTextAndTryAgain(_ error: SendError) async throws {
        let controller = dryRunController(directory: temporaryDirectory())
        controller.transportOverride = { FailingTransport(error: error) }
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        session.comment = "Hello"
        session.send()
        await wait { session.problem != nil }
        #expect(session.problem == .sending)
        #expect(session.phase == .panel)
        #expect(controller.isAvailable, "the tab stays")
    }

    @Test(arguments: ["app_inactive", "monthly_limit"])
    func anUnavailableAnswerStopsEverythingAndTheTabGoes(_ code: String) async throws {
        let controller = dryRunController(directory: temporaryDirectory())
        controller.transportOverride = { FailingTransport(error: .unavailable(code)) }
        let session = FeedbackSession(controller: controller, scene: nil, settings: .dryRun)
        #expect(controller.isAvailable)
        session.comment = "A draft that goes away"
        session.send()
        await wait { session.phase == .unavailable }
        #expect(session.phase == .unavailable)
        #expect(session.problem == nil, "no Try again")
        #expect(session.comment.isEmpty, "the draft is gone")
        #expect(session.pick == nil && session.screenshot == nil)
        #expect(session.texts.unavailable == "Feedback is not available right now.")
        #expect(!controller.isAvailable, "the tab goes away")
        #expect(controller.settings?.active == false)
        #expect(!Nitpick.isAvailable)
    }

    @Test func unavailableIsKeptInTheStoredSettingsAndLiftedByTheNextAnswer() async throws {
        ConfigStub.reset([.status(200, #"{"active":true}"#)], host: "session.stub.test")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConfigStub.self]
        let defaults = scratch.defaults
        let loaderSession = URLSession(configuration: configuration)
        let controller = NitpickController()
        controller.makeLoader = { url, key in SettingsLoader(apiURL: url, appKey: key, session: loaderSession, defaults: defaults, sleep: { _ in throw CancellationError() }) }
        controller.configure(appKey: "npk_abcdefghijklmnopqrstuvwx", options: NitpickOptions(apiURL: URL(string: "http://session.stub.test")!))
        await wait { controller.isAvailable }
        #expect(controller.isAvailable)
        controller.markUnavailable()
        #expect(!controller.isAvailable)
        let key = SettingsStore.key(apiURL: URL(string: "http://session.stub.test")!, appKey: "npk_abcdefghijklmnopqrstuvwx")
        #expect(SettingsStore.load(key, from: defaults)?.settings.active == false)
        // Next valid answer lifts it.
        ConfigStub.reset([.status(200, #"{"active":true}"#)], host: "session.stub.test")
        let again = NitpickController()
        again.makeLoader = controller.makeLoader
        again.configure(appKey: "npk_abcdefghijklmnopqrstuvwx", options: NitpickOptions(apiURL: URL(string: "http://session.stub.test")!))
        #expect(!again.isAvailable, "kept active: false counts until a valid answer comes")
        await wait { again.isAvailable }
        #expect(again.isAvailable)
    }

    // MARK: Instellingen en lipje

    @Test func withoutSettingsThereIsNoTabAndPresentDoesNothing() async throws {
        ConfigStub.reset([.status(500, "")], host: "session.stub.test")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConfigStub.self]
        let defaults = scratch.defaults
        let loaderSession = URLSession(configuration: configuration)
        let controller = NitpickController()
        controller.makeLoader = { url, key in SettingsLoader(apiURL: url, appKey: key, session: loaderSession, defaults: defaults, sleep: { _ in throw CancellationError() }) }
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        controller.configure(appKey: "npk_abcdefghijklmnopqrstuvwx", options: NitpickOptions(apiURL: URL(string: "http://session.stub.test")!))
        try await Task.sleep(for: .milliseconds(200))
        #expect(controller.settings == nil)
        #expect(!controller.isAvailable)
        #expect(!Nitpick.isAvailable)
        lines.removeAll()
        controller.present()
        #expect(controller.session == nil)
        #expect(lines.count == 1 && lines[0].contains("no feedback settings"), "\(lines)")
    }

    @Test func presentDoesNothingWhenInactiveOrBothKindsAreOff() async throws {
        let controller = dryRunController(directory: temporaryDirectory())
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        controller.apply(settings: RemoteSettings(active: false, general: true, specific: true, texts: [:]))
        #expect(!controller.isAvailable && !Nitpick.isAvailable)
        controller.present()
        #expect(controller.session == nil)
        #expect(lines.count == 1 && lines[0].contains("not active"), "\(lines)")
        lines.removeAll()
        controller.apply(settings: RemoteSettings(active: true, general: false, specific: false, texts: [:]))
        #expect(!controller.isAvailable)
        controller.present()
        #expect(lines.count == 1 && lines[0].contains("both kinds"), "\(lines)")
        controller.apply(settings: RemoteSettings(active: true, general: false, specific: true, texts: [:]))
        #expect(controller.isAvailable && Nitpick.isAvailable)
    }

    @Test func aSessionKeepsTheSettingsAndTextsOfTheMomentItOpened() async throws {
        let controller = dryRunController(language: "nl", directory: temporaryDirectory())
        let opening = RemoteSettings(active: true, general: false, specific: true, texts: ["nl": .init(footer: "Vorige tekst", thanks: nil)])
        controller.apply(settings: opening)
        let session = FeedbackSession(controller: controller, scene: nil, settings: opening)
        controller.apply(settings: RemoteSettings(active: true, general: true, specific: true, texts: ["nl": .init(footer: "Nieuwe tekst", thanks: nil)]))
        #expect(session.texts.footer == "Vorige tekst")
        #expect(session.kind == .specific)
        #expect(!session.offersBothKinds)
        // A session that opens now sees the new answer.
        let next = FeedbackSession(controller: controller, scene: nil, settings: controller.settings!)
        #expect(next.texts.footer == "Nieuwe tekst")
        #expect(next.offersBothKinds)
    }

    // MARK: Papier: the rows of the panel

    @Test func theRowPointAtSomethingStartsPointingAtOnce() throws {
        let session = FeedbackSession(controller: dryRunController(directory: temporaryDirectory()), scene: nil, settings: .dryRun)
        #expect(session.showsChoice, "both kinds are on: the panel shows the two rows")
        #expect(session.phase == .panel)
        session.choose(.specific)
        #expect(session.phase == .picking, "no second button: the row starts pointing")
        #expect(session.kind == .specific)
        // Cancelling brings the user back to the rows.
        session.cancelPicking()
        #expect(session.phase == .panel)
        #expect(session.showsChoice)
        #expect(session.pick == nil)
    }

    @Test func theRowGeneralOpensItsFormWithoutPointing() throws {
        let session = FeedbackSession(controller: dryRunController(directory: temporaryDirectory()), scene: nil, settings: .dryRun)
        session.choose(.general)
        #expect(session.phase == .panel)
        #expect(!session.showsChoice)
        #expect(session.kind == .general)
        #expect(session.pick == nil)
    }

    @Test func withOneKindOnThereAreNoRowsToChooseFrom() throws {
        let controller = dryRunController(directory: temporaryDirectory())
        let general = FeedbackSession(controller: controller, scene: nil, settings: RemoteSettings(active: true, general: true, specific: false, texts: [:]))
        #expect(!general.showsChoice && general.kind == .general)
        let specific = FeedbackSession(controller: controller, scene: nil, settings: RemoteSettings(active: true, general: false, specific: true, texts: [:]))
        #expect(!specific.showsChoice && specific.kind == .specific, "with one kind on there is no panel with a single row")
    }

    @Test func aDryRunNeedsNoFetchAndShowsTheTabAtOnce() async throws {
        ConfigStub.reset([.status(500, "")], host: "session.stub.test")
        let controller = dryRunController(directory: temporaryDirectory())
        #expect(controller.settings == .dryRun)
        #expect(controller.isAvailable)
        #expect(ConfigStub.requests(host: "session.stub.test").isEmpty)
        #expect(Nitpick.isAvailable)
    }

    // MARK: Kaders alleen bijhouden als het component open is

    @Test func markersDoNotMeasureWhileTheComponentIsClosed() async throws {
        let registry = NitpickRegistry.shared
        registry.setTracking(false)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        let host = UIHostingController(rootView: VStack { Text("Marked").nitpickElement("tracking.test_element") }.frame(width: 300, height: 500))
        window.rootViewController = host
        window.isHidden = false
        window.layoutIfNeeded()
        let before = registry.frameUpdateCount
        try await Task.sleep(for: .milliseconds(400))
        #expect(registry.frameUpdateCount == before, "the closed component measured frames")
        #expect(registry.pointableElements().filter { $0.name == "tracking.test_element" }.allSatisfy { $0.frame == .zero })

        registry.setTracking(true)
        await wait { registry.pointableElements().contains { $0.name == "tracking.test_element" && $0.frame.width > 0 } }
        let tracked = registry.pointableElements().first { $0.name == "tracking.test_element" }
        #expect(registry.frameUpdateCount > before)
        #expect((tracked?.frame.width ?? 0) > 0, "open: the frame is there")

        registry.setTracking(false)
        #expect(registry.pointableElements().filter { $0.name == "tracking.test_element" }.allSatisfy { $0.frame == .zero }, "closing drops the frames")
        let afterClose = registry.frameUpdateCount
        host.rootView = VStack { Text("Marked and moved").nitpickElement("tracking.test_element") }.frame(width: 200, height: 300)
        try await Task.sleep(for: .milliseconds(300))
        #expect(registry.frameUpdateCount == afterClose)
        window.isHidden = true
        window.rootViewController = nil
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test func openingAndClosingFollowTheRegistry() async throws {
        let controller = dryRunController(directory: temporaryDirectory())
        #expect(!NitpickRegistry.shared.isTracking)
        controller.dismiss()
        #expect(!NitpickRegistry.shared.isTracking)
    }
}
}
