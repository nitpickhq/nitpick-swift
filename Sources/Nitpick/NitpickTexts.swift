import Foundation

/// The texts of the panel in one language. Internal: the texts come from the translations in
/// `GeneratedTexts` (made from `packages/teksten`). Only `footer` and `thanks` can be replaced,
/// by the settings of the app, and they are shown as literal text.
struct NitpickTexts: Sendable, Equatable {
    let language: String
    private let values: [String: String]
    private let footerOverride: String?
    private let thanksOverride: String?

    init(language: String, overrides: RemoteSettings.TextOverrides? = nil) {
        let code = GeneratedTexts.table[language] == nil ? "en" : language
        self.language = code
        self.values = GeneratedTexts.table[code] ?? [:]
        self.footerOverride = overrides?.footer
        self.thanksOverride = overrides?.thanks
    }

    private func value(_ key: String) -> String {
        values[key] ?? GeneratedTexts.table["en"]?[key] ?? ""
    }

    var tabLabel: String { value("tabLabel") }
    var title: String { value("title") }
    var general: String { value("general") }
    var specific: String { value("specific") }
    var commentGeneral: String { value("commentGeneral") }
    var commentSpecific: String { value("commentSpecific") }
    var pointHint: String { value("pointHint") }
    var pointStart: String { value("pointStart") }
    var pointBanner: String { value("pointBanner") }
    var cancel: String { value("cancel") }
    var send: String { value("send") }
    var sending: String { value("sending") }
    var retry: String { value("retry") }
    var removeImage: String { value("removeImage") }
    var imageRemoved: String { value("imageRemoved") }
    var close: String { value("close") }
    var errorSend: String { value("errorSend") }
    var errorComment: String { value("errorComment") }
    var elementNone: String { value("elementNone") }
    var unavailable: String { value("unavailable") }

    /// The line under Send: the app's own text, or the translation.
    var footer: String { footerOverride ?? value("privacyNote") }
    /// The thank-you after sending: the app's own text, or the translation.
    var thanks: String { thanksOverride ?? value("sent") }

    /// The value of a translation key, for tests.
    func translation(_ key: String) -> String { value(key) }
}
