import Testing
import Foundation
import SwiftUI
import CryptoKit
@testable import Nitpick

@Suite("Talen en teksten")
struct TextsTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var preferred: [String]
        var expected: String
        var testDescription: String { "\(preferred) -> \(expected)" }
    }

    static let cases: [Case] = {
        let object = try! Teksten.json("taalkeuze.json")
        return (object["cases"] as! [[String: Any]]).map {
            Case(preferred: $0["preferred"] as! [String], expected: $0["expected"] as! String)
        }
    }()

    @Test func theSharedTableHas42Cases() {
        #expect(Self.cases.count == 42)
    }

    @Test("alle gevallen uit taalkeuze.json", arguments: cases)
    func languageChoiceFollowsTheSharedTable(_ item: Case) {
        #expect(NitpickLanguage.resolve(preferred: item.preferred) == item.expected)
    }

    @Test func theTwentyCodesAreTheOnesInTheSharedTable() throws {
        let codes = try Teksten.json("taalkeuze.json")["codes"] as! [String]
        #expect(codes.count == 20)
        #expect(GeneratedTexts.languages == codes)
        #expect(Set(codes).count == 20)
    }

    @Test func everyLanguageHasAll22KeysInTheGeneratedFile() throws {
        let english = try Teksten.texts("en")
        #expect(english.count == 22)
        #expect(GeneratedTexts.keys == Array(try orderedKeys("en")))
        #expect(GeneratedTexts.table.count == 20)
        for code in GeneratedTexts.languages {
            let table = try #require(GeneratedTexts.table[code], "no table for \(code)")
            #expect(Set(table.keys) == Set(english.keys), "\(code): keys differ")
            #expect(table.count == 22)
            for (key, value) in table { #expect(!value.isEmpty, "\(code).\(key) is empty") }
        }
    }

    @Test func generatedFileEqualsTheJSONFilesItIsMadeFrom() throws {
        // The same content as the script reads now, and the same hash that the script wrote in the file.
        var hash = SHA256()
        hash.update(data: try Teksten.data("taalkeuze.json"))
        for code in GeneratedTexts.languages {
            #expect(GeneratedTexts.table[code] == (try Teksten.texts(code)), "\(code): generated texts differ from \(code).json")
            hash.update(data: try Teksten.data("\(code).json"))
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        #expect(GeneratedTexts.sourceHash == digest, "GeneratedTexts.swift is out of date: run node scripts/generate-texts.mjs")
    }

    @Test func everyTextAccessorGivesText() {
        for code in GeneratedTexts.languages {
            let texts = NitpickTexts(language: code)
            let all = [texts.tabLabel, texts.title, texts.general, texts.specific, texts.commentGeneral, texts.commentSpecific,
                       texts.pointHint, texts.pointStart, texts.pointBanner, texts.cancel, texts.send, texts.sending, texts.retry,
                       texts.removeImage, texts.imageRemoved, texts.close, texts.errorSend, texts.errorComment, texts.elementNone,
                       texts.unavailable, texts.footer, texts.thanks]
            #expect(all.count == 22)
            #expect(all.allSatisfy { !$0.isEmpty }, "\(code) has an empty text")
            #expect(texts.footer == texts.translation("privacyNote"))
            #expect(texts.thanks == texts.translation("sent"))
        }
    }

    @Test func englishAndDutchDefaults() {
        #expect(NitpickTexts(language: "en").footer == "Your feedback goes to the maker of this app.")
        #expect(NitpickTexts(language: "nl").footer == "Je feedback gaat naar de maker van deze app.")
        #expect(NitpickTexts(language: "en").unavailable == "Feedback is not available right now.")
        #expect(NitpickTexts(language: "nl").send == "Versturen")
        #expect(NitpickTexts(language: "xx").send == "Send")
    }

    @Test func onlyFooterAndThanksCanBeReplacedAndTheyStayLiteral() {
        let literal = "**Hi** [link](https://example.com) <b>x</b> &amp;"
        let texts = NitpickTexts(language: "nl", overrides: .init(footer: literal, thanks: "Dank!"))
        #expect(texts.footer == literal)
        #expect(texts.thanks == "Dank!")
        #expect(texts.send == "Versturen")
        #expect(NitpickTexts(language: "nl", overrides: .init(footer: nil, thanks: nil)).footer == "Je feedback gaat naar de maker van deze app.")
    }

    @Test func rightToLeftOnlyForArabic() {
        for code in GeneratedTexts.languages {
            let expected: LayoutDirection = code == "ar" ? .rightToLeft : .leftToRight
            #expect(NitpickLanguage.layoutDirection(for: code) == expected, "\(code)")
        }
    }

    @Test func systemFontForTheSixLanguages() {
        let six: Set<String> = ["ar", "hi", "ja", "ko", "zh-Hans", "zh-Hant"]
        #expect(NitpickLanguage.systemFontOnly == six)
        for code in GeneratedTexts.languages {
            let look = NitpickLook(theme: NitpickTheme(fontName: "Georgia"), language: code)
            if six.contains(code) {
                #expect(look.customFontName == nil, "\(code) must use the system font")
            } else {
                #expect(look.customFontName == "Georgia", "\(code) should use the app's font")
            }
        }
        #expect(NitpickLook(theme: NitpickTheme(fontName: "NoSuchFont-Regular"), language: "en").customFontName == nil)
        #expect(NitpickLook(theme: NitpickTheme(), language: "en").customFontName == nil)
    }

    private func orderedKeys(_ code: String) throws -> [String] {
        // en.json lists the keys in the order of the spec; the script keeps that order.
        let text = String(decoding: try Teksten.data("\(code).json"), as: UTF8.self)
        let block = text.components(separatedBy: "\"texts\": {")[1].components(separatedBy: "}")[0]
        return block.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""), let end = trimmed.dropFirst().firstIndex(of: "\"") else { return nil }
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        }
    }
}

