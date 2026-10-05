import XCTest

/// The four styles of the tab (brief lipje-stijlen): each style, in light and dark, with the accent color #293582, on the
/// checkout screen of the demo. Every style opens the panel with one tap. The pictures go to qa/evidence/lipje-stijlen.
final class LipjeStijlenUITests: XCTestCase {
    var app: XCUIApplication!

    /// qa/evidence/lipje-stijlen in the repository, found from this file's path.
    var evidenceDir: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // LipjeStijlenUITests.swift, UITests, Demo, swift, packages
        return url.appending(path: "qa/evidence/lipje-stijlen/swift")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: evidenceDir, withIntermediateDirectories: true)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: evidenceDir.appending(path: "\(name).png"))
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Starts the demo with a style, goes to Checkout, and returns the tab.
    private func launch(style: String, dark: Bool, left: Bool = false) -> XCUIElement {
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["NITPICK_DEMO_COLOR"] = "293582"
        app.launchEnvironment["NITPICK_DEMO_TABSTYLE"] = style
        app.launchEnvironment["NITPICK_DRYRUN_DIR"] = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "nitpick-lipje-\(UUID().uuidString)").path
        if left { app.launchEnvironment["NITPICK_DEMO_TAB"] = "left" }
        app.launch()
        let appearance = app.buttons[dark ? "demo.style-dark" : "demo.style-light"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 10))
        appearance.tap()
        let link = app.buttons["nav.checkout"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.buttons["checkout.pay"].waitForExistence(timeout: 5))
        let tab = app.buttons["nitpick.tab"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "\(style): no tab")
        sleep(1)
        return tab
    }

    private func checkTouchAreaAndOpen(_ tab: XCUIElement, style: String) {
        let frame = tab.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(style): touch area is at least 44 wide")
        XCTAssertGreaterThanOrEqual(frame.height, 76, "\(style): touch area is at least 76 high")
        XCTAssertEqual(tab.label, "Feedback", "\(style): VoiceOver label")
        XCTAssertTrue(tab.isHittable, "\(style): the tab can be tapped")
    }

    func testEveryStyleInLightAndDark() throws {
        for style in ["accent", "material", "ink", "icon"] {
            for dark in [false, true] {
                let tab = launch(style: style, dark: dark)
                checkTouchAreaAndOpen(tab, style: style)
                save("\(style)-\(dark ? "donker" : "licht")")
                // One tap opens the panel, whatever the style.
                tab.tap()
                XCTAssertTrue(app.buttons["nitpick.close"].waitForExistence(timeout: 5), "\(style): the tab did not open the panel")
                app.terminate()
            }
        }
    }

    func testEveryStyleOnTheLeftEdge() throws {
        for style in ["accent", "material", "ink", "icon"] {
            let tab = launch(style: style, dark: false, left: true)
            checkTouchAreaAndOpen(tab, style: style)
            XCTAssertLessThan(tab.frame.minX, 1, "\(style): on the left edge")
            save("\(style)-links-licht")
            app.terminate()
        }
    }

    /// The icon tab while it is touched: it grows inward to "Feedback". A press of two seconds, and a picture taken from
    /// another thread while the finger is down.
    func testIconTabWhileTouched() throws {
        for dark in [false, true] {
            let tab = launch(style: "icon", dark: dark)
            let done = expectation(description: "picture")
            let file = evidenceDir.appending(path: "icon-aangeraakt-\(dark ? "donker" : "licht").png")
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                let shot = XCUIScreen.main.screenshot()
                try? shot.pngRepresentation.write(to: file)
                done.fulfill()
            }
            tab.press(forDuration: 2.0)
            wait(for: [done], timeout: 5)
            app.terminate()
        }
    }
}
