import Foundation

enum SendError: Error, Equatable {
    case invalidKey
    case rejected(String)
    case tooLarge
    case rateLimited
    /// `app_inactive` or `monthly_limit`: feedback cannot be sent now and no retry helps.
    case unavailable(String)
    case network(String)
    case server(Int)
}

/// Sends or stores one finished piece of feedback.
protocol FeedbackTransport: Sendable {
    func send(payload: Data, screenshot: Data?) async throws
}

struct HTTPTransport: FeedbackTransport {
    let apiURL: URL
    let appKey: String
    var session: URLSession = .shared

    func request(payload: Data, screenshot: Data?) -> URLRequest {
        let boundary = Multipart.boundary()
        var request = URLRequest(url: apiURL.appending(path: "api/v1/feedback"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(appKey, forHTTPHeaderField: "X-Nitpick-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Multipart.body(boundary: boundary, payload: payload, screenshot: screenshot)
        return request
    }

    func send(payload: Data, screenshot: Data?) async throws {
        let request = request(payload: payload, screenshot: screenshot)
        let response: URLResponse
        let body: Data
        do {
            (body, response) = try await session.data(for: request)
        } catch {
            throw SendError.network((error as NSError).localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SendError.network("No response") }
        if (200...299).contains(http.statusCode) { return }
        // Look at `error.code`, not only at the status.
        let error = Self.error(in: body)
        if let code = error.code, Self.unavailableCodes.contains(code) { throw SendError.unavailable(code) }
        switch http.statusCode {
        case 400: throw SendError.rejected(error.message ?? "")
        case 401: throw SendError.invalidKey
        case 413: throw SendError.tooLarge
        case 429: throw SendError.rateLimited
        default: throw SendError.server(http.statusCode)
        }
    }

    /// The platform says: this app takes no feedback now.
    static let unavailableCodes: Set<String> = ["app_inactive", "monthly_limit"]

    static func error(in body: Data) -> (code: String?, message: String?) {
        struct Envelope: Decodable {
            struct Err: Decodable { var code: String?; var message: String? }
            var error: Err?
        }
        let error = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        return (error?.code, error?.message)
    }
}

/// Writes payload and image to disk instead of sending (`dryRun`).
struct DryRunTransport: FeedbackTransport {
    let directory: URL

    static func defaultDirectory() -> URL {
        URL.documentsDirectory.appending(path: "nitpick-dryrun", directoryHint: .isDirectory)
    }

    func send(payload: Data, screenshot: Data?) async throws {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let folder = directory.appending(path: "\(stamp)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try payload.write(to: folder.appending(path: "payload.json"))
            if let screenshot {
                try screenshot.write(to: folder.appending(path: "screenshot.jpg"))
            }
        } catch {
            throw SendError.network((error as NSError).localizedDescription)
        }
        await MainActor.run { DiagnosticsStore.shared.lastDryRunPath = folder.path }
    }
}
