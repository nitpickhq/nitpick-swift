import Testing
import Foundation
import UIKit
@testable import Nitpick

/// Answers `GET /api/v1/config` from a list after a short delay, without a network. Its own counters,
/// so these tests do not share state with the other suites that stub the network.
final class ForegroundStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var replies: [(Int, String)] = []
    nonisolated(unsafe) static var requestCount = 0
    private static let lock = NSLock()

    static func reset(_ replies: [(Int, String)]) {
        lock.lock(); defer { lock.unlock() }
        self.replies = replies
        requestCount = 0
    }

    static func next() -> (Int, String) {
        lock.lock(); defer { lock.unlock() }
        requestCount += 1
        return replies.count > 1 ? replies.removeFirst() : (replies.first ?? (500, ""))
    }

    static var count: Int { lock.lock(); defer { lock.unlock() }; return requestCount }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.next()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Cache-Control": "no-store"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

/// The step "back to the foreground": the app posts `willEnterForegroundNotification`; the component then
/// fetches its settings again only when the last successful answer is older than an hour, or there is none.
extension SharedState {
@MainActor
@Suite("Terug naar de voorgrond", .serialized)
struct ForegroundTests {
    let apiURL = URL(string: "http://foreground.test")!
    let appKey = "npk_foreground0000000000000"
    let clock = TestClock()
    let scratch = ScratchDefaults()
    static let active = #"{"active":true}"#

    /// A controller whose loader takes the injected clock, the URLProtocol stub and a scratch store.
    /// `loaders` counts how often a loader is made.
    func makeController(loaders: LoaderCounter = LoaderCounter()) -> NitpickController {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ForegroundStub.self]
        let session = URLSession(configuration: configuration)
        let defaults = scratch.defaults
        let clock = clock
        let controller = NitpickController()
        controller.makeLoader = { url, key in
            loaders.count += 1
            return SettingsLoader(apiURL: url, appKey: key, session: session, defaults: defaults, now: { clock.now }, sleep: { _ in throw CancellationError() })
        }
        return controller
    }

    final class LoaderCounter { var count = 0 }

    func configure(_ controller: NitpickController) {
        controller.configure(appKey: appKey, options: NitpickOptions(apiURL: apiURL))
    }

    func enterForeground() {
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    func wait(until condition: () -> Bool, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(25)) }
    }

    /// Long enough for a notification, its task and a request of 50 ms to have happened if they were going to.
    func settle() async { try? await Task.sleep(for: .milliseconds(400)) }

    @Test func comingBackFetchesAgainOnlyWhenTheLastSuccessIsOlderThanAnHour() async throws {
        ForegroundStub.reset([(200, Self.active)])
        let controller = makeController()
        configure(controller)
        await wait { ForegroundStub.count == 1 && controller.isAvailable }
        #expect(ForegroundStub.count == 1, "startup fetches at once")
        #expect(controller.isAvailable)

        enterForeground()
        await settle()
        #expect(ForegroundStub.count == 1, "a fresh answer: nothing to fetch")

        clock.advance(3600)
        enterForeground()
        await settle()
        #expect(ForegroundStub.count == 1, "exactly one hour is not older than an hour")

        clock.advance(1)
        enterForeground()
        await wait { ForegroundStub.count == 2 }
        await settle()
        #expect(ForegroundStub.count == 2, "3601 seconds: fetch again")

        enterForeground()
        await settle()
        #expect(ForegroundStub.count == 2, "the new answer is fresh again")
    }

    @Test func comingBackFetchesWhenThereWasNoSuccessYet() async throws {
        ForegroundStub.reset([(500, ""), (200, Self.active)])
        let controller = makeController()
        configure(controller)
        await wait { ForegroundStub.count == 1 }
        await settle()
        #expect(ForegroundStub.count == 1, "the retries are cancelled here: one failed request")
        #expect(controller.settings == nil)
        #expect(!controller.isAvailable)

        // No time passes at all: with no answer at all the foreground fetches anyway.
        enterForeground()
        await wait { controller.isAvailable }
        #expect(ForegroundStub.count == 2)
        #expect(controller.isAvailable)

        enterForeground()
        await settle()
        #expect(ForegroundStub.count == 2, "now there is an answer, so there is nothing to fetch")
    }

    @Test func itHappensOnceForTheAppHoweverOftenItIsConfiguredOrNotified() async throws {
        ForegroundStub.reset([(200, Self.active)])
        let loaders = LoaderCounter()
        let controller = makeController(loaders: loaders)
        configure(controller)
        configure(controller)
        configure(controller)
        await wait { ForegroundStub.count == 1 && controller.isAvailable }
        await settle()
        #expect(loaders.count == 1, "one loader per app key and address")
        #expect(ForegroundStub.count == 1, "configuring again with a fresh answer fetches nothing")

        clock.advance(3601)
        enterForeground()
        enterForeground()
        enterForeground()
        await wait { ForegroundStub.count >= 2 }
        await settle()
        #expect(ForegroundStub.count == 2, "three notifications at once: one fetch")
    }
}
}
