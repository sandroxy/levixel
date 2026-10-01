import XCTest
import UIKit

@MainActor
final class RunnerUITests: XCTestCase {
    private let app = XCUIApplication()

    func testNativeGesturesAndSourceRestoration() {
        continueAfterFailure = false
        app.launch()
        openFirst()
        point(0.85, 0.5).press(forDuration: 0.05, thenDragTo: point(0.15, 0.5))
        awaitImage(red: false, name: "paged-second")
        point(0.5, 0.5).press(forDuration: 0.8)
        let action = app.buttons["Inspect"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        capture("actions")
        action.tap()
        XCTAssertTrue(action.waitForNonExistence(timeout: 10))
        dismissDrag()
        awaitStatus("Dismiss 1 second 1 | Action inspect second 1")

        openFirst()
        point(0.5, 0.5).doubleTap()
        point(0.5, 0.5).press(forDuration: 0.05, thenDragTo: point(0.5, 0.78))
        awaitImage(red: true, name: "double-tap-pan")
        app.pinch(withScale: 0.2, velocity: -1)
        dismissDrag()
        awaitStatus("Dismiss 2 first 0 | Action inspect second 1")

        openFirst()
        app.pinch(withScale: 2, velocity: 1)
        point(0.5, 0.5).press(forDuration: 0.05, thenDragTo: point(0.5, 0.78))
        awaitImage(red: true, name: "pinch-pan")
        app.pinch(withScale: 0.2, velocity: -1)
        point(0.5, 0.5).tap()
        awaitStatus("Dismiss 3 first 0 | Action inspect second 1")
        capture("restored-sources")
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y))
    }

    private func openFirst() {
        let source = app.descendants(matching: .any).matching(identifier: "source-first").firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        XCTAssertTrue(source.isHittable)
        source.tap()
        awaitImage(red: true, name: "opened-first")
    }

    private func dismissDrag() {
        point(0.5, 0.5).press(forDuration: 0.05, thenDragTo: point(0.5, 0.92))
    }

    private func awaitStatus(_ text: String) {
        let status = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Native event identity: \(text)")
    }

    private func awaitImage(red: Bool, name: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.imageCoversViewport(red: red) == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed,
                       "The native image must cover a point outside the Flutter thumbnails: \(name)")
        capture(name)
    }

    private func imageCoversViewport(red: Bool) -> Bool {
        guard let screen = XCUIScreen.main.screenshot().image.cgImage,
              let sample = screen.cropping(to: CGRect(x: CGFloat(Int(Double(screen.width) * 0.08)),
                  y: CGFloat(screen.height / 2), width: 1, height: 1)) else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
        context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return red ? pixel[0] > 150 && pixel[2] < 110 : pixel[2] > 150 && pixel[0] < 100
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
