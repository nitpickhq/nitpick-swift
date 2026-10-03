import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import Nitpick

private let facts = DeviceFacts(model: "iPhone17,3", osVersion: "18.6.0", locale: "nl_NL", appVersion: "1.4.2", build: "87")

private func keys(_ data: Data) throws -> Set<String> {
    let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    return Set(object.keys)
}

private func specificPayload(comment: String = "Knop te klein") -> FeedbackPayload {
    let element = MarkedElement(id: UUID(), name: "checkout.pay_button", kind: .element, frame: CGRect(x: 20, y: 700, width: 350, height: 52), screenID: nil)
    let pick = PickedTarget(tap: CGPoint(x: 100, y: 720), element: element, match: .exact, screen: "Checkout", viewport: CGSize(width: 393, height: 852), scale: 3)
    return PayloadFactory.specific(comment: comment, pick: pick, facts: facts)
}

@MainActor
@Suite("Payload en multipart volgens afspraak API v1")
struct PayloadTests {
    @Test func specificPayloadHasExactlyTheAgreedFieldNames() throws {
        let json = try specificPayload().jsonData()
        let expected: Set<String> = ["kind", "comment", "screen", "element", "element_match", "element_frame", "tap", "viewport", "platform", "sdk", "app_version", "build", "device", "client_ts"]
        #expect(try keys(json) == expected)
        let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        #expect(Set((object["element_frame"] as! [String: Any]).keys) == ["x", "y", "width", "height"])
        #expect(Set((object["tap"] as! [String: Any]).keys) == ["x", "y"])
        #expect(Set((object["viewport"] as! [String: Any]).keys) == ["width", "height", "scale"])
        #expect(Set((object["device"] as! [String: Any]).keys) == ["model", "os_version", "locale"])
        #expect(Set((object["sdk"] as! [String: Any]).keys) == ["name", "version"])
    }

    @Test func specificValues() throws {
        let object = try JSONSerialization.jsonObject(with: specificPayload().jsonData()) as! [String: Any]
        #expect(object["kind"] as? String == "specific")
        #expect(object["element_match"] as? String == "exact")
        #expect(object["element"] as? String == "checkout.pay_button")
        #expect(object["screen"] as? String == "Checkout")
        #expect(object["platform"] as? String == "ios")
        #expect(object["score"] == nil)
        let viewport = object["viewport"] as! [String: Double]
        #expect(viewport == ["width": 393, "height": 852, "scale": 3])
    }

    @Test func sdkIsSwiftZeroTwoZero() throws {
        let object = try JSONSerialization.jsonObject(with: specificPayload().jsonData()) as! [String: Any]
        let sdk = object["sdk"] as! [String: String]
        #expect(sdk == ["name": "swift", "version": "0.2.0"])
        #expect(Nitpick.version == "0.2.0")
    }

    @Test func payloadHasNoScoreForEitherKind() throws {
        let general = try PayloadFactory.general(comment: "Mooi", screen: "Home", facts: facts).jsonData()
        let specific = try specificPayload().jsonData()
        for json in [general, specific] {
            let object = try JSONSerialization.jsonObject(with: json) as! [String: Any]
            #expect(object["score"] == nil)
            #expect(!String(decoding: json, as: UTF8.self).contains("score"))
        }
        let expected: Set<String> = ["kind", "comment", "screen", "platform", "sdk", "app_version", "build", "device", "client_ts"]
        #expect(try keys(general) == expected)
    }

    @Test func generalPayloadCarriesTheCommentAndNoPointingFields() throws {
        let payload = PayloadFactory.general(comment: "  Mooi  ", screen: "Home", facts: facts)
        let object = try JSONSerialization.jsonObject(with: payload.jsonData()) as! [String: Any]
        #expect(object["kind"] as? String == "general")
        #expect(object["comment"] as? String == "Mooi")
        #expect(object["tap"] == nil && object["element"] == nil && object["element_match"] == nil && object["element_frame"] == nil && object["viewport"] == nil)
    }

    @Test func nearestAndNoneMatchesAreWritten() throws {
        var pick = PickedTarget(tap: CGPoint(x: 1, y: 1), element: nil, match: .none, screen: nil, viewport: CGSize(width: 10, height: 10), scale: 2)
        var object = try JSONSerialization.jsonObject(with: PayloadFactory.specific(comment: "x", pick: pick, facts: facts).jsonData()) as! [String: Any]
        #expect(object["element_match"] as? String == "none")
        #expect(object["element"] == nil)
        pick.match = .nearest
        object = try JSONSerialization.jsonObject(with: PayloadFactory.specific(comment: "x", pick: pick, facts: facts).jsonData()) as! [String: Any]
        #expect(object["element_match"] as? String == "nearest")
    }

    @Test func commentIsTrimmedAndCappedAt2000() {
        #expect(PayloadFactory.general(comment: "   ", screen: nil, facts: facts).comment == nil)
        let long = String(repeating: "a", count: 2500)
        #expect(PayloadFactory.general(comment: long, screen: nil, facts: facts).comment?.count == 2000)
    }

