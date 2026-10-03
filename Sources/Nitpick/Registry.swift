import SwiftUI

/// What a marker marks.
enum MarkerKind: Sendable, Equatable {
    case element
    case mask
}

/// One marked element with its frame in window points.
struct MarkedElement: Sendable, Equatable {
    var id: UUID
    var name: String
    var kind: MarkerKind
    var frame: CGRect
    /// The screen marker this element was placed inside, if any.
    var screenID: UUID?
}

/// One visible `.nitpickScreen`.
struct ScreenEntry: Sendable, Equatable {
    var id: UUID
    var name: String
    var order: Int
    /// False for a screen that is mounted but hidden (for example a tab that is not selected).
    /// Such a screen is never the current screen and its elements never count when pointing.
    var focused: Bool = true
}

enum MatchKind: String, Sendable, Codable {
    case exact, nearest, none
}

struct HitResult: Sendable, Equatable {
    var element: MarkedElement?
    var match: MatchKind
}

/// Pure matching rules, kept apart from UI so they can be tested.
enum HitTester {
    /// Nearest-element radius in points.
    static let nearestRadius: CGFloat = 44

    /// The smallest marked element that contains the tap wins; otherwise the
    /// nearest one within 44 points; otherwise nothing. Masks never match.
    static func match(tap: CGPoint, in elements: [MarkedElement]) -> HitResult {
        var best: MarkedElement?
        var bestArea = CGFloat.infinity
        for element in elements where element.kind == .element {
            guard element.frame.width > 0, element.frame.height > 0, element.frame.contains(tap) else { continue }
            let area = element.frame.width * element.frame.height
            if area <= bestArea {
                best = element
                bestArea = area
            }
        }
        if let best { return HitResult(element: best, match: .exact) }

        var nearest: MarkedElement?
        var nearestDistance = CGFloat.infinity
        for element in elements where element.kind == .element {
            guard element.frame.width > 0, element.frame.height > 0 else { continue }
            let distance = distance(from: tap, to: element.frame)
            if distance <= nearestRadius, distance < nearestDistance {
                nearest = element
                nearestDistance = distance
            }
        }
        if let nearest { return HitResult(element: nearest, match: .nearest) }
        return HitResult(element: nil, match: .none)
    }

    static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Keeps the frames of marked elements and the stack of visible screens.
///
/// Frames are only tracked while the component is open (panel or pointing): `isTracking`. When it is closed,
/// scrolling lists cost nothing, because the markers then do not even measure their frame.
/// Only `isTracking` is observable; the frames are not, on purpose: scrolling updates them constantly.
@MainActor
@Observable
final class NitpickRegistry {
    @ObservationIgnored static let shared = NitpickRegistry()

    /// Whether frames are tracked now. Off while the component is closed.
    var isTracking: Bool

    @ObservationIgnored private(set) var elements: [UUID: MarkedElement] = [:]
    @ObservationIgnored private(set) var screens: [UUID: ScreenEntry] = [:]
    @ObservationIgnored private var screenCounter = 0
    /// How many frame updates came in since launch. Diagnostics only.
    @ObservationIgnored private(set) var frameUpdateCount = 0

    init(tracking: Bool = false) {
        isTracking = tracking
    }

    func registerElement(id: UUID, name: String, kind: MarkerKind, screenID: UUID?) {
        var entry = elements[id] ?? MarkedElement(id: id, name: name, kind: kind, frame: .zero, screenID: screenID)
        entry.name = name
        entry.kind = kind
        entry.screenID = screenID
        elements[id] = entry
    }

    /// Ignored while the component is closed.
    func updateFrame(id: UUID, frame: CGRect) {
        guard isTracking else { return }
        frameUpdateCount += 1
        if elements[id] != nil {
            elements[id]?.frame = frame
        } else {
            // Geometry can report before onAppear. Keep the frame; the name follows.
            elements[id] = MarkedElement(id: id, name: "", kind: .element, frame: frame, screenID: nil)
        }
    }

    /// Starts or stops tracking. Stopping drops the frames, so a stale frame never matches later.
    func setTracking(_ tracking: Bool) {
        guard tracking != isTracking else { return }
        isTracking = tracking
        if !tracking {
            for id in elements.keys { elements[id]?.frame = .zero }
            // An entry that only ever had a frame (no marker came) is of no use anymore.
            elements = elements.filter { !$0.value.name.isEmpty }
        }
    }

    func removeElement(id: UUID) {
        elements[id] = nil
    }

    func screenAppeared(id: UUID, name: String, focused: Bool = true) {
        screenCounter += 1
        screens[id] = ScreenEntry(id: id, name: name, order: screenCounter, focused: focused)
    }

    /// The focus of a screen that is already known changes (a tab is selected or deselected). Unknown ids are ignored.
    func screenFocusChanged(id: UUID, focused: Bool) {
        screens[id]?.focused = focused
    }

    func screenDisappeared(id: UUID) {
        screens[id] = nil
    }

    /// The last screen that appeared and is still visible and has focus.
    var currentScreen: ScreenEntry? {
        screens.values.filter(\.focused).max { $0.order < $1.order }
    }

    /// Elements that can be pointed at now: the ones inside the current screen, or all when
    /// no screen is marked. An element without a screen marker stays pointable. An element inside
    /// a screen without focus never counts, also when no screen has focus.
    func pointableElements() -> [MarkedElement] {
        let current = currentScreen?.id
        return elements.values.filter { element in
            guard !element.name.isEmpty else { return false }
            if let screenID = element.screenID, let screen = screens[screenID], !screen.focused { return false }
            guard let current else { return true }
            return element.screenID == nil || element.screenID == current
        }
    }

    func maskFrames() -> [CGRect] {
        elements.values.filter { $0.kind == .mask && $0.frame.width > 0 && $0.frame.height > 0 }.map(\.frame)
    }

    func reset() {
        elements = [:]
        screens = [:]
    }
}
