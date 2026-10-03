import SwiftUI

/// Picks one of the 20 languages from the device's preferred languages.
/// The rules and the table of examples are in `docs/specs/api-v1.md` and `packages/teksten/taalkeuze.json`.
enum NitpickLanguage {
    static let supported: [String] = GeneratedTexts.languages
    /// Languages written from right to left.
    static let rightToLeft: Set<String> = ["ar"]
    /// Languages for which the component always uses the system font.
    static let systemFontOnly: Set<String> = ["ar", "hi", "ja", "ko", "zh-Hans", "zh-Hant"]

    /// The first preferred language that fits wins; otherwise English.
    static func resolve(preferred: [String]) -> String {
        for tag in preferred {
            if let code = code(for: tag) { return code }
        }
        return "en"
    }

    /// The code for one language tag, or nil when the tag is none of the 20.
    static func code(for tag: String) -> String? {
        let parts = tag.replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first else { return nil }
        switch first {
        case "zh":
            let rest = parts.dropFirst()
            // A script in the tag always wins over the region.
            if rest.contains("hant") { return "zh-Hant" }
            if rest.contains("hans") { return "zh-Hans" }
            if rest.contains(where: { ["tw", "hk", "mo"].contains($0) }) { return "zh-Hant" }
            return "zh-Hans"
        case "no", "nb", "nn":
            return "nb"
        case "pt":
            return "pt"
        default:
            return supported.contains(first) ? first : nil
        }
    }

    /// The panel follows the chosen language, not the direction of the app.
    static func layoutDirection(for language: String) -> LayoutDirection {
        rightToLeft.contains(language) ? .rightToLeft : .leftToRight
    }
}
