import Testing
import Foundation
import SwiftUI
import UIKit
import Vision
@testable import Nitpick

/// The addition after the build of Papier (`docs/ontwerp/component/papier.md`, "Aanvulling na de bouw"):
/// one kind on opens that kind at once, no name of an element in the form, the rim of the tab on the side of the app,
/// and closing that moves.
extension SharedState {
@MainActor
@Suite("Papier: de aanvulling na de bouw", .serialized)
struct PapierGelijkTests {
    func controller(directory: URL = FileManager.default.temporaryDirectory.appending(path: "nitpick-gelijk-\(UUID().uuidString)", directoryHint: .isDirectory)) -> NitpickController {
        let controller = NitpickController()
        controller.configure(appKey: "npk_test", options: NitpickOptions(dryRun: true, dryRunDirectory: directory, language: "en"))
        return controller
    }

    func settings(general: Bool, specific: Bool) -> RemoteSettings {
        RemoteSettings(active: true, general: general, specific: specific, texts: [:])
    }

    func wait(until condition: () -> Bool, timeout: Duration = .seconds(5)) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(25)) }
    }

    // MARK: One kind on opens that kind at once

    @Test func onlyGeneralOnOpensTheFormAtOnce() throws {
        let controller = controller()
        // present() ends in openSession(settings:in:): with a scene it also makes the window.
        controller.openSession(settings: settings(general: true, specific: false), in: nil)
        let session = try #require(controller.session)
        #expect(session.phase == .panel)
        #expect(!session.showsChoice, "no panel with one row")
        #expect(session.kind == .general)
        #expect(session.pick == nil)
        controller.dismiss()
    }

    @Test func onlyPointingOnStartsPointingAtOnce() throws {
        let controller = controller()
        controller.openSession(settings: settings(general: false, specific: true), in: nil)
        let session = try #require(controller.session)
        #expect(session.phase == .picking, "no panel with one row: pointing starts")
        #expect(session.kind == .specific)
        // There is no panel to go back to: Cancel while pointing closes the component.
        session.cancelPicking()
        #expect(controller.session == nil)
    }

    @Test func bothKindsOnStillShowTheTwoRows() throws {
        let controller = controller()
        controller.openSession(settings: settings(general: true, specific: true), in: nil)
        let session = try #require(controller.session)
        #expect(session.phase == .panel && session.showsChoice)
        session.choose(.specific)
        session.cancelPicking()
        #expect(controller.session === session, "with both kinds Cancel brings the user back to the rows")
        #expect(session.showsChoice && session.phase == .panel)
        controller.dismiss()
    }

    // MARK: The form without the name of an element

    private func formSession(controller: NitpickController, elementName: String?) -> FeedbackSession {
        let session = FeedbackSession(controller: controller, scene: nil, settings: settings(general: true, specific: true))
        let size = CGSize(width: 64, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGray4.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let element = elementName.map { MarkedElement(id: UUID(), name: $0, kind: .element, frame: CGRect(x: 20, y: 700, width: 350, height: 52), screenID: nil) }
        session.pick = PickedTarget(tap: CGPoint(x: 100, y: 720), element: element, match: element == nil ? .none : .exact,
                                    screen: "Checkout", viewport: CGSize(width: 393, height: 852), scale: 3)
        session.screenshotImage = image
        session.screenshot = image.jpegData(compressionQuality: 0.8)
        session.kind = .specific
        session.showsChoice = false
        return session
    }

    /// What can be read in the form on the screen, found by text recognition on a picture of it.
    private func readForm(of session: FeedbackSession) async throws -> [String] {
        // The part between the header and the footer (a scroll view is not drawn by the renderer).
        let view = PanelLayer(session: session, palette: NitpickPalette.resolve(.standard, in: EnvironmentValues()), startsShown: true).content
            .padding(20)
            .frame(width: 393, height: 500, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let picture = try #require(renderer.uiImage)
        let cgImage = try #require(picture.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    @Test func theFormShowsNoNameOfAnElementButThePayloadKeepsIt() async throws {
        let controller = controller()
        let named = formSession(controller: controller, elementName: "checkout.pay_button")
        let lines = try await readForm(of: named)
        let joined = lines.joined(separator: " | ")
        // The form is on the screen: the buttons and the question can be read.
        #expect(joined.contains("Remove image"), "the form is not on the screen: \(joined)")
        #expect(joined.contains("Point at an element") && joined.contains("What is wrong"), "\(joined)")
        // No name of an element, however it is written.
        #expect(!joined.lowercased().contains("checkout"), "\(joined)")
        #expect(!joined.contains("pay_button"), "\(joined)")

        let none = formSession(controller: controller, elementName: nil)
        let noneLines = try await readForm(of: none).joined(separator: " | ")
        #expect(noneLines.contains("Remove image"), "\(noneLines)")
        #expect(!noneLines.lowercased().contains("no specific element"), "\(noneLines)")
        #expect(!noneLines.lowercased().contains("specific element"), "\(noneLines)")

        // The agent still gets the name.
        let pick = try #require(named.pick)
        let payload = try PayloadFactory.specific(comment: "Te klein", pick: pick, facts: DeviceFacts.current()).jsonData()
        let object = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        #expect(object["element"] as? String == "checkout.pay_button", "\(object)")
    }

    // MARK: The rim of the tab

    /// The surface of the tab as pixels, one pixel to the point: the rim color is pure red.
    private func tabPixels(edge: NitpickTabEdge, dark: Bool) throws -> (width: Int, height: Int, color: (Int, Int) -> (r: Int, g: Int, b: Int)) {
        let view = TabSurface(edge: edge, rim: Color(red: 1, green: 0, blue: 0))
            .frame(width: TabGeometry.visibleWidth, height: TabGeometry.length)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let cgImage = try #require(renderer.uiImage?.cgImage)
        let width = cgImage.width, height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (width, height, { x, y in
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        })
    }

    private func isRim(_ pixel: (r: Int, g: Int, b: Int)) -> Bool { pixel.r > 200 && pixel.g < 60 && pixel.b < 60 }

    @Test(arguments: [false, true])
    func theRimOfATabOnTheRightSitsOnTheLeftSideOnly(dark: Bool) throws {
        let pixels = try tabPixels(edge: .right, dark: dark)
        let middle = pixels.height / 2
        #expect(pixels.width == 22 && pixels.height == 76)
        // The side of the app: 2 points of rim.
        #expect(isRim(pixels.color(0, middle)) && isRim(pixels.color(1, middle)), "left side: \(pixels.color(0, middle)) \(pixels.color(1, middle))")
        #expect(!isRim(pixels.color(2, middle)), "the rim is 2 points wide")
        // The other sides have none: the screen side, the top and the bottom.
        #expect(!isRim(pixels.color(pixels.width - 1, middle)) && !isRim(pixels.color(pixels.width - 2, middle)))
        for x in 12..<20 {
            #expect(!isRim(pixels.color(x, 1)) && !isRim(pixels.color(x, pixels.height - 2)), "top and bottom at \(x)")
        }
    }

    @Test(arguments: [false, true])
    func theRimOfATabOnTheLeftSitsOnTheRightSideOnly(dark: Bool) throws {
        let pixels = try tabPixels(edge: .left, dark: dark)
        let middle = pixels.height / 2
        let last = pixels.width - 1
        #expect(isRim(pixels.color(last, middle)) && isRim(pixels.color(last - 1, middle)), "right side: \(pixels.color(last, middle)) \(pixels.color(last - 1, middle))")
        #expect(!isRim(pixels.color(last - 2, middle)), "the rim is 2 points wide")
        #expect(!isRim(pixels.color(0, middle)) && !isRim(pixels.color(1, middle)))
        for x in 2..<10 {
            #expect(!isRim(pixels.color(x, 1)) && !isRim(pixels.color(x, pixels.height - 2)), "top and bottom at \(x)")
        }
    }

    // MARK: Closing moves

    @Test func closingTheFormSlidesFirstAndTheWindowGoesAfterTheMovement() async throws {
        let controller = controller()
        controller.openSession(settings: settings(general: true, specific: true), in: nil)
        let session = try #require(controller.session)
        #expect(FeedbackSession.closeDuration == .milliseconds(280), "the same 280 ms as opening")
        session.close()
        #expect(session.isClosing, "the panel starts to move at once")
        #expect(controller.session === session, "but the window stays while it moves")
        try await Task.sleep(for: .milliseconds(120))
        #expect(controller.session === session)
        await wait(until: { controller.session == nil })
        #expect(controller.session == nil, "after the movement the session is gone")
    }

    @Test func closingWhilePointingHasNothingToMove() throws {
        let controller = controller()
        controller.openSession(settings: settings(general: false, specific: true), in: nil)
        let session = try #require(controller.session)
        session.close()
        #expect(controller.session == nil)
    }

    @Test func aSecondCloseDuringTheMovementChangesNothing() async throws {
        let controller = controller()
        controller.openSession(settings: settings(general: true, specific: false), in: nil)
        let session = try #require(controller.session)
        session.close()
        session.close()
        await wait(until: { controller.session == nil })
        #expect(controller.session == nil)
    }
}
}
