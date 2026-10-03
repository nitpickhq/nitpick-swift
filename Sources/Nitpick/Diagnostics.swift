import Foundation

/// A snapshot of what the component is doing. Read-only; for tests and for measuring.
public struct NitpickDiagnostics: Sendable, Equatable {
    /// Marked elements and masks that are on screen now.
    public var registeredElements: Int
    /// Frame updates received since launch (grows while a list scrolls).
    public var frameUpdates: Int
    /// Name of the screen that counts as current.
    public var currentScreen: String?
    /// Time to find the element for one tap, in milliseconds.
    public var lastPickMilliseconds: Double?
    /// Time to make the picture, in milliseconds.
    public var lastCaptureMilliseconds: Double?
    /// Folder of the last dry run.
    public var lastDryRunPath: String?
    /// Size of the last picture in bytes and pixels.
    public var lastScreenshotBytes: Int?
    public var lastScreenshotPixels: String?
    /// Whether `drawHierarchy` reported a complete drawing for the last picture.
    public var lastCaptureComplete: Bool?
}

@MainActor
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()
    var lastPickMilliseconds: Double?
    var lastCaptureMilliseconds: Double?
    var lastDryRunPath: String?
    var lastScreenshotBytes: Int?
    var lastScreenshotPixels: String?
    var lastCaptureComplete: Bool?

    func snapshot() -> NitpickDiagnostics {
        let registry = NitpickRegistry.shared
        return NitpickDiagnostics(
            registeredElements: registry.elements.count,
            frameUpdates: registry.frameUpdateCount,
            currentScreen: registry.currentScreen?.name,
            lastPickMilliseconds: lastPickMilliseconds,
            lastCaptureMilliseconds: lastCaptureMilliseconds,
            lastDryRunPath: lastDryRunPath,
            lastScreenshotBytes: lastScreenshotBytes,
            lastScreenshotPixels: lastScreenshotPixels,
            lastCaptureComplete: lastCaptureComplete
        )
    }
}