extension SharedState {
@MainActor
@Suite("Opties")
struct OptionsTests {
    @Test func defaultOptions() {
        let options = NitpickOptions()
        #expect(options.apiURL.host == "app.nitpickhq.com")
        #expect(options.showsTab)
        #expect(!options.dryRun)
        #expect(options.tabEdge == .right)
        #expect(options.tabVerticalPosition == 0.5)
        #expect(!options.showsBrand)
        #expect(options.language == nil)
        if case .standard = options.theme.color {} else { Issue.record("the default color is not .standard") }
        #expect(options.theme.fontName == nil)
    }

    @Test func forcedLanguageWorksForAll20Codes() {
        let controller = NitpickController()
        for code in GeneratedTexts.languages {
            controller.configure(appKey: "npk_test", options: NitpickOptions(dryRun: true, language: code))
            #expect(controller.language == code)
            #expect(controller.texts(for: nil).language == code)
        }
        controller.configure(appKey: "npk_test", options: NitpickOptions(dryRun: true, language: "xx"))
        controller.preferredLanguages = { ["de-DE"] }
        #expect(controller.language == "de")
    }

    @Test func deviceLanguageIsUsedWithoutAForcedOne() {
        let controller = NitpickController()
        controller.preferredLanguages = { ["zh_Hant_HK", "en"] }
        controller.configure(appKey: "npk_test", options: NitpickOptions(dryRun: true))
        #expect(controller.language == "zh-Hant")
    }

    @Test func brandDomainIsInOnePlace() {
        #expect(!NitpickBrand.domain.isEmpty)
        #expect(!NitpickOptions().showsBrand)
    }

    @Test func privacyManifestDeclaresUserDefaultsWithReasonCA921() throws {
        let url = Teksten.packageDirectory.appending(path: "Sources/Nitpick/PrivacyInfo.xcprivacy")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
        let types = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(types.count == 1)
        #expect(types.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(types.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
    }
}
}
