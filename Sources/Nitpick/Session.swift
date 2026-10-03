import SwiftUI
import UIKit

/// One run of the panel, from opening to sending or closing. Holds the draft.
/// The settings and the texts are those of the moment it was opened.
@MainActor
@Observable
final class FeedbackSession {
    enum Phase { case panel, picking, sent, unavailable }
    enum Kind { case general, specific }
    /// What is shown under the form: the comment is missing, or sending failed (then Try again shows).
    enum Problem: Equatable { case comment, sending }

    var phase: Phase = .panel
    var kind: Kind
    var comment = "" {
        didSet { if problem == .comment { problem = nil } }
    }
    var pick: PickedTarget?
    var screenshot: Data?
    var screenshotImage: UIImage?
    var imageRemoved = false
    var isSending = false
    var problem: Problem?
    /// Shown for a moment after the tap: the tapped point and the element that was found.
    var highlightTap: CGPoint?
    var highlightFrame: CGRect?
    var outlines: [CGRect] = []
    /// The panel shows its two choices as rows. It stays so until the user has chosen General (then the form shows)
    /// or has pointed at something (then the form for pointing shows). With only one kind on there is nothing to choose:
    /// General opens its form at once and Point at something starts pointing at once (`begin()`).
    var showsChoice: Bool
    /// The user closed the panel: it slides down (or fades) and the window goes when that is done.
    var isClosing = false

    @ObservationIgnored private let controller: NitpickController
    @ObservationIgnored private let scene: UIWindowScene?
    @ObservationIgnored let settings: RemoteSettings
    @ObservationIgnored let texts: NitpickTexts
    @ObservationIgnored let look: NitpickLook
    @ObservationIgnored let showsBrand: Bool

    init(controller: NitpickController, scene: UIWindowScene?, settings: RemoteSettings) {
        self.controller = controller
        self.scene = scene
        self.settings = settings
        self.texts = controller.texts(for: settings)
        self.look = controller.look
        self.showsBrand = controller.options.showsBrand
        self.kind = settings.general ? .general : .specific
        self.showsChoice = settings.general && settings.specific
    }

    var language: String { texts.language }
    var offersBothKinds: Bool { settings.general && settings.specific }

    var errorMessage: String? {
        switch problem {
        case .comment: texts.errorComment
        case .sending: texts.errorSend
        case nil: nil
        }
    }

    @ObservationIgnored private var pickTask: Task<Void, Never>?
    /// Set when the controller closed this session. Work that is still waiting then does nothing more.
    @ObservationIgnored private(set) var isEnded = false

    /// The close button works unless a send is running: closing then would hide a failure the user never sees.
    var canClose: Bool { !isSending }

    /// How long the panel moves when it closes: the same as when it opens.
    static var closeDuration: Duration = .milliseconds(280)
    @ObservationIgnored private var closeTask: Task<Void, Never>?

