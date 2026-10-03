import Foundation
import CryptoKit

/// The settings of the app as the platform answers `GET /api/v1/config`.
struct RemoteSettings: Codable, Equatable, Sendable {
    struct TextOverrides: Codable, Equatable, Sendable {
        var footer: String?
        var thanks: String?
    }

    var active: Bool
    var general: Bool
    var specific: Bool
    /// Language code to the app's own `footer` and `thanks`.
    var texts: [String: TextOverrides]

    /// What a dry run uses: active, both kinds on, the built-in translations.
    static let dryRun = RemoteSettings(active: true, general: true, specific: true, texts: [:])

    /// Whether there is anything to offer: active, and at least one kind on.
    var offersFeedback: Bool { active && (general || specific) }

    static let maxTextLength = 140

    /// A 200 counts only when the body is a JSON object and `active` is a boolean; otherwise nil.
    /// Unknown fields, languages and kinds are ignored; a missing kind is on; a text that is no string,
    /// is empty or is longer than 140 code points is skipped.
    static func parse(_ data: Data) -> RemoteSettings? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        guard let active = bool(object["active"]) else { return nil }
        let kinds = object["kinds"] as? [String: Any]
        var texts: [String: TextOverrides] = [:]
        if let raw = object["texts"] as? [String: Any] {
            for (language, value) in raw where GeneratedTexts.languages.contains(language) {
                guard let entry = value as? [String: Any] else { continue }
                let overrides = TextOverrides(footer: text(entry["footer"]), thanks: text(entry["thanks"]))
                if overrides.footer != nil || overrides.thanks != nil { texts[language] = overrides }
            }
        }
        return RemoteSettings(active: active, general: bool(kinds?["general"]) ?? true, specific: bool(kinds?["specific"]) ?? true, texts: texts)
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty, string.unicodeScalars.count <= maxTextLength else { return nil }
        return string
    }
}

/// What is kept in `UserDefaults`: the last valid answer and when it was fetched.
struct StoredSettings: Codable, Equatable, Sendable {
    var settings: RemoteSettings
    var fetchedAt: Date
}

enum SettingsStore {
    /// `nitpick.config.<sha256(apiURL + appKey)>`
    static func key(apiURL: URL, appKey: String) -> String {
        let digest = SHA256.hash(data: Data((apiURL.absoluteString + appKey).utf8))
        return "nitpick.config." + digest.map { String(format: "%02x", $0) }.joined()
    }

    static func load(_ key: String, from defaults: UserDefaults) -> StoredSettings? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StoredSettings.self, from: data)
    }

    static func save(_ stored: StoredSettings, key: String, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key) }
    }

    static func remove(_ key: String, from defaults: UserDefaults) {
        defaults.removeObject(forKey: key)
    }
}

/// Fetches the settings of the app and keeps the last valid answer.
///
/// - At startup, and when the app comes back to the foreground with an answer older than an hour (or none): one fetch at a time.
/// - 200: valid answer, kept. 401: the key is unknown, nothing is kept. 429, a server error, an invalid answer or no network:
///   again after 30 seconds, at most 3 times; after that the next return to the foreground tries again.
/// - Network, clock, sleep and storage can be passed in, so tests need no real network or time.
@MainActor
final class SettingsLoader {
    enum Outcome: Equatable { case success, invalidKey, failure }

    static let timeout: TimeInterval = 10
    static let retryDelay: Duration = .seconds(30)
    static let maxRetries = 3
    /// An answer is stale when it is older than this many seconds.
    static let refreshAge: TimeInterval = 3600

    let apiURL: URL
    let appKey: String
    let storageKey: String
    private let session: URLSession
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The settings that count now: the last valid answer, kept or fresh. Nil without any.
    private(set) var settings: RemoteSettings?
    /// When the last valid answer was fetched.
    private(set) var lastSuccess: Date?
    /// Number of requests made, for tests and diagnostics.
    private(set) var requestCount = 0
    /// Called after every change of `settings`.
    var onChange: (@MainActor () -> Void)?
    private var inFlight: Task<Void, Never>?

