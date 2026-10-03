import Foundation
import os

/// One line in the developer log (Console, Xcode). Never shown to the end user.
@MainActor
enum NitpickLog {
    /// Tests collect the lines here.
    static var recorder: ((String) -> Void)?
    private static let logger = Logger(subsystem: "nitpick", category: "component")

    static func write(_ message: String) {
        recorder?(message)
        logger.notice("Nitpick: \(message, privacy: .public)")
    }
}
