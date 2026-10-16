import UIKit
import XCTest
@testable import Levixel

final class LevixelUniSourceUpdatesTests: XCTestCase {
    func testGestureCloseRejectsLateSourceChangesInBothVisibilityModes() throws {
        for visibility in ["visible", "hidden"] {
            for change in ["move", "replace", "remove"] {
                try checkClosingUpdates(visibility: visibility, change: change, gesture: true)
            }
        }
    }

    func testProgrammaticCloseRejectsLateSourceChangesInBothVisibilityModes() throws {
        for visibility in ["visible", "hidden"] {
            try checkClosingUpdates(visibility: visibility, change: "replace", gesture: false)
        }
    }

    func testCancelledGestureStillAcceptsSourceUpdates() throws {
        for visibility in ["visible", "hidden"] {
            let fixture = try LevixelDismissalFixture()
            let runtime = LevixelUniPresenter.shared
            let closed = expectation(description: "Closed after cancellation")
            var events: [NSDictionary] = []
            let gallery = try open(runtime, in: fixture, visibility: visibility, closed: closed) { events.append($0) }
            defer { runtime.eventHandler = nil; runtime.close(options: [:]) { _ in } }
            let viewer = try XCTUnwrap(fixture.presenter.presentedViewController as? LevixelViewerController)
            let pan = LevixelDismissalPan()
            pan.send(.changed, translation: 20, to: viewer)
            pan.send(.cancelled, translation: 20, to: viewer)
            let restored = expectation(description: "Cancelled drag restored")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { restored.fulfill() }
            wait(for: [restored], timeout: 2)
            XCTAssertFalse(viewer.isClosing)
            XCTAssertTrue(try update(runtime, gallery: gallery, change: "replace"))
            XCTAssertNotNil(viewer.anchorView(for: 0))
            XCTAssertFalse(events.contains { $0["type"] as? String == "dismiss" })
            runtime.close(options: [:]) { _ in }
            wait(for: [closed], timeout: 3)
            let restoredSources = visibilityEvents(events).filter { $0["hidden"] as? Bool == false }
            XCTAssertEqual(restoredSources.compactMap { $0["sourceId"] as? String },
                           visibility == "hidden" ? ["original", "replacement"] : [])
        }
    }

    private func checkClosingUpdates(visibility: String, change: String, gesture: Bool) throws {
        let fixture = try LevixelDismissalFixture()
        let runtime = LevixelUniPresenter.shared
        let closed = expectation(description: "Closed \(visibility) \(change)")
        var events: [NSDictionary] = []
        let gallery = try open(runtime, in: fixture, visibility: visibility, closed: closed) { events.append($0) }
        defer { runtime.eventHandler = nil; runtime.close(options: [:]) { _ in } }
        let viewer = try XCTUnwrap(fixture.presenter.presentedViewController as? LevixelViewerController)
        let anchor = try XCTUnwrap(viewer.anchorView(for: 0))
        let frame = anchor.convert(anchor.bounds, to: fixture.window)
        if gesture {
            let pan = LevixelDismissalPan()
            pan.send(.changed, translation: viewer.view.bounds.height * 0.3, to: viewer)
            pan.send(.ended, translation: viewer.view.bounds.height * 0.3, to: viewer)
        } else {
            runtime.close(options: [:]) { _ in }
        }
        XCTAssertTrue(viewer.isClosing)
        XCTAssertFalse(events.contains { $0["type"] as? String == "dismiss" },
                       "Inject the measurement while the return animation is still active")
        let eventCount = events.count
        XCTAssertFalse(try update(runtime, gallery: gallery, change: change))
        XCTAssertTrue(viewer.anchorView(for: 0) === anchor, "Closing must not replace or remove the return anchor")
        XCTAssertEqual(anchor.convert(anchor.bounds, to: fixture.window), frame)
        XCTAssertEqual(events.count, eventCount, "Rejected updates must not transfer source visibility")
        wait(for: [closed], timeout: 3)
        XCTAssertEqual(events.filter { $0["type"] as? String == "dismiss" }.count, 1)
        XCTAssertNil(anchor.window)
        XCTAssertNil(fixture.presenter.presentedViewController)
        let restored = visibilityEvents(events).filter { $0["hidden"] as? Bool == false }
        XCTAssertEqual(restored.compactMap { $0["sourceId"] as? String }, visibility == "hidden" ? ["original"] : [])
        XCTAssertFalse(try update(runtime, gallery: gallery, change: change))
    }

    private func open(_ runtime: LevixelUniPresenter, in fixture: LevixelDismissalFixture,
                      visibility: String, closed: XCTestExpectation,
                      event: @escaping (NSDictionary) -> Void) throws -> String {
        let opened = expectation(description: "Native viewer opened")
        let presented = expectation(description: "UniApp open completed")
        runtime.eventHandler = { value in
            event(value)
            if value["type"] as? String == "opened" { opened.fulfill() }
            if value["type"] as? String == "dismiss" { closed.fulfill() }
        }
        let image = try XCTUnwrap(fixture.source.image?.pngData())
        var response: NSDictionary?
        runtime.open(options: [
            "items": [["id": "photo", "type": "image", "url": "data:image/png;base64,\(image.base64EncodedString())"]],
            "sourceHints": [hint(left: 20)], "sourceIds": ["original"], "sourceVisibility": visibility,
        ], rootView: fixture.presenter.view, viewController: fixture.presenter) { result in
            response = result
            presented.fulfill()
        }
        wait(for: [presented, opened], timeout: 3)
        XCTAssertEqual(response?["ok"] as? Bool, true)
        return try XCTUnwrap((response?["data"] as? NSDictionary)?["galleryId"] as? String)
    }

    private func update(_ runtime: LevixelUniPresenter, gallery: String, change: String) throws -> Bool {
        var response: NSDictionary?
        let hints: [Any] = change == "remove" ? [NSNull()] : [hint(left: 140)]
        let sourceIds: [Any] = change == "remove" ? [NSNull()] : [change == "replace" ? "replacement" : "original"]
        runtime.updateSources(options: [
            "galleryId": gallery, "revision": 1,
            "sourceHints": hints, "sourceIds": sourceIds,
        ]) { response = $0 }
        XCTAssertEqual(response?["ok"] as? Bool, true)
        return try XCTUnwrap((response?["data"] as? NSDictionary)?["updated"] as? Bool)
    }

    private func hint(left: CGFloat) -> [String: Any] {
        ["rect": ["left": left, "top": 80, "width": 80, "height": 80],
         "coordinateSpace": "viewport", "cornerRadius": 12]
    }

    private func visibilityEvents(_ events: [NSDictionary]) -> [NSDictionary] {
        events.filter { $0["type"] as? String == "sourceVisibilityChange" }
            .compactMap { $0["payload"] as? NSDictionary }
    }
}