    var isFetching: Bool { inFlight != nil }

    /// The session that is used outside of tests: no cookies, no cache, a total time limit of 10 seconds.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    init(
        apiURL: URL,
        appKey: String,
        session: URLSession = SettingsLoader.makeSession(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.apiURL = apiURL
        self.appKey = appKey
        self.session = session
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.storageKey = SettingsStore.key(apiURL: apiURL, appKey: appKey)
        if let stored = SettingsStore.load(storageKey, from: defaults) {
            settings = stored.settings
            lastSuccess = stored.fetchedAt
        }
    }

    /// An answer older than an hour, or none yet.
    var isStale: Bool {
        guard let lastSuccess else { return true }
        // A time in the future (the clock was set back after the fetch) counts as stale too.
        let age = now().timeIntervalSince(lastSuccess)
        return age < 0 || age > Self.refreshAge
    }

    /// At startup: always fetch.
    @discardableResult
    func startup() -> Task<Void, Never>? { launch(force: true) }

    /// Back in the foreground: fetch only when the answer is stale.
    @discardableResult
    func foregrounded() -> Task<Void, Never>? { launch(force: false) }

    /// Waits until the running fetch (with its retries) is done.
    func waitUntilIdle() async { await inFlight?.value }

    private func launch(force: Bool) -> Task<Void, Never>? {
        if let inFlight { return inFlight }
        guard force || isStale else { return nil }
        let task = Task { @MainActor [self] in
            await runWithRetries()
            inFlight = nil
        }
        inFlight = task
        return task
    }

    private func runWithRetries() async {
        var retries = 0
        while true {
            switch await fetchOnce() {
            case .success, .invalidKey:
                return
            case .failure:
                guard retries < Self.maxRetries else { return }
                retries += 1
                do { try await sleep(Self.retryDelay) } catch { return }
            }
        }
    }

    func fetchOnce() async -> Outcome {
        requestCount += 1
        var request = URLRequest(url: apiURL.appending(path: "api/v1/config"))
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(appKey, forHTTPHeaderField: "X-Nitpick-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NitpickLog.write("settings: no answer (\((error as NSError).localizedDescription)); trying again later")
            return .failure
        }
        guard let http = response as? HTTPURLResponse else {
            NitpickLog.write("settings: no HTTP answer; trying again later")
            return .failure
        }
        switch http.statusCode {
        case 200:
            guard let parsed = RemoteSettings.parse(data) else {
                NitpickLog.write("settings: the answer is not valid; trying again later")
                return .failure
            }
            if !parsed.active {
                NitpickLog.write("this account has no active subscription, the tab is hidden.")
            }
            let fetchedAt = now()
            settings = parsed
            lastSuccess = fetchedAt
            SettingsStore.save(StoredSettings(settings: parsed, fetchedAt: fetchedAt), key: storageKey, to: defaults)
            onChange?()
            return .success
        case 401:
            NitpickLog.write("settings: the app key is not known (invalid_key); the feedback tab stays off")
            settings = nil
            lastSuccess = nil
            SettingsStore.remove(storageKey, from: defaults)
            onChange?()
            return .invalidKey
        default:
            NitpickLog.write("settings: status \(http.statusCode); trying again later")
            return .failure
        }
    }

    /// The platform said the app is not available (`app_inactive`, `monthly_limit`): keep `active: false`
    /// until the next valid answer. The time of the last answer stays as it was.
    func markInactive() {
        guard var current = settings else { return }
        current.active = false
        settings = current
        if let lastSuccess {
            SettingsStore.save(StoredSettings(settings: current, fetchedAt: lastSuccess), key: storageKey, to: defaults)
        }
        onChange?()
    }
}
