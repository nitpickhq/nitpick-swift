import SwiftUI
import UIKit

/// Nitpick: in-app feedback where users point at the exact thing that bugs them.
///
///     @main struct MyApp: App {
///         init() { Nitpick.configure(appKey: "npk_...") }
///         var body: some Scene { WindowGroup { RootView() } }
///     }
public enum Nitpick {
    /// Version of this component. Sent as `sdk.version`.
    public static let version = FeedbackPayload.sdkVersion

    /// Call once at launch. Installs the edge tab (unless you turn it off) in every window scene.
    /// When the app starts, the component asks Nitpick for the feedback settings of your app
    /// (which kinds are on, and two texts). That request carries nothing about the user or the device.
    /// The tab shows once there are settings. Nothing else is captured or sent until the user opens the panel and taps Send.
    @MainActor
    public static func configure(appKey: String, options: NitpickOptions = NitpickOptions()) {
        NitpickController.shared.configure(appKey: appKey, options: options)
    }

    /// Whether the component offers feedback now: there are settings, the app is active and at least one kind is on.
    /// Observable: a SwiftUI view that reads it updates when it changes. Use it to hide your own button.
    @MainActor
    public static var isAvailable: Bool {
        NitpickAvailability.shared.isAvailable
    }

    /// Opens the panel, for example from your own button. Works with `showsTab: false`.
    /// Does nothing (and writes one line in the developer log) when `isAvailable` is false.
    @MainActor
    public static func present() {
        NitpickController.shared.present()
    }

    /// Closes the panel and any pointing in progress.
    @MainActor
    public static func dismiss() {
        NitpickController.shared.dismiss()
    }

    /// What the component is doing right now. Read-only.
    @MainActor
    public static var diagnostics: NitpickDiagnostics {
        DiagnosticsStore.shared.snapshot()
    }

    @MainActor
    static func attachIfNeeded() {
        NitpickController.shared.attach()
    }
}
