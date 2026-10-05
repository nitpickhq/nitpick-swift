import Foundation
import CoreGraphics

/// The JSON that goes to `POST /api/v1/feedback`, field for field as in the API agreement (v1).
/// Fields the device does not know are left out; the platform reads a missing field as null.
struct FeedbackPayload: Codable, Equatable, Sendable {
    struct Frame: Codable, Equatable, Sendable {
        var x: Double, y: Double, width: Double, height: Double
        init(_ rect: CGRect) {
            x = rect.origin.x; y = rect.origin.y; width = rect.size.width; height = rect.size.height
        }
    }
    struct Point: Codable, Equatable, Sendable {
        var x: Double, y: Double
        init(_ point: CGPoint) { x = point.x; y = point.y }
    }
    struct Viewport: Codable, Equatable, Sendable {
        var width: Double, height: Double, scale: Double
    }
    struct SDK: Codable, Equatable, Sendable {
        var name: String
        var version: String
    }
    struct Device: Codable, Equatable, Sendable {
        var model: String?
        var osVersion: String?
        var locale: String?
        enum CodingKeys: String, CodingKey { case model, osVersion = "os_version", locale }
    }

    var kind: String
    var comment: String?
    var screen: String?
    var element: String?
    var elementMatch: String?
    var elementFrame: Frame?
    var tap: Point?
    var viewport: Viewport?
    var platform: String
    var sdk: SDK
    var appVersion: String?
    var build: String?
    var device: Device
    var clientTS: String?

    enum CodingKeys: String, CodingKey {
        case kind, comment, screen, element
        case elementMatch = "element_match"
        case elementFrame = "element_frame"
        case tap, viewport, platform, sdk
        case appVersion = "app_version"
        case build, device
        case clientTS = "client_ts"
    }

    static let sdkName = "swift"
    static let sdkVersion = "0.3.1"

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Facts about the device and the app. Never the device name the user chose.
struct DeviceFacts: Sendable, Equatable {
    var model: String?
    var osVersion: String?
    var locale: String?
    var appVersion: String?
    var build: String?

    /// Hardware identifier such as `iPhone16,1`. On the simulator that is the model of the Mac host,
    /// so the simulator's own identifier is used.
    static func modelIdentifier() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        return machine
    }

    @MainActor
    static func current(bundle: Bundle = .main) -> DeviceFacts {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceFacts(
            model: modelIdentifier(),
            osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            locale: Locale.current.identifier,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }
}

enum PayloadFactory {
    static func general(comment: String, screen: String?, facts: DeviceFacts, now: Date = Date()) -> FeedbackPayload {
        FeedbackPayload(
            kind: "general", comment: trimmed(comment), screen: screen,
            platform: "ios", sdk: .init(name: FeedbackPayload.sdkName, version: FeedbackPayload.sdkVersion),
            appVersion: facts.appVersion, build: facts.build,
            device: .init(model: facts.model, osVersion: facts.osVersion, locale: facts.locale),
            clientTS: timestamp(now)
        )
    }

    static func specific(comment: String, pick: PickedTarget, facts: DeviceFacts, now: Date = Date()) -> FeedbackPayload {
        FeedbackPayload(
            kind: "specific", comment: trimmed(comment), screen: pick.screen,
            element: pick.element?.name, elementMatch: pick.match.rawValue,
            elementFrame: pick.element.map { .init($0.frame) },
            tap: .init(pick.tap),
            viewport: .init(width: pick.viewport.width, height: pick.viewport.height, scale: pick.scale),
            platform: "ios", sdk: .init(name: FeedbackPayload.sdkName, version: FeedbackPayload.sdkVersion),
            appVersion: facts.appVersion, build: facts.build,
            device: .init(model: facts.model, osVersion: facts.osVersion, locale: facts.locale),
            clientTS: timestamp(now)
        )
    }

    private static func trimmed(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : String(value.prefix(2000))
    }

    static func timestamp(_ date: Date) -> String {
        date.ISO8601Format(.init(includingFractionalSeconds: true))
    }
}

/// The outcome of one tap in the pointing layer.
struct PickedTarget: Sendable, Equatable {
    var tap: CGPoint
    var element: MarkedElement?
    var match: MatchKind
    var screen: String?
    var viewport: CGSize
    var scale: Double
}

/// Builds `multipart/form-data` by hand; no third-party code.
enum Multipart {
    static func boundary() -> String { "nitpick-" + UUID().uuidString }

    static func body(boundary: String, payload: Data, screenshot: Data?) -> Data {
        var data = Data()
        func add(_ string: String) { data.append(Data(string.utf8)) }
        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"payload\"\r\n")
        add("Content-Type: application/json\r\n\r\n")
        data.append(payload)
        add("\r\n")
        if let screenshot {
            add("--\(boundary)\r\n")
            add("Content-Disposition: form-data; name=\"screenshot\"; filename=\"screenshot.jpg\"\r\n")
            add("Content-Type: image/jpeg\r\n\r\n")
            data.append(screenshot)
            add("\r\n")
        }
        add("--\(boundary)--\r\n")
        return data
    }
}