    @Test func deviceCarriesNoDeviceName() throws {
        let json = String(decoding: try specificPayload().jsonData(), as: UTF8.self)
        #expect(!json.contains(UIDevice.current.name))
        let current = DeviceFacts.current()
        #expect(current.model?.hasPrefix("iPhone") == true || current.model?.hasPrefix("iPad") == true)
        #expect(current.model != UIDevice.current.name)
    }

    @Test func timestampIsISO8601() {
        let stamp = PayloadFactory.timestamp(Date(timeIntervalSince1970: 0))
        #expect(stamp == "1970-01-01T00:00:00.000Z")
    }
}

@MainActor
@Suite("Multipart en versturen")
struct MultipartTests {
    @Test func bodyIsValidMultipartWithPayloadAndScreenshot() throws {
        let boundary = "BOUNDARY"
        let payload = Data("{\"kind\":\"general\"}".utf8)
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let body = Multipart.body(boundary: boundary, payload: payload, screenshot: jpeg)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.hasPrefix("--BOUNDARY\r\n"))
        #expect(text.hasSuffix("\r\n--BOUNDARY--\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"payload\"\r\nContent-Type: application/json\r\n\r\n{\"kind\":\"general\"}\r\n--BOUNDARY\r\n"))
        #expect(text.contains("name=\"screenshot\"; filename=\"screenshot.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        // Two parts plus the closing line: three boundary markers.
        #expect(text.components(separatedBy: "--BOUNDARY").count - 1 == 3)
        // The binary data is in there byte for byte.
        #expect(body.range(of: jpeg) != nil)
    }

    @Test func bodyWithoutScreenshotHasOnePart() {
        let body = Multipart.body(boundary: "B", payload: Data("{}".utf8), screenshot: nil)
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("screenshot"))
        #expect(text.components(separatedBy: "--B").count - 1 == 2)
    }

    @Test func requestHasKeyUrlAndContentType() throws {
        let transport = HTTPTransport(apiURL: URL(string: "http://localhost:3000")!, appKey: "npk_test")
        let request = transport.request(payload: Data("{}".utf8), screenshot: nil)
        #expect(request.url?.absoluteString == "http://localhost:3000/api/v1/feedback")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Nitpick-Key") == "npk_test")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=nitpick-") == true)
    }

    @Test func dryRunWritesPayloadAndImage() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "nitpick-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try await DryRunTransport(directory: dir).send(payload: Data("{\"a\":1}".utf8), screenshot: Data([1, 2, 3]))
        let folders = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        #expect(folders.count == 1)
        #expect(try Data(contentsOf: folders[0].appending(path: "payload.json")) == Data("{\"a\":1}".utf8))
        #expect(try Data(contentsOf: folders[0].appending(path: "screenshot.jpg")) == Data([1, 2, 3]))
        #expect(DiagnosticsStore.shared.lastDryRunPath?.hasPrefix(dir.path) == true)
    }

    @Test func serverAnswersMapToErrors() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let transport = HTTPTransport(apiURL: URL(string: "http://stub.test")!, appKey: "npk_x", session: URLSession(configuration: config))

        StubProtocol.status = 201
        try await transport.send(payload: Data("{}".utf8), screenshot: nil)

        StubProtocol.status = 401
        await #expect(throws: SendError.invalidKey) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        StubProtocol.status = 429
        await #expect(throws: SendError.rateLimited) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        // The component looks at `error.code`, not only at the status.
        StubProtocol.status = 429
        StubProtocol.body = Data("{\"error\":{\"code\":\"rate_limited\",\"message\":\"slow down\"}}".utf8)
        await #expect(throws: SendError.rateLimited) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        StubProtocol.status = 403
        StubProtocol.body = Data("{\"error\":{\"code\":\"app_inactive\",\"message\":\"Subscription ended\"}}".utf8)
        await #expect(throws: SendError.unavailable("app_inactive")) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        StubProtocol.status = 429
        StubProtocol.body = Data("{\"error\":{\"code\":\"monthly_limit\",\"message\":\"limit\"}}".utf8)
        await #expect(throws: SendError.unavailable("monthly_limit")) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        StubProtocol.status = 403
        StubProtocol.body = Data("{}".utf8)
        await #expect(throws: SendError.server(403)) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        StubProtocol.body = Data("{}".utf8)
        StubProtocol.status = 413
        await #expect(throws: SendError.tooLarge) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
        StubProtocol.status = 400
        StubProtocol.body = Data("{\"error\":{\"code\":\"invalid_payload\",\"message\":\"comment required\"}}".utf8)
        await #expect(throws: SendError.rejected("comment required")) { try await transport.send(payload: Data("{}".utf8), screenshot: nil) }
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 201
    nonisolated(unsafe) static var body = Data("{}".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
