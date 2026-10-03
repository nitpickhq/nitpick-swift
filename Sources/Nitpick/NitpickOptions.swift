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
