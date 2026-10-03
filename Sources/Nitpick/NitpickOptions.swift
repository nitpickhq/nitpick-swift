import Foundation

/// Which screen edge the tab hangs on. Physical: also in an app that runs from right to left.
public enum NitpickTabEdge: Sendable {
    case right
    case left
}

/// Options for `Nitpick.configure(appKey:options:)`. Every value has a default.
/// The kinds of feedback and two of the texts are not set here: the component fetches them
/// from your Nitpick settings when the app starts.
public struct NitpickOptions: Sendable {
    /// Base URL of the Nitpick platform. The default never resolves (`.invalid`),
    /// so nothing leaks to a foreign domain before you set a real one.
    public var apiURL: URL
    /// Show the edge tab. Turn it off when you open the panel from your own button with `Nitpick.present()`.
    public var showsTab: Bool
    /// Which edge the tab hangs on.
    public var tabEdge: NitpickTabEdge
    /// Vertical position of the middle of the tab as a fraction of the window height (0 top, 1 bottom).
    /// The tab always stays at least 60 points from the top and bottom edge.
    public var tabVerticalPosition: Double
    /// The screens the tab shows on, by the name you gave them with `.nitpickScreen`. `nil` (the default) shows the tab
    /// on every screen. A rule is an exact name (capitals count) or ends on `*` and then matches every name that starts
    /// with what comes before it (`"Checkout*"`). An empty list shows the tab nowhere. The tab only shows on a screen
    /// that has a name; `showsTab: false` always wins. `Nitpick.present()` works on every screen.
    public var tabScreens: [String]?
    /// Write the payload and the image to disk instead of sending them. Also fetches no settings:
    /// the tab shows at once, both kinds are on and the texts are the built-in translations.
    public var dryRun: Bool
    /// Where a dry run writes. Default: `Documents/nitpick-dryrun`.
    public var dryRunDirectory: URL?
    /// The color and the font. Everything else about the look is fixed.
    public var theme: NitpickTheme
    /// A small mark with the Nitpick domain under the panel. Off by default.
    public var showsBrand: Bool
    /// Forces a language (one of the 20 codes, for example `"ar"`). For tests; `nil` follows the device.
    public var language: String?

    public static let defaultAPIURL = URL(string: "https://app.nitpickhq.com")!

    public init(
        apiURL: URL = NitpickOptions.defaultAPIURL,
        showsTab: Bool = true,
        tabEdge: NitpickTabEdge = .right,
        tabVerticalPosition: Double = 0.5,
        tabScreens: [String]? = nil,
        dryRun: Bool = false,
        dryRunDirectory: URL? = nil,
        theme: NitpickTheme = NitpickTheme(),
        showsBrand: Bool = false,
        language: String? = nil
    ) {
        self.apiURL = apiURL
        self.showsTab = showsTab
        self.tabEdge = tabEdge
        self.tabVerticalPosition = tabVerticalPosition
        self.tabScreens = tabScreens
        self.dryRun = dryRun
        self.dryRunDirectory = dryRunDirectory
        self.theme = theme
        self.showsBrand = showsBrand
        self.language = language
    }
}

/// The brand mark with domain (option `showsBrand`). The domain is not chosen yet: it is set here, in one place.
enum NitpickBrand {
    static let domain = "nitpickhq.com"
}

/// Which screens the tab shows on: the rules for `NitpickOptions.tabScreens`.
enum TabScreens {
    /// A rule matches a name when it is equal to it (capitals count), or, when the rule ends on `*`,
    /// when the name starts with what comes before the `*`.
    static func matches(rule: String, name: String) -> Bool {
        if rule.hasSuffix("*") { return name.hasPrefix(String(rule.dropLast())) }
        return name == rule
    }

    /// Whether the tab may show on the screen with this name. No list: yes, on every screen, also one without a name.
    /// A list: only on a screen with a name that one of the rules matches.
    static func allows(screen name: String?, list: [String]?) -> Bool {
        guard let list else { return true }
        guard let name else { return false }
        return list.contains { matches(rule: $0, name: name) }
    }
}
