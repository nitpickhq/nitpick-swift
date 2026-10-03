import XCTest

/// Drives the demo app on the simulator: open the tab, point, send in dry run, and keep the evidence.
final class DemoUITests: XCTestCase {
    var app: XCUIApplication!
    /// The places of the texts on the screen, for the contrast measurement; `evidence` writes and empties them.
    var targets: [Target] = []
    let dryRunDir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "nitpick-uitest-\(UUID().uuidString)")

    /// qa/evidence/swift/papier-gelijk in the repository, found from this file's path: the screens of the design Papier
    /// after the addition ("Aanvulling na de bouw"). The older map `papier` is not touched any more.
    var evidenceDir: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appending(path: "qa/evidence/swift/papier-gelijk")
    }

    /// The other evidence of the older tests (pictures, reports of the flows), kept apart from the screens of Papier.
    var overigDir: URL { evidenceDir.appending(path: "overig") }

    /// The texts of the shared translations, read from packages/teksten.
    func texts(_ code: String) throws -> [String: String] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // DemoUITests.swift, UITests, Demo, swift
        let data = try Data(contentsOf: url.appending(path: "teksten/\(code).json"))
        return (try JSONSerialization.jsonObject(with: data) as! [String: Any])["texts"] as! [String: String]
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: dryRunDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: overigDir, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["NITPICK_DRYRUN_DIR"] = dryRunDir.path
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dryRunDir)
    }

    // MARK: Helpers

    func screenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: overigDir.appending(path: "\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func open(_ screen: String) {
        let link = app.buttons["nav.\(screen)"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "link nav.\(screen) not found")
        link.tap()
    }

    func openPanel() {
        let tab = app.buttons["nitpick.tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "edge tab not found")
        tab.tap()
        let opened = app.buttons["nitpick.close"].waitForExistence(timeout: 5)
        if !opened { screenshot("debug-panel-not-open"); print(app.debugDescription) }
        XCTAssertTrue(opened, "panel did not open")
    }

    /// The row Point at something starts pointing at once: one tap, no second button.
    func startPointing() {
        let row = app.buttons["nitpick.kind.specific"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row Point at something")
        sleep(1) // let panel and keyboard animations settle
        row.tap()
        let cancel = app.buttons["nitpick.cancel-pointing"]
        if !cancel.waitForExistence(timeout: 3) {
            screenshot("debug-no-pointing")
            if app.buttons["nitpick.kind.specific"].exists { app.buttons["nitpick.kind.specific"].tap() }
        }
        if !cancel.waitForExistence(timeout: 5) { screenshot("debug-after-retry") }
        XCTAssertTrue(cancel.exists, "pointing layer did not start")
    }

    /// The row General opens its form at once.
    func openGeneralForm() {
        let row = app.buttons["nitpick.kind.general"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no row General")
        row.tap()
        XCTAssertTrue(app.buttons["nitpick.send"].waitForExistence(timeout: 5), "the form for General did not open")
    }

    /// Taps at a point in the window, as a fraction of the window.
    func tapWindow(x: CGFloat, y: CGFloat) {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: app.windows.firstMatch.frame.width * x, dy: app.windows.firstMatch.frame.height * y)).tap()
    }

    func tapCenter(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func tapPointingLayer(at coordinate: XCUICoordinate) {
        coordinate.tap()
    }

    func fillCommentAndSend(_ text: String) {
        let comment = app.textViews["nitpick.comment"].exists ? app.textViews["nitpick.comment"] : app.textFields["nitpick.comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5), "comment field missing")
        comment.tap()
        comment.typeText(text)
        // Close the keyboard by tapping the panel title area, so Send is visible.
        let send = app.buttons["nitpick.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        if !send.isHittable { screenshot("debug-send-not-hittable") }
        send.tap()
    }

    /// The newest dry-run folder: payload.json and optional screenshot.jpg.
    func latestDryRun() throws -> (payload: [String: Any], payloadData: Data, screenshot: Data?) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let folders = (try? FileManager.default.contentsOfDirectory(at: dryRunDir, includingPropertiesForKeys: nil)) ?? []
            if let newest = folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last,
               let data = try? Data(contentsOf: newest.appending(path: "payload.json")) {
                let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                return (object, data, try? Data(contentsOf: newest.appending(path: "screenshot.jpg")))
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTFail("no dry run output in \(dryRunDir.path)")
        return ([:], Data(), nil)
    }

    func keep(_ name: String, _ run: (payload: [String: Any], payloadData: Data, screenshot: Data?)) throws {
        try run.payloadData.write(to: overigDir.appending(path: "\(name)-payload.json"))
        if let shot = run.screenshot { try shot.write(to: overigDir.appending(path: "\(name)-screenshot.jpg")) }
    }

    /// Point at an element in the current screen and send. Returns the dry run.
    func pointAndSend(at element: XCUIElement, name: String, comment: String = "UI test comment", screenshots: Bool = false) throws -> (payload: [String: Any], payloadData: Data, screenshot: Data?) {
        let target = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        openPanel()
        if screenshots { screenshot("\(name)-2-panel") }
        startPointing()
        if screenshots { screenshot("\(name)-3-pointing-layer") }
        target.tap()
        if screenshots { screenshot("\(name)-4-pointing-ring") }
        XCTAssertTrue(app.images["nitpick.preview"].waitForExistence(timeout: 10) || app.otherElements["nitpick.preview"].waitForExistence(timeout: 2), "no preview")
        if screenshots { screenshot("\(name)-5-form-with-preview") }
        fillCommentAndSend(comment)
        let run = try latestDryRun()
        try keep(name, run)
        return run
    }

    // MARK: Tests

    /// The main flow of the brief: tab, point, tap a marked button, form, send in dry run.
    func testPointAtMarkedButtonAndSendDryRun() throws {
        app.launch()
        open("checkout")
        XCTAssertTrue(app.buttons["checkout.pay"].waitForExistence(timeout: 5))
        screenshot("checkout-1-tab")
        let run = try pointAndSend(at: app.buttons["checkout.pay"], name: "checkout", comment: "The pay button is too small", screenshots: true)
        let p = run.payload
        XCTAssertEqual(p["kind"] as? String, "specific")
        XCTAssertEqual(p["screen"] as? String, "Checkout")
        XCTAssertEqual(p["element"] as? String, "checkout.pay_button")
        XCTAssertEqual(p["element_match"] as? String, "exact")
        XCTAssertNotNil(p["tap"] as? [String: Double])
        XCTAssertNotNil(p["viewport"] as? [String: Double])
        XCTAssertNotNil(p["element_frame"] as? [String: Double])
        XCTAssertEqual(p["comment"] as? String, "The pay button is too small")
        XCTAssertEqual((p["sdk"] as? [String: String])?["name"], "swift")
        let shot = try XCTUnwrap(run.screenshot)
        XCTAssertGreaterThan(shot.count, 5000)
        XCTAssertEqual(shot.prefix(2), Data([0xFF, 0xD8]))
    }

    /// General feedback is a comment only: no score, the payload has no `score`.
    func testGeneralFeedbackWithACommentDryRunWithoutScore() throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openPanel()
        XCTAssertFalse(app.buttons["nitpick.score.4"].exists, "there is no score anymore")
        XCTAssertTrue(app.buttons["nitpick.kind.general"].exists && app.buttons["nitpick.kind.specific"].exists)
        XCTAssertFalse(app.buttons["nitpick.point"].exists, "the separate button to start pointing is gone")
        XCTAssertFalse(app.buttons["nitpick.send"].exists, "the panel with the two rows has no Send")
        openGeneralForm()
        let comment = app.textViews["nitpick.comment"].exists ? app.textViews["nitpick.comment"] : app.textFields["nitpick.comment"]
        comment.tap()
        comment.typeText("Nice app")
        screenshot("general-1-form")
        app.buttons["nitpick.send"].tap()
        let run = try latestDryRun()
        try keep("general", run)
        XCTAssertEqual(run.payload["kind"] as? String, "general")
        XCTAssertEqual(run.payload["comment"] as? String, "Nice app")
        XCTAssertNil(run.payload["score"])
        XCTAssertFalse(String(decoding: run.payloadData, as: UTF8.self).contains("score"))
        XCTAssertEqual((run.payload["sdk"] as? [String: String])?["version"], "0.3.0")
        XCTAssertNil(run.screenshot)
        let thanks = try texts("en")["sent"]!
        let sent = app.descendants(matching: .any)["nitpick.sent"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "no thank-you")
        XCTAssertTrue(sent.label.contains(thanks), "thank-you is '\(sent.label)'")
        screenshot("general-2-thanks")
    }

    /// Without a comment nothing is sent; the panel says why.
    func testGeneralFeedbackWithoutACommentIsNotSent() throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        openPanel()
        openGeneralForm()
        app.buttons["nitpick.send"].tap()
        let error = app.staticTexts["nitpick.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "no message about the missing comment")
        XCTAssertEqual(error.label, try texts("en")["errorComment"])
        sleep(1)
        target("error message", error)
        target("Send", app.buttons["nitpick.send"], kind: "send")
        evidence("fout-licht")
        XCTAssertTrue(app.buttons["nitpick.send"].exists, "still a send button, not Try again")
        sleep(1)
        let folders = (try? FileManager.default.contentsOfDirectory(at: dryRunDir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertTrue(folders.isEmpty, "something was written: \(folders)")
        screenshot("general-no-comment")
    }

    /// Integration: really send (no dry run) to a running platform. Only runs when
    /// NITPICK_INTEGRATION_KEY is passed (xcodebuild: TEST_RUNNER_NITPICK_INTEGRATION_KEY=npk_...), see qa/integratie/keten.sh.
    func testSendsToPlatform() throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["NITPICK_INTEGRATION_KEY"], !key.isEmpty else {
            throw XCTSkip("NITPICK_INTEGRATION_KEY not set; this test needs a running platform")
        }
        let comment = env["NITPICK_INTEGRATION_COMMENT"] ?? "Integration: the pay button is too small"
        app.launchEnvironment["NITPICK_DEMO_MODE"] = "send"
        app.launchEnvironment["NITPICK_KEY"] = key
        app.launchEnvironment["NITPICK_API_URL"] = env["NITPICK_INTEGRATION_API_URL"] ?? "http://localhost:3000"
        app.launch()
        open("checkout")
        let pay = app.buttons["checkout.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        openPanel()
        startPointing()
        pay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.images["nitpick.preview"].waitForExistence(timeout: 10) || app.otherElements["nitpick.preview"].waitForExistence(timeout: 2), "no preview")
        fillCommentAndSend(comment)
        let sent = app.descendants(matching: .any)["nitpick.sent"]
        let failed = app.descendants(matching: .any)["nitpick.error"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !sent.exists, !failed.exists { Thread.sleep(forTimeInterval: 0.3) }
        screenshot("integration-after-send")
        XCTAssertFalse(failed.exists, "the platform did not accept the feedback: \(failed.label)")
        XCTAssertTrue(sent.exists, "no confirmation after sending")
    }

    func testPointingWorksAboveSheet() throws {
        app.launch()
        open("sheet")
        app.buttons["sheet.open"].tap()
        let upgrade = app.buttons["sheet.upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        sleep(1)
        screenshot("sheet-1-sheet-open-with-tab")
        let run = try pointAndSend(at: upgrade, name: "sheet", comment: "Upgrade copy", screenshots: true)
        XCTAssertEqual(run.payload["element"] as? String, "sheet.upgrade_button")
        XCTAssertEqual(run.payload["element_match"] as? String, "exact")
        XCTAssertEqual(run.payload["screen"] as? String, "Upgrade sheet")
    }

    func testNearestAndNone() throws {
        app.launch()
        open("checkout")
        let pay = app.buttons["checkout.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        let frame = pay.frame
        // Right under the button, 20 points below its lower edge: nearest.
        openPanel(); startPointing()
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.maxY + 20)).tap()
        XCTAssertTrue(app.buttons["nitpick.send"].waitForExistence(timeout: 10))
        fillCommentAndSend("near")
        let near = try latestDryRun()
        try keep("checkout-nearest", near)
        XCTAssertEqual(near.payload["element_match"] as? String, "nearest")
        XCTAssertEqual(near.payload["element"] as? String, "checkout.pay_button")
    }

    func testSecureFieldAndMaskAreBlackInThePicture() throws {
        app.launch()
        open("checkout")
        let password = app.secureTextFields["checkout.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        let card = app.textFields["checkout.card"]
        let passwordFrame = password.frame, cardFrame = card.frame
        let run = try pointAndSend(at: app.buttons["checkout.pay"], name: "checkout-masks")
        let jpeg = try XCTUnwrap(run.screenshot)
        let image = try XCTUnwrap(UIImage(data: jpeg))
        let viewport = try XCTUnwrap(run.payload["viewport"] as? [String: Double])
        func luminance(at frame: CGRect) -> Double {
            let cg = image.cgImage!
            let x = Int(frame.midX / viewport["width"]! * Double(cg.width))
            let y = Int(frame.midY / viewport["height"]! * Double(cg.height))
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
            return Double(Int(px[0]) + Int(px[1]) + Int(px[2])) / 3
        }
        XCTAssertLessThan(luminance(at: passwordFrame), 25, "SecureField is not black in the picture")
        XCTAssertLessThan(luminance(at: cardFrame), 25, "masked card field is not black in the picture")
    }

    /// What reaches the picture for map, web and video.
    func testCaptureMapWebVideo() throws {
        for (screen, element, wait) in [("map", "map.view", 4), ("web", "web.view", 3), ("video", "video.player", 4)] {
            app.launch()
            open(screen)
            let target = app.descendants(matching: .any)[element]
            XCTAssertTrue(target.waitForExistence(timeout: 10), "\(element) missing")
            sleep(UInt32(wait))
            screenshot("\(screen)-0-reference-simulator")
            let run = try pointAndSend(at: target, name: "\(screen)-capture", comment: "Look at \(screen)")
            XCTAssertEqual(run.payload["element"] as? String, element)
            XCTAssertNotNil(run.screenshot)
            app.terminate()
        }
    }

    func testPerformanceWithTwoHundredElements() throws {
        var lines: [String] = []
        for (nav, label) in [("perfeager", "eager ScrollView+VStack, 200 elements alive"), ("perf", "lazy List, 200 rows")] {
            app.launch()
            open(nav)
            let list = ["perf.list"].map { id in app.scrollViews[id].exists ? app.scrollViews[id] : (app.collectionViews[id].exists ? app.collectionViews[id] : app.tables[id]) }[0]
            XCTAssertTrue(list.waitForExistence(timeout: 5))
            lines.append("== \(label)")
            func updates() -> Int {
                let text = app.staticTexts["demo.diag"].label
                let part = text.components(separatedBy: " ").first { $0.hasPrefix("updates=") } ?? "updates=0"
                return Int(part.dropFirst(8)) ?? 0
            }
            sleep(1)
            lines.append("at rest: \(app.staticTexts["demo.diag"].label.components(separatedBy: " dry=")[0])")
            let before = updates()
            let start = Date()
            for _ in 0..<5 { list.swipeUp(velocity: .fast) }
            sleep(1)
            lines.append("5 fast swipes: \(updates() - before) frame updates in \(String(format: "%.1f", Date().timeIntervalSince(start))) s (including swipe setup)")
            for round in 1...3 {
                // The middle of the list: whichever row is there is the target.
                _ = try pointAndSend(at: list, name: "perf-\(nav)-round\(round)")
                sleep(2)
                lines.append("round \(round): \(app.staticTexts["demo.diag"].label.components(separatedBy: " dry=")[0])")
                list.swipeUp(velocity: .fast)
            }
            app.terminate()
        }
        try lines.joined(separator: "\n").write(to: overigDir.appending(path: "perf-diagnostics.txt"), atomically: true, encoding: .utf8)
    }

    func testPointingStartsWhileTheAppKeyboardIsOpen() throws {
        app.launch()
        open("checkout")
        let name = app.textFields["checkout.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        openPanel()
        startPointing()
        XCTAssertTrue(app.buttons["nitpick.cancel-pointing"].exists)
    }

    func testPointingStartsWhileASecureFieldHasFocus() throws {
        app.launch()
        open("checkout")
        let password = app.secureTextFields["checkout.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.tap()
        sleep(1)
        openPanel()
        startPointing()
        XCTAssertTrue(app.buttons["nitpick.cancel-pointing"].exists)
    }

    /// Only `configure` and the markers: no `.nitpick()` modifier on the root view.
    func testWorksWithoutTheRootModifier() throws {
        app.launchEnvironment["NITPICK_DEMO_NO_MODIFIER"] = "1"
        app.launch()
        open("checkout")
        let run = try pointAndSend(at: app.buttons["checkout.pay"], name: "no-modifier", comment: "Works without .nitpick()")
        XCTAssertEqual(run.payload["element"] as? String, "checkout.pay_button")
        XCTAssertEqual(run.payload["element_match"] as? String, "exact")
    }

    func testOwnButtonOpensPanelWithoutTab() throws {
        app.launchEnvironment["NITPICK_DEMO_TAB"] = "off"
        app.launch()
        XCTAssertFalse(app.buttons["nitpick.tab"].exists)
        let own = app.buttons["demo.own-button"]
        XCTAssertTrue(own.waitForExistence(timeout: 10))
        own.tap()
        XCTAssertTrue(app.buttons["nitpick.close"].waitForExistence(timeout: 5))
    }

    /// The tab only shows on a screen in `tabScreens`: on Checkout (in the list) it does, on Home (outside it) it does not.
    /// The panel can still be opened from the app's own button on Home.
    func testTabShowsOnAScreenInTheListAndNotOnAScreenOutsideIt() throws {
        app.launchEnvironment["NITPICK_DEMO_SCREENS"] = "Checkout"
        app.launch()
        let tab = app.buttons["nitpick.tab"]
        XCTAssertTrue(app.buttons["nav.checkout"].waitForExistence(timeout: 10))
        // Home is not in the list: no tab.
        XCTAssertFalse(tab.waitForExistence(timeout: 2), "the tab must not show on Home")
        listShot("swift-home-without-tab")
        open("checkout")
        XCTAssertTrue(app.buttons["checkout.pay"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "the tab must show on Checkout")
        listShot("swift-checkout-with-tab")
        // Back to Home: the tab goes again.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["nav.checkout"].waitForExistence(timeout: 5))
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: tab)], timeout: 5)
        // The own button works outside the list.
        let own = app.buttons["demo.own-button"]
        XCTAssertTrue(own.waitForExistence(timeout: 5))
        own.tap()
        XCTAssertTrue(app.buttons["nitpick.close"].waitForExistence(timeout: 5), "present() works outside the list")
    }

    /// Writes a screenshot into qa/evidence/lipje-schermen/swift in the repository.
    func listShot(_ name: String) {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let dir = url.appending(path: "qa/evidence/lipje-schermen/swift", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: dir.appending(path: "\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTabLetsTouchesThroughToTheApp() throws {
        app.launch()
        // Tap the app under the invisible parts of the component's window: navigation must work.
        open("checkout")
        XCTAssertTrue(app.buttons["checkout.pay"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["nav.checkout"].waitForExistence(timeout: 5))
    }

    /// The panel follows the device language: footer, title and kinds from the shared translations.
    func testTextsFollowTheDeviceLanguage() throws {
        for (language, locale) in [("nl", "nl_NL"), ("en", "en_US"), ("ja", "ja_JP"), ("ar", "ar_EG"), ("zh-Hant", "zh_TW")] {
            let expected = try texts(language == "zh-Hant" ? "zh-Hant" : language)
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            openPanel()
            let footer = app.staticTexts["nitpick.footer"]
            XCTAssertTrue(footer.waitForExistence(timeout: 5), "no footer in \(language)")
            XCTAssertEqual(footer.label, expected["privacyNote"], "footer in \(language)")
            XCTAssertTrue(app.buttons["nitpick.kind.general"].label.contains(expected["general"]!), "general in \(language)")
            XCTAssertTrue(app.buttons["nitpick.kind.specific"].label.contains(expected["specific"]!), "specific in \(language)")
            XCTAssertTrue(app.staticTexts[expected["title"]!].exists, "title in \(language)")
            screenshot("panel-\(language)")
            app.terminate()
        }
    }

    /// Arabic runs from right to left, also in an app that runs from left to right: the panel follows the chosen
    /// language, not the app. Compared with English by where the close button sits next to the title.
    func testArabicPanelRunsFromRightToLeftInAnAppThatRunsLeftToRight() throws {
        func closeIsLeftOfTitle(language: String) throws -> Bool {
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment["NITPICK_DEMO_LANGUAGE"] = language
            app.launch()
            openPanel()
            let title = app.staticTexts[try texts(language)["title"]!]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            let close = app.buttons["nitpick.close"]
            screenshot("panel-\(language)-forced-in-english-app")
            let result = close.frame.midX < title.frame.midX
            app.terminate()
            return result
        }
        XCTAssertFalse(try closeIsLeftOfTitle(language: "en"), "English: the close button is on the right")
        XCTAssertTrue(try closeIsLeftOfTitle(language: "ar"), "Arabic: the close button is on the left")
    }

    /// The accent color goes to the send button; the form is kept as evidence.
    func testAccentColorGoesToTheSendButton() throws {
        app.launchEnvironment["NITPICK_DEMO_COLOR"] = "FFCC00"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        open("checkout")
        let run = try pointAndSend(at: app.buttons["checkout.pay"], name: "accent", comment: "Accent color check")
        XCTAssertEqual(run.payload["kind"] as? String, "specific")
        // Again, up to the form, to look at the colors. The button is found before the panel covers the screen.
        let payFrame = app.buttons["checkout.pay"].frame
        XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 10), "the panel did not close after sending")
        openPanel()
        startPointing()
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: payFrame.midX, dy: payFrame.midY)).tap()
        let send = app.buttons["nitpick.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        sleep(1)
        let shot = XCUIScreen.main.screenshot()
        try shot.pngRepresentation.write(to: overigDir.appending(path: "form-accent.png"))
        let image = try XCTUnwrap(shot.image.cgImage)
        let scale = Double(image.width) / Double(app.windows.firstMatch.frame.width)
        func pixel(_ point: CGPoint) -> (r: Int, g: Int, b: Int) {
            var px = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let x = Int(Double(point.x) * scale), y = Int(Double(point.y) * scale)
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
            return (Int(px[0]), Int(px[1]), Int(px[2]))
        }
        let frame = send.frame
        let fill = pixel(CGPoint(x: frame.minX + 14, y: frame.midY))
        XCTAssertTrue(fill.r > 235 && fill.g > 185 && fill.g < 220 && fill.b < 40, "send button is not the accent color: \(fill)")
    }

    /// The brand mark with the domain is off by default and shows with the option.
    func testBrandMarkIsOffByDefaultAndOnWithTheOption() throws {
        app.launch()
        openPanel()
        XCTAssertFalse(app.descendants(matching: .any)["nitpick.brand"].exists)
        app.terminate()
        app.launchEnvironment["NITPICK_DEMO_BRAND"] = "1"
        app.launch()
        openPanel()
        XCTAssertTrue(app.descendants(matching: .any)["nitpick.brand"].waitForExistence(timeout: 5))
        screenshot("panel-brand")
    }

    /// Frames are only tracked while the component is open: no frame updates while scrolling with the panel closed.
    func testFramesAreOnlyTrackedWhileTheComponentIsOpen() throws {
        app.launch()
        open("perf")
        let list = app.scrollViews["perf.list"].exists ? app.scrollViews["perf.list"] : (app.collectionViews["perf.list"].exists ? app.collectionViews["perf.list"] : app.tables["perf.list"])
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        func updates() -> Int {
            let text = app.staticTexts["demo.diag"].label
            let part = text.components(separatedBy: " ").first { $0.hasPrefix("updates=") } ?? "updates=-1"
            return Int(part.dropFirst(8)) ?? -1
        }
        sleep(1)
        let atRest = updates()
        for _ in 0..<5 { list.swipeUp(velocity: .fast) }
        sleep(1)
        let afterScrolling = updates()
        XCTAssertEqual(atRest, 0, "frames were tracked at rest with the component closed")
        XCTAssertEqual(afterScrolling, 0, "frames were tracked while scrolling with the component closed")
        openPanel()
        sleep(2)
        let whileOpen = updates()
        XCTAssertGreaterThan(whileOpen, 0, "no frames were tracked while open")
        app.buttons["nitpick.close"].tap()
        sleep(1)
        let afterClosing = updates()
        for _ in 0..<3 { list.swipeUp(velocity: .fast) }
        sleep(1)
        XCTAssertEqual(updates(), afterClosing, "frames were tracked again after closing")
        try "closed at rest: \(atRest)\nclosed after 5 fast swipes: \(afterScrolling)\nopen (panel shown for 2 s): \(whileOpen)\nafter closing, after 3 more swipes: \(updates() - afterClosing) more updates".write(to: overigDir.appending(path: "tracking-closed-open.txt"), atomically: true, encoding: .utf8)
    }

    /// Mean brightness (0 black, 1 white) of a rectangle of the screen, in points.
    func brightness(of shot: XCUIScreenshot, in rect: CGRect) throws -> Double {
        let image = try XCTUnwrap(shot.image.cgImage)
        let scale = Double(image.width) / Double(app.windows.firstMatch.frame.width)
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
        let crop = try XCTUnwrap(image.cropping(to: pixels))
        var px = [UInt8](repeating: 0, count: 4 * 4 * 4)
        let context = CGContext(data: &px, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .medium
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 4, height: 4))
        var total = 0.0
        for i in 0..<16 { total += (0.299 * Double(px[i * 4]) + 0.587 * Double(px[i * 4 + 1]) + 0.114 * Double(px[i * 4 + 2])) / 255 }
        return total / 16
    }

    /// The panel takes the light or dark style of the app's own window, also when that changes while the app runs.
    /// The demo sets the style of its own window; the system style stays as it is, so at least one of the
    /// changes below differs from the system and shows that the panel does not just follow the system.
    func testPanelFollowsLightAndDarkOfTheAppsWindow() throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        var report = ""
        for style in ["light", "dark", "light", "dark"] {
            let button = app.buttons["demo.style-\(style)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "no button for \(style)")
            button.tap()
            sleep(1)
            openPanel()
            let footer = app.staticTexts["nitpick.footer"]
            XCTAssertTrue(footer.waitForExistence(timeout: 5))
            sleep(1)
            let shot = XCUIScreen.main.screenshot()
            let value = try brightness(of: shot, in: footer.frame.insetBy(dx: 0, dy: -2))
            report += "app window \(style): brightness of the panel \(String(format: "%.3f", value))\n"
            if style == "dark" { screenshot("panel-en-dark") } else { screenshot("panel-en-light-after-dark") }
            if style == "dark" {
                XCTAssertLessThan(value, 0.3, "the panel is not dark while the app's window is dark")
            } else {
                XCTAssertGreaterThan(value, 0.7, "the panel is not light while the app's window is light")
            }
            app.buttons["nitpick.close"].tap()
            XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 5))
        }
        try report.write(to: overigDir.appending(path: "panel-follows-app-window.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Review fixes

    /// Counts the pixels of a screenshot in a rectangle (in points of the window) that pass a test on (r, g, b).
    func count(in shot: XCUIScreenshot, rect: CGRect, windowWidth: CGFloat, where matches: (Int, Int, Int) -> Bool) throws -> Int {
        let image = try XCTUnwrap(shot.image.cgImage)
        let scale = CGFloat(image.width) / windowWidth
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !pixels.isEmpty, let crop = image.cropping(to: pixels) else { return 0 }
        let width = crop.width, height = crop.height
        var px = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0
        for i in 0..<(width * height) where matches(Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) { total += 1 }
        return total
    }

    /// The dashed frame of the accent color (magenta, drawn at 55 percent over a light background).
    func isMagenta(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 200 && b > 200 && g < 175 && r - g > 60 && b - g > 60 }
    /// The red of the frame and the tap spot, #FF3B30.
    func isRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 215 && g > 25 && g < 120 && b > 20 && b < 110 }

    /// Where the pointing layer draws its frames and the tap spot: on the physical place of the element, also when the
    /// panel runs from right to left. Two set-ups: an app that runs from right to left (forced, the badge sits on the right) and an English app with an
    /// Arabic panel (the badge sits on the left). A mirrored drawing would show on the other side in both.
    func testPointingFramesAndTapSpotSitAtThePhysicalPlaceInArabic() throws {
        let setups: [(name: String, arguments: [String], language: String?, badgeOnTheRight: Bool)] = [
            ("arabic-app", ["-AppleLanguages", "(ar)", "-AppleLocale", "ar_EG", "-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"], nil, true),
            ("english-app-arabic-panel", ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"], "ar", false),
        ]
        var report = ""
        for setup in setups {
            app.launchArguments = setup.arguments
            app.launchEnvironment["NITPICK_DEMO_COLOR"] = "FF00FF"
            if let language = setup.language { app.launchEnvironment["NITPICK_DEMO_LANGUAGE"] = language } else { app.launchEnvironment["NITPICK_DEMO_LANGUAGE"] = "ar" }
            app.launch()
            let badge = app.descendants(matching: .any)["demo.badge"]
            XCTAssertTrue(badge.waitForExistence(timeout: 10), "no badge")
            let window = app.windows.firstMatch.frame
            let frame = badge.frame
            // The badge sits where the layout puts it: a sanity check of the set-up itself.
            XCTAssertEqual(frame.midX > window.width / 2, setup.badgeOnTheRight, "\(setup.name): the badge is on the wrong side to begin with: \(frame)")
            let mirrored = CGRect(x: window.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height)

            openPanel()
            startPointing()
            sleep(1)
            // 1. The dashed frame during pointing.
            let before = XCUIScreen.main.screenshot()
            screenshot("pointing-\(setup.name)-dashed")
            let ring = frame.insetBy(dx: -4, dy: -4), mirroredRing = mirrored.insetBy(dx: -4, dy: -4)
            let dashedHere = try count(in: before, rect: ring, windowWidth: window.width, where: isMagenta)
            let dashedMirrored = try count(in: before, rect: mirroredRing, windowWidth: window.width, where: isMagenta)
            report += "\(setup.name): badge at x \(Int(frame.minX))...\(Int(frame.maxX)); dashed frame pixels at the badge: \(dashedHere), at the mirrored place \(Int(mirrored.minX))...\(Int(mirrored.maxX)): \(dashedMirrored)\n"
            XCTAssertGreaterThan(dashedHere, 40, "\(setup.name): no dashed frame at the physical place of the element")
            XCTAssertEqual(dashedMirrored, 0, "\(setup.name): a frame at the mirrored place")

            // 2. The red frame and the tap spot right after the tap.
            badge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let lit = XCUIScreen.main.screenshot()
            screenshot("pointing-\(setup.name)-lit")
            let redHere = try count(in: lit, rect: frame.insetBy(dx: -10, dy: -10), windowWidth: window.width, where: isRed)
            let redMirrored = try count(in: lit, rect: mirrored.insetBy(dx: -10, dy: -10), windowWidth: window.width, where: isRed)
            report += "\(setup.name): red frame and tap spot pixels at the badge: \(redHere), at the mirrored place: \(redMirrored)\n"
            XCTAssertGreaterThan(redHere, 40, "\(setup.name): no red frame or tap spot at the physical place of the element (or the screenshot came after the 450 ms)")
            XCTAssertEqual(redMirrored, 0, "\(setup.name): a red frame or tap spot at the mirrored place")
            // And the element that was found is the one that is sent: the badge.
            XCTAssertTrue(app.images["nitpick.preview"].waitForExistence(timeout: 10) || app.otherElements["nitpick.preview"].waitForExistence(timeout: 2), "no preview")
            fillCommentAndSend("badge")
            let run = try latestDryRun()
            XCTAssertEqual(run.payload["element"] as? String, "home.badge", "\(setup.name): the element that is sent")
            try? FileManager.default.removeItem(at: dryRunDir)
            try FileManager.default.createDirectory(at: dryRunDir, withIntermediateDirectories: true)
            app.terminate()
        }
        try report.write(to: overigDir.appending(path: "pointing-arabic-physical-place.txt"), atomically: true, encoding: .utf8)
    }

    /// Cancelling while pointing always works: before a tap, after a tap on nothing, again and again.
    func testCancelWhilePointingIsAlwaysPossible() throws {
        app.launch()
        openPanel()
        for round in 1...3 {
            startPointing()
            let cancel = app.buttons["nitpick.cancel-pointing"]
            XCTAssertTrue(cancel.isHittable, "round \(round): Cancel cannot be tapped")
            cancel.tap()
            XCTAssertTrue(app.buttons["nitpick.kind.specific"].waitForExistence(timeout: 5), "round \(round): back at the panel")
            XCTAssertFalse(app.buttons["nitpick.cancel-pointing"].exists, "round \(round): the pointing layer is gone")
        }
        // A tap on empty space ends in the form; pointing again and cancelling still works.
        startPointing()
        tapWindow(x: 0.5, y: 0.93)
        XCTAssertTrue(app.images["nitpick.preview"].waitForExistence(timeout: 10) || app.otherElements["nitpick.preview"].waitForExistence(timeout: 2), "no form after the tap")
        let again = app.buttons["nitpick.pointAgain"]
        XCTAssertTrue(again.waitForExistence(timeout: 5), "no button to point again")
        again.tap()
        let cancel = app.buttons["nitpick.cancel-pointing"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "pointing did not start again")
        XCTAssertTrue(cancel.isHittable, "after a finished pick: Cancel cannot be tapped")
        cancel.tap()
        XCTAssertTrue(app.buttons["nitpick.close"].waitForExistence(timeout: 5))
        app.buttons["nitpick.close"].tap()
        XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 5), "the tab is back after closing")
        screenshot("cancel-pointing-always")
    }

    /// The tab survives the app going to the background and coming back (the scene deactivates and activates again),
    /// and still opens the panel.
    func testTabSurvivesTheAppGoingToTheBackgroundAndBack() throws {
        app.launch()
        let tab = app.buttons["nitpick.tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        for round in 1...3 {
            XCUIDevice.shared.press(.home)
            sleep(1)
            app.activate()
            XCTAssertTrue(tab.waitForExistence(timeout: 10), "round \(round): the tab is gone after coming back")
            XCTAssertTrue(tab.isHittable, "round \(round): the tab cannot be tapped")
        }
        tab.tap()
        XCTAssertTrue(app.buttons["nitpick.close"].waitForExistence(timeout: 5), "the tab does not open the panel after coming back")
    }

    // MARK: Papier: the screens, with where each text sits, for the contrast measurement

    /// A place on the screen, in points, with what is on it. `qa/evidence/swift/papier/contrast.py` measures the
    /// contrast of the text there from the picture of the simulator.
    struct Target: Encodable {
        var name: String
        var kind: String   // text, rows, multi, field, send, tab
        var x: Double, y: Double, width: Double, height: Double
    }

    func target(_ name: String, _ element: XCUIElement, kind: String = "text") {
        let f = element.frame
        targets.append(Target(name: name, kind: kind, x: f.minX, y: f.minY, width: f.width, height: f.height))
    }

    /// A picture of the screen in the evidence folder, with the places that were recorted since the last one.
    func evidence(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: evidenceDir.appending(path: "\(name).png"))
        let window = app.windows.firstMatch.frame
        let info = EvidenceInfo(window_width: window.width, window_height: window.height, targets: targets)
        if let data = try? JSONEncoder().encode(info) { try? data.write(to: evidenceDir.appending(path: "\(name).json")) }
        targets = []
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    struct EvidenceInfo: Encodable {
        var window_width: Double, window_height: Double
        var targets: [Target]
    }

    func preview() -> XCUIElement {
        app.descendants(matching: .any)["nitpick.preview"]
    }

    /// The whole way: tab, panel, pointing, form, thank-you, in light or dark, with or without the accent color.
    func papierFlow(dark: Bool, accent: Bool) throws {
        let en = try texts("en")
        let suffix = (accent ? "accent-" : "") + (dark ? "donker" : "licht")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if accent { app.launchEnvironment["NITPICK_DEMO_COLOR"] = "6E56CF" }
        app.launch()
        let style = app.buttons[dark ? "demo.style-dark" : "demo.style-light"]
        XCTAssertTrue(style.waitForExistence(timeout: 10))
        style.tap()
        sleep(1)
        open("checkout")
        XCTAssertTrue(app.buttons["checkout.pay"].waitForExistence(timeout: 5))
        let tab = app.buttons["nitpick.tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        sleep(1)

        // 1. The tab.
        target("tab", tab, kind: "tab")
        evidence("lipje-\(suffix)")
        tab.tap()
        XCTAssertTrue(app.buttons["nitpick.close"].waitForExistence(timeout: 5))
        sleep(1)

        // 2. The panel with the two rows.
        target("title", app.staticTexts[en["title"]!])
        target("close", app.buttons["nitpick.close"])
        target("row General", app.buttons["nitpick.kind.general"], kind: "rows")
        target("row Point at something", app.buttons["nitpick.kind.specific"], kind: "rows")
        target("footer", app.staticTexts["nitpick.footer"])
        evidence("paneel-\(suffix)")

        // 3. One tap on the row: the pill at the top.
        app.buttons["nitpick.kind.specific"].tap()
        let cancel = app.buttons["nitpick.cancel-pointing"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "the row did not start pointing")
        sleep(1)
        target("pill text", app.staticTexts[en["pointBanner"]!])
        target("pill Cancel", cancel)
        evidence("aanwijzen-\(suffix)")

        // 4. Tap the pay button: the form with the preview.
        let pay = app.buttons["checkout.pay"]
        pay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview().waitForExistence(timeout: 10), "no preview")
        sleep(1)
        target("title", app.staticTexts[en["title"]!])
        target("Cancel", app.buttons["nitpick.close"])
        // No name of an element in the form: the preview shows what was pointed at.
        XCTAssertFalse(app.staticTexts["nitpick.elementName"].exists || app.staticTexts["nitpick.elementNone"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'checkout.pay' OR label CONTAINS[c] 'specific element'")).firstMatch.exists, "the form shows the name of the element")
        target("Remove image", app.buttons["nitpick.removeImage"])
        target("Point at an element", app.buttons["nitpick.pointAgain"])
        target("label of the field", app.staticTexts[en["commentSpecific"]!])
        target("Send", app.buttons["nitpick.send"], kind: "send")
        target("footer", app.staticTexts["nitpick.footer"])
        evidence("formulier-\(suffix)")

        // 5. Type, with the keyboard open: the text in the field.
        let field = app.textViews["nitpick.comment"].exists ? app.textViews["nitpick.comment"] : app.textFields["nitpick.comment"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("The price is cut off on this card.")
        sleep(1)
        target("text in the field", field, kind: "field")
        target("Send", app.buttons["nitpick.send"], kind: "send")
        evidence("formulier-getypt-\(suffix)")

        // 6. Send: the thank-you.
        app.buttons["nitpick.send"].tap()
        let sent = app.descendants(matching: .any)["nitpick.sent"]
        XCTAssertTrue(sent.waitForExistence(timeout: 5), "no thank-you")
        sleep(1)
        let sentClose = app.buttons["nitpick.sent-close"]
        target("thank-you", sent, kind: "multi")
        if sentClose.exists { target("Close", sentClose) }
        evidence("bedankje-\(suffix)")
        XCTAssertTrue(sent.label.contains(en["sent"]!))
        XCTAssertTrue(sentClose.exists, "no Close under the thank-you")
        // It goes away by itself after 2.5 seconds: the tab comes back without a tap.
        XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 8), "the thank-you did not go away by itself")
    }

    // MARK: Papier: the addition after the build

    /// The form shows no name of an element, and the agent still gets it in the payload.
    func testFormShowsNoElementNameButPayloadKeepsIt() throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        open("checkout")
        XCTAssertTrue(app.buttons["checkout.pay"].waitForExistence(timeout: 5))
        openPanel()
        startPointing()
        app.buttons["checkout.pay"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview().waitForExistence(timeout: 10), "no preview")
        sleep(1)
        XCTAssertFalse(app.staticTexts["nitpick.elementName"].exists)
        XCTAssertFalse(app.staticTexts["nitpick.elementNone"].exists)
        let names = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'checkout.pay' OR label CONTAINS[c] 'specific element'"))
        XCTAssertEqual(names.count, 0, "the form shows the name of the element")
        XCTAssertTrue(app.buttons["nitpick.removeImage"].exists && app.buttons["nitpick.pointAgain"].exists)
        fillCommentAndSend("Too small")
        let run = try latestDryRun()
        XCTAssertEqual(run.payload["element"] as? String, "checkout.pay_button")
        XCTAssertEqual(run.payload["element_match"] as? String, "exact")
    }

    /// The tab on the right and on the left, in light and dark: the rim in the color only on the side of the app.
    func testTabRimOnTheSideOfTheApp() throws {
        for edge in ["right", "left"] {
            for dark in [false, true] {
                app.terminate()
                app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
                app.launchEnvironment["NITPICK_DEMO_COLOR"] = "6E56CF"
                app.launchEnvironment["NITPICK_DEMO_TAB"] = edge == "left" ? "left" : "right"
                app.launch()
                let style = app.buttons[dark ? "demo.style-dark" : "demo.style-light"]
                XCTAssertTrue(style.waitForExistence(timeout: 10))
                style.tap()
                let tab = app.buttons["nitpick.tab"]
                XCTAssertTrue(tab.waitForExistence(timeout: 10))
                sleep(1)
                let name = "lipje-\(edge == "left" ? "links" : "rechts")-\(dark ? "donker" : "licht")"
                evidence(name)
                try? tab.screenshot().pngRepresentation.write(to: evidenceDir.appending(path: "\(name)-detail.png"))
            }
        }
    }

    /// Closing moves: a picture in the middle of the movement, in light and dark. The picture is taken at once after the tap on
    /// Close; the panel is then on its way down, with the dim layer half faded.
    func closingHalfway(dark: Bool) throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let style = app.buttons[dark ? "demo.style-dark" : "demo.style-light"]
        XCTAssertTrue(style.waitForExistence(timeout: 10))
        style.tap()
        sleep(1)
        open("checkout")
        openPanel()
        sleep(1)
        let close = app.buttons["nitpick.close"]
        // The tap waits until the movement is over, so pictures are taken next to it on another thread, one after the other;
        // the test keeps the one where the panel is about halfway down (the dim layer is then half faded too).
        let frames = FrameCollector()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            let start = Date()
            while Date().timeIntervalSince(start) < 1.2 {
                frames.add(XCUIScreen.main.screenshot(), at: Date().timeIntervalSince(start))
            }
            group.leave()
        }
        close.tap()
        group.wait()
        let mode = dark ? "donker" : "licht"
        try? FileManager.default.createDirectory(at: overigDir.appending(path: "sluiten-frames"), withIntermediateDirectories: true)
        for (index, frame) in frames.all.enumerated() {
            try frame.shot.pngRepresentation.write(to: overigDir.appending(path: "sluiten-frames/\(mode)-\(String(format: "%02d", index))-\(Int(frame.at * 1000))ms.png"))
        }
        XCTAssertGreaterThan(frames.all.count, 3, "too few pictures of the movement")
        XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 5), "the tab is back after the movement")
        XCTAssertFalse(app.buttons["nitpick.close"].exists)
    }

    final class FrameCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(shot: XCUIScreenshot, at: Double)] = []
        func add(_ shot: XCUIScreenshot, at: Double) { lock.lock(); items.append((shot, at)); lock.unlock() }
        var all: [(shot: XCUIScreenshot, at: Double)] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testClosingMovesHalfwayLight() throws { try closingHalfway(dark: false) }
    func testClosingMovesHalfwayDark() throws { try closingHalfway(dark: true) }

    func testPapierScreensLight() throws { try papierFlow(dark: false, accent: false) }
    func testPapierScreensDark() throws { try papierFlow(dark: true, accent: false) }
    func testPapierScreensWithAccentColorLight() throws { try papierFlow(dark: false, accent: true) }
    func testPapierScreensWithAccentColorDark() throws { try papierFlow(dark: true, accent: true) }

    /// The panel in German and in Arabic (an English app, the panel follows the chosen language).
    func testPanelInGermanAndArabicForEvidence() throws {
        for language in ["de", "ar"] {
            let expected = try texts(language)
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment["NITPICK_DEMO_LANGUAGE"] = language
            app.launch()
            openPanel()
            XCTAssertTrue(app.staticTexts[expected["title"]!].waitForExistence(timeout: 5), "title in \(language)")
            XCTAssertEqual(app.staticTexts["nitpick.footer"].label, expected["privacyNote"])
            sleep(1)
            target("title", app.staticTexts[expected["title"]!])
            target("close", app.buttons["nitpick.close"])
            target("row General", app.buttons["nitpick.kind.general"], kind: "rows")
            target("row Point at something", app.buttons["nitpick.kind.specific"], kind: "rows")
            target("footer", app.staticTexts["nitpick.footer"])
            evidence("paneel-\(language)")
            app.terminate()
        }
    }

    /// A small screen (run it on the iPhone 16e) with the largest text size that is not an accessibility size:
    /// Send and the line under it stay visible, also with the keyboard open.
    func testSmallScreenWithLargeTextKeepsSendAndFooterVisible() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]?.replacingOccurrences(of: " ", with: "-") ?? "toestel"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        openPanel()
        sleep(1)
        let window = app.windows.firstMatch.frame
        let footer = app.staticTexts["nitpick.footer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        XCTAssertTrue(window.contains(footer.frame), "the footer is not in the window: \(footer.frame) in \(window)")
        XCTAssertTrue(footer.isHittable || window.contains(footer.frame), "the footer is not visible")
        XCTAssertTrue(app.buttons["nitpick.kind.general"].isHittable, "the row General cannot be tapped")
        XCTAssertTrue(app.buttons["nitpick.kind.specific"].isHittable, "the row Point at something cannot be tapped")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: evidenceDir.appending(path: "klein-scherm-grote-tekst-paneel-\(device).png"))

        openGeneralForm()
        sleep(1)
        let send = app.buttons["nitpick.send"]
        XCTAssertTrue(window.contains(send.frame) && send.isHittable, "Send is not visible: \(send.frame) in \(window)")
        XCTAssertTrue(window.contains(footer.frame), "the footer is not visible in the form: \(footer.frame)")
        XCTAssertGreaterThanOrEqual(send.frame.height, 44, "Send is at least 44 points high")
        XCTAssertGreaterThanOrEqual(send.frame.width, 112, "Send is at least 112 points wide")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: evidenceDir.appending(path: "klein-scherm-grote-tekst-formulier-\(device).png"))

        // With the keyboard open: the form scrolls, Send and the line under it stay above the keyboard.
        let field = app.textViews["nitpick.comment"].exists ? app.textViews["nitpick.comment"] : app.textFields["nitpick.comment"]
        field.tap()
        field.typeText("The price is cut off on this card.")
        sleep(1)
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "no keyboard")
        XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY + 1, "Send is behind the keyboard")
        XCTAssertLessThanOrEqual(footer.frame.maxY, keyboard.frame.minY + 1, "the footer is behind the keyboard")
        XCTAssertTrue(send.isHittable, "Send cannot be tapped with the keyboard open")
        XCTAssertGreaterThan(send.frame.minY, 0)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: evidenceDir.appending(path: "klein-scherm-grote-tekst-toetsenbord-\(device).png"))
        // The form for pointing, with the largest text size too: the tallest form there is.
        app.buttons["nitpick.close"].tap()
        XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 5))
        open("checkout")
        let pay = app.buttons["checkout.pay"]
        XCTAssertTrue(pay.waitForExistence(timeout: 5))
        openPanel()
        startPointing()
        pay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(preview().waitForExistence(timeout: 10), "no preview")
        sleep(1)
        XCTAssertTrue(window.contains(send.frame) && send.isHittable, "pointing form: Send is not visible: \(send.frame) in \(window)")
        XCTAssertTrue(window.contains(footer.frame), "pointing form: the footer is not visible: \(footer.frame)")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: evidenceDir.appending(path: "klein-scherm-grote-tekst-aanwijsformulier-\(device).png"))
        field.tap()
        field.typeText("The price is cut off on this card.")
        sleep(1)
        XCTAssertLessThanOrEqual(send.frame.maxY, keyboard.frame.minY + 1, "pointing form: Send is behind the keyboard")
        XCTAssertLessThanOrEqual(footer.frame.maxY, keyboard.frame.minY + 1, "pointing form: the footer is behind the keyboard")
        XCTAssertTrue(send.isHittable, "pointing form: Send cannot be tapped with the keyboard open")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: evidenceDir.appending(path: "klein-scherm-grote-tekst-aanwijsformulier-toetsenbord-\(device).png"))
    }

    // MARK: Focus of a screen (TabView)

    /// qa/evidence/swift/focus in the repository.
    var focusEvidenceDir: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url.appending(path: "qa/evidence/swift/focus")
    }

    /// Two tabs with a card on the same place, both mounted. The tap spots of the brief, in points of the window:
    /// A (Home shown, inside both cards), B (Settings shown, inside the hidden card of Home only, beyond 44 points of the
    /// visible card), C (Settings shown, on the visible card). With the focus passed, only the cards of the shown tab count.
    /// `TEST_RUNNER_NITPICK_TABS_FOCUS=off` leaves the focus out of the demo and only measures (the "before" table).
    func testTabViewFocusKeepsTheHiddenTabOut() throws {
        let passesFocus = ProcessInfo.processInfo.environment["NITPICK_TABS_FOCUS"] != "off"
        let mode = passesFocus ? "na" : "voor"
        app.launchEnvironment["NITPICK_DEMO_TABS_FOCUS"] = passesFocus ? "on" : "off"
        app.launch()
        open("tabs")
        let homeCard = app.descendants(matching: .any)["tabs.home-card"]
        XCTAssertTrue(homeCard.waitForExistence(timeout: 10), "tab Home not shown")
        // Visit Settings and come back, so both tabs have been mounted.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tabs.settings-card"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(homeCard.waitForExistence(timeout: 5))
        try FileManager.default.createDirectory(at: focusEvidenceDir, withIntermediateDirectories: true)

        func pick(_ spot: String, x: CGFloat, y: CGFloat) throws -> (element: String, match: String, screen: String) {
            for folder in (try? FileManager.default.contentsOfDirectory(at: dryRunDir, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: folder)
            }
            openPanel(); startPointing()
            app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
            XCTAssertTrue(app.buttons["nitpick.send"].waitForExistence(timeout: 10), "no form after the tap on \(spot)")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: focusEvidenceDir.appending(path: "\(mode)-\(spot)-formulier.png"))
            fillCommentAndSend("focus \(spot)")
            let run = try latestDryRun()
            let sentClose = app.buttons["nitpick.sent-close"]
            if sentClose.waitForExistence(timeout: 5) { sentClose.tap() }
            XCTAssertTrue(app.buttons["nitpick.tab"].waitForExistence(timeout: 5), "the panel did not close after \(spot)")
            return (run.payload["element"] as? String ?? "geen", run.payload["element_match"] as? String ?? "?", run.payload["screen"] as? String ?? "-")
        }

        // A: Home shown. Tap 30 points below the top of the cards: inside the card of Settings too (70 points high).
        let homeFrame = homeCard.frame
        let a = try pick("A-home", x: homeFrame.midX, y: homeFrame.minY + 30)

        // B and C: Settings shown.
        app.tabBars.buttons["Settings"].tap()
        let settingsCard = app.descendants(matching: .any)["tabs.settings-card"]
        XCTAssertTrue(settingsCard.waitForExistence(timeout: 5))
        sleep(1)
        let settingsFrame = settingsCard.frame
        // 60 points under the visible card: inside the card of Home (160 points high) and beyond 44 points of the visible one.
        let b = try pick("B-settings-onder-de-kaart", x: settingsFrame.midX, y: settingsFrame.maxY + 60)
        let c = try pick("C-settings-kaart", x: settingsFrame.midX, y: settingsFrame.midY)

        let rows: [[String: String]] = [
            ["plek": "A", "tabblad": "Home", "tik": "\(Int(homeFrame.midX)),\(Int(homeFrame.minY + 30))", "verwacht": "tabs.home_card exact", "kreeg": "\(a.element) \(a.match)", "scherm": a.screen],
            ["plek": "B", "tabblad": "Settings", "tik": "\(Int(settingsFrame.midX)),\(Int(settingsFrame.maxY + 60))", "verwacht": "geen none", "kreeg": "\(b.element) \(b.match)", "scherm": b.screen],
            ["plek": "C", "tabblad": "Settings", "tik": "\(Int(settingsFrame.midX)),\(Int(settingsFrame.midY))", "verwacht": "tabs.settings_card exact", "kreeg": "\(c.element) \(c.match)", "scherm": c.screen],
        ]
        let json = try JSONSerialization.data(withJSONObject: ["modus": mode, "focus_doorgegeven": passesFocus, "plekken": rows], options: [.prettyPrinted, .sortedKeys])
        try json.write(to: focusEvidenceDir.appending(path: "\(mode)-uitkomst.json"))

        // Without the focus the test only measures; with it, every spot must be right.
        guard passesFocus else { return }
        XCTAssertEqual(a.element, "tabs.home_card", "A")
        XCTAssertEqual(a.match, "exact", "A")
        XCTAssertEqual(a.screen, "Tabs home", "A")
        XCTAssertEqual(b.element, "geen", "B: a hidden element was chosen")
        XCTAssertEqual(b.match, "none", "B")
        XCTAssertEqual(b.screen, "Tabs settings", "B")
        XCTAssertEqual(c.element, "tabs.settings_card", "C")
        XCTAssertEqual(c.match, "exact", "C")
        XCTAssertEqual(c.screen, "Tabs settings", "C")
    }
}
