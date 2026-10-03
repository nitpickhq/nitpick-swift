import SwiftUI
import UIKit

/// A window that lets touches through unless they land on something the component drew.
final class NitpickWindow: UIWindow {
    /// When set, only touches inside this area (computed from the window size) are taken;
    /// all others fall through to the app. SwiftUI's hosting view answers for its whole area,
    /// so the window cannot tell empty space from the button by itself.
    var interactiveArea: ((CGSize) -> CGRect)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let interactiveArea, !interactiveArea(bounds.size).insetBy(dx: -4, dy: -4).contains(point) {
            return nil
        }
        return super.hitTest(point, with: event)
    }
}

/// What the host app can read: whether the component offers feedback now.
@MainActor
@Observable
final class NitpickAvailability {
    @ObservationIgnored static let shared = NitpickAvailability()
    var isAvailable = false
}

@MainActor
final class NitpickController {
    static let shared = NitpickController()

    private(set) var appKey: String?
    private(set) var options = NitpickOptions()
    /// The settings that count now. Nil until there is an answer or kept settings; a dry run uses the standard.
    private(set) var settings: RemoteSettings?
    /// What a tab window was built with: when it is the same, an activation leaves the window alone.
    struct TabSignature: Equatable {
        var look: NitpickLook
        var label: String
        var edge: NitpickTabEdge
        var verticalPosition: Double
    }
    struct TabEntry {
        var window: NitpickWindow
        var signature: TabSignature
    }
    /// The tab window per scene. Removed when the scene disconnects; an entry that belongs to another scene is never used.
    let tabWindows = SceneTable<UIWindowScene, TabEntry> { entry in
        entry.window.isHidden = true
        entry.window.rootViewController = nil
    }
    private var sessionWindow: NitpickWindow?
    /// The open session. Internal to the module so tests can put one in place; only the controller sets it otherwise.
    var session: FeedbackSession?
    private var observing = false
    private var loader: SettingsLoader?
    /// One loader per app key and API address, shared over calls of `configure`.
    private var loaders: [String: SettingsLoader] = [:]
    /// The registration for light and dark per scene, with the app window it was made on.
    struct StyleObservation {
        weak var window: UIWindow?
        var registration: UITraitChangeRegistration
    }
    let styleObservations = SceneTable<UIWindowScene, StyleObservation> { observation in
        if let window = observation.window { window.unregisterForTraitChanges(observation.registration) }
    }

    /// Tests replace these.
    var preferredLanguages: () -> [String] = { Locale.preferredLanguages }
    var makeLoader: (URL, String) -> SettingsLoader = { SettingsLoader(apiURL: $0, appKey: $1) }
    var transportOverride: (() -> any FeedbackTransport)?

    init() {}

    /// The language of the panel: the forced one (tests), otherwise the first that fits the device.
    var language: String {
        if let forced = options.language, NitpickLanguage.supported.contains(forced) { return forced }
        return NitpickLanguage.resolve(preferred: preferredLanguages())
    }

    func texts(for settings: RemoteSettings?) -> NitpickTexts {
        let language = language
        return NitpickTexts(language: language, overrides: settings?.texts[language])
    }

    var look: NitpickLook { NitpickLook(theme: options.theme, language: language) }
    var isConfigured: Bool { appKey != nil }
    /// Whether there is anything to offer: settings that are active, with at least one kind on.
    var isAvailable: Bool { settings?.offersFeedback ?? false }

    // MARK: Setup

