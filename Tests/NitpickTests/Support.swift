import Foundation
import CryptoKit
import Testing

/// Reads the shared files in `packages/teksten` from the repository, found from this file's path.
enum Teksten {
    static var directory: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // Support.swift, NitpickTests, Tests, swift
        return url.appending(path: "teksten", directoryHint: .isDirectory)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: name))
    }

    static func json(_ name: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: data(name)) as! [String: Any]
    }

    static func texts(_ code: String) throws -> [String: String] {
        try json("\(code).json")["texts"] as! [String: String]
    }

    /// The package folder `packages/swift`.
    static var packageDirectory: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }
}

/// A scratch `UserDefaults` that is removed afterwards.
final class ScratchDefaults {
    let suiteName = "nitpick-test-\(UUID().uuidString)"
    let defaults: UserDefaults
    init() { defaults = UserDefaults(suiteName: suiteName)! }
    deinit { defaults.removePersistentDomain(forName: suiteName) }
}

/// The parent of every suite that uses the shared parts of the component (the availability, the developer log, the registry).
/// `.serialized` on a suite orders only the tests inside it, and suites run side by side; on a parent it holds for all suites
/// inside, so these suites never run at the same time.
@Suite("Gedeelde onderdelen van het component", .serialized)
enum SharedState {}
