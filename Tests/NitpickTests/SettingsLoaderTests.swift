import Testing
import Foundation
@testable import Nitpick

/// Answers `GET /api/v1/config` from a list, without a network.
final class ConfigStub: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case status(Int, String)
        case fail(URLError.Code)
    }
    /// Replies and requests per host, so suites that run side by side do not take each other's answers.
    nonisolated(unsafe) private static var stores: [String: (replies: [Reply], requests: [URLRequest])] = [:]
    static let defaultHost = "stub.test"
    private static let lock = NSLock()

    static var requests: [URLRequest] { requests(host: defaultHost) }

    static func requests(host: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return stores[host]?.requests ?? []
    }

    static func reset(_ replies: [Reply], host: String = defaultHost) {
        lock.lock(); defer { lock.unlock() }
        stores[host] = (replies, [])
    }

    static func next(for request: URLRequest) -> Reply {
        lock.lock(); defer { lock.unlock() }
        let host = request.url?.host() ?? defaultHost
        var store = stores[host] ?? ([], [])
        store.requests.append(request)
        // The last reply repeats.
        let reply = store.replies.count > 1 ? store.replies.removeFirst() : (store.replies.first ?? .fail(.cannotConnectToHost))
        stores[host] = store
        return reply
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        switch Self.next(for: request) {
        case .status(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Cache-Control": "no-store"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }
    override func stopLoading() {}
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(_ seconds: TimeInterval) { lock.lock(); current = current.addingTimeInterval(seconds); lock.unlock() }
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Duration] = []
    func add(_ value: Duration) { lock.lock(); values.append(value); lock.unlock() }
    var all: [Duration] { lock.lock(); defer { lock.unlock() }; return values }
}

private let okBody = #"{"active":true,"kinds":{"general":true,"specific":false},"texts":{"nl":{"thanks":"Dank je wel!"},"en":{"footer":"Chain test"}}}"#

extension SharedState {
@MainActor
@Suite("Instellingen ophalen", .serialized)
struct SettingsLoaderTests {
    let apiURL = URL(string: "http://stub.test")!
    let clock = TestClock()
    let sleeps = SleepLog()
    let scratch = ScratchDefaults()

    func makeLoader(appKey: String = "npk_abcdefghijklmnopqrstuvwx", replies: [ConfigStub.Reply], clock: TestClock? = nil, defaults: UserDefaults? = nil) -> SettingsLoader {
        ConfigStub.reset(replies)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConfigStub.self]
        let clock = clock ?? self.clock
        let sleeps = self.sleeps
        return SettingsLoader(
            apiURL: apiURL, appKey: appKey, session: URLSession(configuration: configuration),
            defaults: defaults ?? scratch.defaults, now: { clock.now },
            sleep: { sleeps.add($0) }
        )
    }

    func run(_ loader: SettingsLoader, force: Bool = true) async {
        if force { loader.startup() } else { loader.foregrounded() }
        await loader.waitUntilIdle()
    }

    // MARK: 200

    @Test func status200IsKeptAndUsed() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        #expect(loader.settings == nil)
        await run(loader)
        let settings = try #require(loader.settings)
        #expect(settings.active)
        #expect(settings.general && !settings.specific)
        #expect(settings.texts["nl"]?.thanks == "Dank je wel!")
        #expect(settings.texts["en"]?.footer == "Chain test")
        #expect(loader.lastSuccess == clock.now)
        #expect(ConfigStub.requests.count == 1)
        #expect(sleeps.all.isEmpty)
        // Kept under nitpick.config.<sha256(apiURL + appKey)>, with the time of fetching.
        let key = SettingsStore.key(apiURL: apiURL, appKey: "npk_abcdefghijklmnopqrstuvwx")
        #expect(key.hasPrefix("nitpick.config."))
        #expect(key.count == "nitpick.config.".count + 64)
        let stored = try #require(SettingsStore.load(key, from: scratch.defaults))
        #expect(stored.settings == settings)
        #expect(stored.fetchedAt == clock.now)
    }

    @Test func theRequestCarriesOnlyTheKeyAndAcceptWithATenSecondTimeout() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        await run(loader)
        let request = try #require(ConfigStub.requests.first)
        #expect(request.url?.absoluteString == "http://stub.test/api/v1/config")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "X-Nitpick-Key") == "npk_abcdefghijklmnopqrstuvwx")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == ["x-nitpick-key", "accept"])
        #expect(request.timeoutInterval == 10)
        #expect(request.httpBody == nil)
    }

    @Test func aKeptAnswerIsThereAgainAfterARestartWithoutANetwork() async throws {
        let first = makeLoader(replies: [.status(200, okBody)])
        await run(first)
        let second = makeLoader(replies: [.fail(.notConnectedToInternet)])
        #expect(second.settings == first.settings)
        #expect(second.lastSuccess == first.lastSuccess)
        #expect(ConfigStub.requests.isEmpty)
        // Another key or another address has its own keeping place.
        let other = makeLoader(appKey: "npk_zzzzzzzzzzzzzzzzzzzzzzzz", replies: [.status(200, okBody)])
        #expect(other.settings == nil)
        #expect(SettingsStore.key(apiURL: apiURL, appKey: "a") != SettingsStore.key(apiURL: URL(string: "http://other.test")!, appKey: "a"))
    }

    @Test func missingKindsAreOnAndUnknownThingsAreIgnored() throws {
        let body = #"{"active":true,"extra":1,"kinds":{"general":false,"surprise":false},"texts":{"xx":{"footer":"Nope"},"nl":{"footer":"Hoi","thanks":7,"other":"x"},"de":"kaputt","fr":{}}}"#
        let settings = try #require(RemoteSettings.parse(Data(body.utf8)))
        #expect(settings.active)
        #expect(!settings.general)
        #expect(settings.specific)
        #expect(settings.texts.keys.sorted() == ["nl"])
        #expect(settings.texts["nl"] == .init(footer: "Hoi", thanks: nil))
        let none = try #require(RemoteSettings.parse(Data(#"{"active":false}"#.utf8)))
        #expect(!none.active && none.general && none.specific && none.texts.isEmpty)
    }

    @Test func aTextOfMoreThan140CodePointsOrNoStringIsSkipped() throws {
        let long = String(repeating: "a", count: 141)
        let exact = String(repeating: "b", count: 140)
        let body = #"{"active":true,"texts":{"en":{"footer":"\#(long)","thanks":"\#(exact)"},"nl":{"footer":null,"thanks":""}}}"#
        let settings = try #require(RemoteSettings.parse(Data(body.utf8)))
        #expect(settings.texts["en"] == .init(footer: nil, thanks: exact))
        #expect(settings.texts["nl"] == nil)
        // 140 emoji are 140 code points (and 280 UTF-16 units): they fit.
        let emoji = String(repeating: "\u{1F600}", count: 140)
        let ok = try #require(RemoteSettings.parse(Data(#"{"active":true,"texts":{"en":{"footer":"\#(emoji)"}}}"#.utf8)))
        #expect(ok.texts["en"]?.footer == emoji)
    }

    @Test(arguments: ["not json", "[]", "{}", #"{"active":"true"}"#, #"{"active":1}"#, #"{"active":null}"#, ""])
    func anInvalidAnswerCountsAsAServerFault(_ body: String) async {
        let loader = makeLoader(replies: [.status(200, body)])
        await run(loader)
        #expect(loader.settings == nil)
        #expect(loader.lastSuccess == nil)
        #expect(ConfigStub.requests.count == 4, "first try plus 3 retries")
        #expect(sleeps.all == [.seconds(30), .seconds(30), .seconds(30)])
    }

    // MARK: 401, 429, 5xx, no network

    @Test func status401WipesKeptSettingsAndDoesNotRetry() async throws {
        let first = makeLoader(replies: [.status(200, okBody)])
        await run(first)
        let key = first.storageKey
        #expect(SettingsStore.load(key, from: scratch.defaults) != nil)

        let loader = makeLoader(replies: [.status(401, #"{"error":{"code":"invalid_key","message":"Unknown key"}}"#)])
        #expect(loader.settings != nil)
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        await run(loader)
        #expect(loader.settings == nil)
        #expect(loader.lastSuccess == nil)
        #expect(SettingsStore.load(key, from: scratch.defaults) == nil)
        #expect(scratch.defaults.data(forKey: key) == nil)
        #expect(ConfigStub.requests.count == 1)
        #expect(sleeps.all.isEmpty)
        #expect(lines.count == 1 && lines[0].contains("invalid_key"), "one line in the developer log: \(lines)")
    }

    @Test(arguments: [
        ConfigStub.Reply.status(429, #"{"error":{"code":"rate_limited","message":"x"}}"#),
        ConfigStub.Reply.status(500, "oops"),
        ConfigStub.Reply.status(503, ""),
        ConfigStub.Reply.status(404, ""),
        ConfigStub.Reply.fail(.notConnectedToInternet),
        ConfigStub.Reply.fail(.timedOut),
    ])
    func failuresRetryAfter30SecondsAtMostThreeTimes(_ reply: ConfigStub.Reply) async {
        let loader = makeLoader(replies: [reply])
        await run(loader)
        #expect(ConfigStub.requests.count == 4, "first try plus 3 retries")
        #expect(sleeps.all == [.seconds(30), .seconds(30), .seconds(30)])
        #expect(loader.settings == nil, "no settings, so no tab")
        #expect(!loader.isFetching)
    }

    @Test func keptSettingsKeepCountingWhileTheServerFails() async throws {
        let first = makeLoader(replies: [.status(200, okBody)])
        await run(first)
        let loader = makeLoader(replies: [.status(500, "")])
        let kept = try #require(loader.settings)
        await run(loader)
        #expect(loader.settings == kept)
        #expect(loader.lastSuccess == first.lastSuccess)
        #expect(SettingsStore.load(loader.storageKey, from: scratch.defaults)?.settings == kept)
    }

    @Test func aRetryThatSucceedsStopsTheRetrying() async throws {
        let loader = makeLoader(replies: [.status(500, ""), .fail(.timedOut), .status(200, okBody)])
        await run(loader)
        #expect(loader.settings?.active == true)
        #expect(ConfigStub.requests.count == 3)
        #expect(sleeps.all == [.seconds(30), .seconds(30)])
    }

    @Test func afterThreeRetriesTheNextForegroundTries() async throws {
        let loader = makeLoader(replies: [.status(500, "")])
        await run(loader)
        #expect(ConfigStub.requests.count == 4)
        ConfigStub.reset([.status(200, okBody)])
        await run(loader, force: false)   // no successful fetch yet: tries at once
        #expect(ConfigStub.requests.count == 1)
        #expect(loader.settings?.active == true)
    }

    // MARK: When

    @Test func foregroundFetchesOnlyWhenTheAnswerIsOlderThanAnHour() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        await run(loader)
        #expect(ConfigStub.requests.count == 1)
        func foreground(after seconds: TimeInterval) async -> Int {
            ConfigStub.reset([.status(200, okBody)])
            // Time is counted from the last successful fetch.
            let target = loader.lastSuccess!.addingTimeInterval(seconds)
            clock.advance(target.timeIntervalSince(clock.now))
            await run(loader, force: false)
            return ConfigStub.requests.count
        }
        #expect(await foreground(after: 0) == 0)
        #expect(await foreground(after: 3599) == 0)
        #expect(await foreground(after: 3600) == 0, "exactly an hour is not older than an hour")
        #expect(await foreground(after: 3601) == 1, "older than an hour")
        // The fetch moved the time of the last answer: the next foreground right after finds it fresh.
        ConfigStub.reset([.status(200, okBody)])
        await run(loader, force: false)
        #expect(ConfigStub.requests.isEmpty)
    }

    @Test func startupAlwaysFetchesEvenWithAFreshAnswer() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        await run(loader)
        await run(loader)
        #expect(ConfigStub.requests.count == 2)
    }

    @Test func oneFetchAtATime() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        let first = loader.startup()
        let second = loader.startup()
        let third = loader.foregrounded()
        #expect(first != nil && second != nil && third != nil)
        #expect(loader.isFetching)
        await loader.waitUntilIdle()
        #expect(ConfigStub.requests.count == 1)
        #expect(!loader.isFetching)
    }

    // MARK: Not available

    @Test func inactiveIsKeptUntilTheNextValidAnswerAndTheTimeStays() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        await run(loader)
        let fetchedAt = try #require(loader.lastSuccess)
        clock.advance(120)
        loader.markInactive()
        #expect(loader.settings?.active == false)
        #expect(loader.lastSuccess == fetchedAt)
        let again = makeLoader(replies: [.fail(.timedOut)])
        #expect(again.settings?.active == false, "kept over a restart")
        #expect(again.settings?.offersFeedback == false)
        // A valid answer lifts it.
        ConfigStub.reset([.status(200, okBody)])
        await run(again)
        #expect(again.settings?.active == true)
    }

    // MARK: Review: log line for inactive, and a time in the future

    @Test func anInactiveAnswerWritesTheLineOfTheSpecExactlyOnce() async throws {
        let loader = makeLoader(replies: [.status(200, #"{"active":false}"#)])
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        await run(loader)
        #expect(loader.settings?.active == false)
        #expect(lines == ["this account has no active subscription, the tab is hidden."], "\(lines)")
        #expect(ConfigStub.requests.count == 1)
    }

    @Test func anActiveAnswerWritesNoSuchLine() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        var lines: [String] = []
        NitpickLog.recorder = { lines.append($0) }
        defer { NitpickLog.recorder = nil }
        await run(loader)
        #expect(lines.isEmpty, "\(lines)")
    }

    @Test func aTimeInTheFutureCountsAsStale() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        await run(loader)
        #expect(!loader.isStale)
        // The clock of the device was a day ahead when the answer came, and is corrected now.
        clock.advance(-86_400)
        #expect(loader.isStale, "a fetch time that lies ahead of now is stale")
        clock.advance(86_400 + 1)
        #expect(!loader.isStale, "back to normal: one second after the fetch is fresh")
    }

    @Test func afterAClockCorrectionTheForegroundFetchesAgain() async throws {
        let loader = makeLoader(replies: [.status(200, okBody)])
        await run(loader)
        clock.advance(-3 * 3600)   // the clock goes back three hours
        ConfigStub.reset([.status(200, okBody)])
        await run(loader, force: false)
        #expect(ConfigStub.requests.count == 1, "the foreground fetched")
        // The new answer carries the corrected time, so the next foreground right after finds it fresh.
        ConfigStub.reset([.status(200, okBody)])
        await run(loader, force: false)
        #expect(ConfigStub.requests.isEmpty)
    }

    @Test func aStoredTimeInTheFutureIsStaleAfterARestart() async throws {
        let first = makeLoader(replies: [.status(200, okBody)])
        await run(first)
        let key = first.storageKey
        let stored = try #require(SettingsStore.load(key, from: scratch.defaults))
        SettingsStore.save(StoredSettings(settings: stored.settings, fetchedAt: clock.now.addingTimeInterval(86_400)), key: key, to: scratch.defaults)
        let restarted = makeLoader(replies: [.status(200, okBody)])
        #expect(restarted.settings != nil)
        #expect(restarted.isStale)
    }
}
}