    /// What Close, Cancel, a tap on the dim layer and the end of the thank-you do. In the panel the panel slides down
    /// first (with Reduce Motion it fades) and the dim layer fades with it; the window goes after 280 ms.
    /// While pointing there is no panel, so then it closes at once.
    func close() {
        guard !isEnded, !isClosing else { return }
        guard phase != .picking else {
            controller.dismiss()
            return
        }
        isClosing = true
        closeTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.closeDuration) } catch { return }
            guard let self, !self.isEnded else { return }
            self.controller.dismiss()
        }
    }

    /// The controller closed this session: work that is still waiting stops.
    func end() {
        isEnded = true
        pickTask?.cancel()
        pickTask = nil
        closeTask?.cancel()
        closeTask = nil
    }

    // MARK: Choosing

    /// A row of the panel. General opens the form at once; Point at something starts pointing at once.
    func choose(_ chosen: Kind) {
        kind = chosen
        switch chosen {
        case .general: showsChoice = false
        case .specific: startPicking()
        }
    }

    /// Called once by the controller when the panel opens, after the frames are tracked. With one kind on there is no
    /// panel with a single row: General shows its form (the init did that), Point at something starts pointing now.
    func begin() {
        guard !offersBothKinds, !settings.general, settings.specific else { return }
        startPicking()
        // The frames of the elements are measured just after tracking starts: draw the outlines again when they are there.
        pickTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self, !self.isEnded, self.phase == .picking, self.highlightTap == nil else { return }
            self.refreshOutlines()
        }
    }

    // MARK: Pointing

    private func refreshOutlines() {
        outlines = NitpickRegistry.shared.pointableElements().filter { $0.kind == .element && $0.frame.width > 0 }.map(\.frame)
    }

    func startPicking() {
        // Close the app's keyboard so the layout under the picture is the one the user sees.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        refreshOutlines()
        highlightTap = nil
        highlightFrame = nil
        phase = .picking
    }

    func cancelPicking() {
        pickTask?.cancel()
        pickTask = nil
        highlightTap = nil
        highlightFrame = nil
        // With only pointing on there is no panel to go back to: Cancel closes.
        if pick == nil, !offersBothKinds {
            controller.dismiss()
            return
        }
        phase = .panel
    }

    /// One tap in the pointing layer: find the element, light it up, take the picture, show the form.
    func handleTap(_ point: CGPoint) {
        guard phase == .picking, highlightTap == nil else { return }
        let started = CACurrentMediaTime()
        let registry = NitpickRegistry.shared
        let result = HitTester.match(tap: point, in: registry.pointableElements())
        let found = (CACurrentMediaTime() - started) * 1000
        DiagnosticsStore.shared.lastPickMilliseconds = found

        highlightTap = point
        highlightFrame = result.element?.frame
        let screenName = registry.currentScreen?.name

        pickTask?.cancel()
        pickTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: Self.highlightDuration) } catch { return }
            // The panel may have been closed, or pointing cancelled, in the meantime.
            guard let self else { return }
            guard !Task.isCancelled, !self.isEnded, self.phase == .picking else {
                self.highlightTap = nil
                self.highlightFrame = nil
                return
            }
            self.finishPick(point: point, result: result, screenName: screenName)
        }
    }

    /// How long the found element stays lit before the picture is taken.
    static var highlightDuration: Duration = .milliseconds(450)

    /// Takes the picture and shows the form. However this ends, the light on the element goes out,
    /// so the pointing layer can take a new tap and its Cancel is visible again.
    func finishPick(point: CGPoint, result: HitResult, screenName: String?) {
        defer {
            highlightTap = nil
            highlightFrame = nil
        }
        guard let scene, let appWindow = controller.appWindow(in: scene) else {
            // The app's window is not there (hidden for a moment, for example by a privacy cover): stay in pointing, so the user can tap again or cancel.
            NitpickLog.write("pointing: the app's window is not on screen, no picture was taken; tap again or cancel")
            return
        }
        let registry = NitpickRegistry.shared
        let captureStart = CACurrentMediaTime()
        let captured = Capture.capture(window: appWindow, maskFrames: registry.maskFrames())
        DiagnosticsStore.shared.lastCaptureMilliseconds = (CACurrentMediaTime() - captureStart) * 1000
        if let captured {
            screenshot = captured.jpeg
            screenshotImage = UIImage(data: captured.jpeg)
            DiagnosticsStore.shared.lastCaptureComplete = captured.drewCompletely
            DiagnosticsStore.shared.lastScreenshotBytes = captured.jpeg.count
            DiagnosticsStore.shared.lastScreenshotPixels = "\(Int(captured.pixelSize.width))x\(Int(captured.pixelSize.height))"
        } else {
            screenshot = nil
            screenshotImage = nil
        }
        imageRemoved = false
        pick = PickedTarget(
            tap: point, element: result.element, match: result.match, screen: screenName,
            viewport: appWindow.bounds.size, scale: Double(appWindow.screen.scale)
        )
        kind = .specific
        showsChoice = false
        phase = .panel
    }

    func removeImage() {
        screenshot = nil
        screenshotImage = nil
        imageRemoved = true
    }

    // MARK: Sending

    /// Both kinds need a comment: without one nothing is sent and the panel says so.
    func send() {
        guard !isSending else { return }
        guard !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            problem = .comment
            return
        }
        let facts = DeviceFacts.current()
        let payload: FeedbackPayload
        var image: Data?
        switch kind {
        case .general:
            payload = PayloadFactory.general(comment: comment, screen: NitpickRegistry.shared.currentScreen?.name, facts: facts)
        case .specific:
            guard let pick else { return }
            payload = PayloadFactory.specific(comment: comment, pick: pick, facts: facts)
            image = screenshot
        }
        guard let body = try? payload.jsonData() else { return }
        let transport = controller.transport()
        isSending = true
        problem = nil
        Task { @MainActor in
            do {
                try await transport.send(payload: body, screenshot: image)
                isSending = false
                phase = .sent
                try? await Task.sleep(for: NitpickStyle.thanksDuration)
                if controller.session === self { close() }
            } catch SendError.unavailable(let code) {
                isSending = false
                NitpickLog.write("sending stopped: the platform answered \(code); the feedback tab goes away")
                stopBecauseUnavailable()
            } catch {
                // What the server says goes to the developer log only; the user sees the fixed text.
                isSending = false
                if !isEnded {
                    NitpickLog.write("sending failed: \(error)")
                    problem = .sending
                } else {
                    // The panel was closed (by the app) while this was sending: nobody sees a message, so the log must say it.
                    NitpickLog.write("sending failed after the panel was closed, the feedback did not arrive and the draft is gone: \(error)")
                }
            }
        }
    }

    /// `app_inactive` or `monthly_limit`: the sentence `unavailable`, no Try again, the draft is gone, the tab goes away.
    private func stopBecauseUnavailable() {
        comment = ""
        pick = nil
        screenshot = nil
        screenshotImage = nil
        problem = nil
        phase = .unavailable
        controller.markUnavailable()
    }
}