    func configure(appKey: String, options: NitpickOptions) {
        self.appKey = appKey
        self.options = options
        closeSession()
        tabWindows.removeAll()
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.attach() }
            }
            NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIWindowScene else { return }
                Task { @MainActor in self?.sceneDisconnected(scene) }
            }
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.loader?.foregrounded() }
            }
        }
        loader?.onChange = nil
        if options.dryRun {
            // A dry run fetches nothing: active, both kinds on, the built-in translations.
            loader = nil
            settings = .dryRun
        } else {
            let key = SettingsStore.key(apiURL: options.apiURL, appKey: appKey)
            let created: Bool
            if let existing = loaders[key] {
                loader = existing
                created = false
            } else {
                let fresh = makeLoader(options.apiURL, appKey)
                loaders[key] = fresh
                loader = fresh
                created = true
            }
            settings = loader?.settings
            loader?.onChange = { [weak self] in self?.settingsChanged() }
            // At startup always; a second call of `configure` follows the rule for the foreground.
            if created { loader?.startup() } else { loader?.foregrounded() }
        }
        refresh()
    }

    private func settingsChanged() {
        settings = loader?.settings
        refresh()
    }

    /// Applies new settings in tests.
    func apply(settings: RemoteSettings?) {
        self.settings = settings
        refresh()
    }

    /// The platform said the app is not available: keep `active: false` until the next valid answer.
    func markUnavailable() {
        if let loader {
            loader.markInactive()
            settings = loader.settings
        } else {
            settings?.active = false
        }
        refresh()
    }

    private func refresh() {
        NitpickAvailability.shared.isAvailable = isAvailable
        attach()
    }

    /// Shows the tab in every window scene when there is something to offer, the tab is on and the
    /// component is closed; hides it otherwise. A new answer counts at once when the component is closed.
    func attach() {
        guard isConfigured else { return }
        tabWindows.prune()
        styleObservations.prune()
        let show = options.showsTab && isAvailable && session == nil
        guard show else {
            for entry in tabWindows.values { entry.window.isHidden = true }
            return
        }
        let signature = TabSignature(look: look, label: texts(for: settings).tabLabel, edge: options.tabEdge, verticalPosition: options.tabVerticalPosition)
        for scene in windowScenes() {
            observeAppStyle(in: scene)
            guard scene.activationState != .unattached else { continue }
            if var entry = tabWindows.value(for: scene) {
                // The window and its hosting controller stay; only a changed label or look is passed on.
                if refreshTab(&entry, to: signature) { tabWindows.set(entry, for: scene) }
                entry.window.overrideUserInterfaceStyle = appStyle(in: scene)
                entry.window.isHidden = false
            } else {
                let window = NitpickWindow(windowScene: scene)
                window.overrideUserInterfaceStyle = appStyle(in: scene)
                tabWindows.set(installTab(in: window, signature: signature), for: scene)
            }
        }
    }

    /// Puts the tab in a new window: the hosting controller is made here, once for the life of the window.
    func installTab(in window: NitpickWindow, signature: TabSignature) -> TabEntry {
        window.interactiveArea = Self.interactiveArea(for: signature)
        window.windowLevel = UIWindow.Level(rawValue: 900)
        window.backgroundColor = .clear
        let host = UIHostingController(rootView: tabLayer(signature))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        return TabEntry(window: window, signature: signature)
    }

    /// Passes a changed label or look to the tab that is already there, in the same hosting controller.
    /// Returns whether anything changed; with the same signature nothing is touched.
    @discardableResult
    func refreshTab(_ entry: inout TabEntry, to signature: TabSignature) -> Bool {
        guard entry.signature != signature else { return false }
        entry.window.interactiveArea = Self.interactiveArea(for: signature)
        (entry.window.rootViewController as? UIHostingController<EdgeTabLayer>)?.rootView = tabLayer(signature)
        entry.signature = signature
        return true
    }

    private static func interactiveArea(for signature: TabSignature) -> (CGSize) -> CGRect {
        { size in
            TabGeometry.rect(in: size, tab: TabGeometry.size, edge: signature.edge, verticalPosition: signature.verticalPosition)
        }
    }

    private func tabLayer(_ signature: TabSignature) -> EdgeTabLayer {
        EdgeTabLayer(look: signature.look, label: signature.label, edge: signature.edge, verticalPosition: signature.verticalPosition) {
            Nitpick.present()
        }
    }

    /// The scene is gone: its tab window and its registration for light and dark go with it, and so does a panel that was open in it.
    func sceneDisconnected(_ scene: UIWindowScene) {
        tabWindows.remove(scene)
        styleObservations.remove(scene)
        // A panel that was open in this scene (its window has lost the scene already) closes with it.
        if session != nil, sessionWindow?.windowScene === scene || sessionWindow?.windowScene == nil { dismiss() }
    }

    private func windowScenes() -> [UIWindowScene] {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    }

    private func activeScene() -> UIWindowScene? {
        let scenes = windowScenes()
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }

    /// The app's own window in a scene: never one of ours.
    func appWindow(in scene: UIWindowScene) -> UIWindow? {
        let candidates = scene.windows.filter { !($0 is NitpickWindow) && !$0.isHidden }
        return candidates.first { $0.isKeyWindow } ?? candidates.first { $0.windowLevel == .normal } ?? candidates.first
    }

    // MARK: Light and dark

    /// Our windows take the light or dark style of the app's window and follow its changes.
    private func appStyle(in scene: UIWindowScene) -> UIUserInterfaceStyle {
        appWindow(in: scene)?.traitCollection.userInterfaceStyle ?? .unspecified
    }

    private func observeAppStyle(in scene: UIWindowScene) {
        guard let app = appWindow(in: scene) else { return }
        if let existing = styleObservations.value(for: scene) {
            if existing.window === app { return }
            // The app has another window now: the registration on the old one goes.
            styleObservations.remove(scene)
        }
        let registration = app.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self, weak scene] (window: UIWindow, _) in
            let style = window.traitCollection.userInterfaceStyle
            MainActor.assumeIsolated {
                guard let self, let scene else { return }
                self.tabWindows.value(for: scene)?.window.overrideUserInterfaceStyle = style
                if self.sessionWindow?.windowScene === scene { self.sessionWindow?.overrideUserInterfaceStyle = style }
            }
        }
        styleObservations.set(StyleObservation(window: app, registration: registration), for: scene)
    }

    // MARK: Session

    func present() {
        guard isConfigured else {
            NitpickLog.write("present() does nothing: Nitpick.configure has not been called")
            return
        }
        guard session == nil else { return }
        guard let settings else {
            NitpickLog.write("present() does nothing: there are no feedback settings yet (the app has not fetched them, or the key is unknown)")
            return
        }
        guard settings.active else {
            NitpickLog.write("present() does nothing: this app is not active on Nitpick")
            return
        }
        guard settings.general || settings.specific else {
            NitpickLog.write("present() does nothing: both kinds of feedback are off in the settings")
            return
        }
        guard let scene = activeScene() else { return }
        observeAppStyle(in: scene)
        openSession(settings: settings, in: scene)
    }

    /// Opens the panel with the settings of this moment (they hold until the component closes). With only one kind on
    /// it opens that kind at once: General its form, Point at something the pointing. Without a scene (tests) there is
    /// no window; everything else is the same.
    func openSession(settings: RemoteSettings, in scene: UIWindowScene?) {
        let session = FeedbackSession(controller: self, scene: scene, settings: settings)
        self.session = session
        NitpickRegistry.shared.setTracking(true)
        if let scene {
            let window = NitpickWindow(windowScene: scene)
            window.windowLevel = UIWindow.Level(rawValue: 1500)
            window.backgroundColor = .clear
            window.overrideUserInterfaceStyle = appStyle(in: scene)
            if let app = appWindow(in: scene) { window.frame = app.frame }
            let host = UIHostingController(rootView: SessionView(session: session))
            host.view.backgroundColor = .clear
            window.rootViewController = host
            window.isHidden = false
            sessionWindow = window
        }
        for entry in tabWindows.values { entry.window.isHidden = true }
        session.begin()
    }

    func dismiss() {
        closeSession()
        // A new answer that came in while the component was open counts from now on.
        attach()
    }

    private func closeSession() {
        session?.end()
        sessionWindow?.isHidden = true
        sessionWindow?.rootViewController = nil
        sessionWindow = nil
        session = nil
        NitpickRegistry.shared.setTracking(false)
    }

    func transport() -> any FeedbackTransport {
        if let transportOverride { return transportOverride() }
        if options.dryRun {
            return DryRunTransport(directory: options.dryRunDirectory ?? DryRunTransport.defaultDirectory())
        }
        return HTTPTransport(apiURL: options.apiURL, appKey: appKey ?? "")
    }
}
