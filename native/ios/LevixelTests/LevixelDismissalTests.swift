import UIKit
import XCTest
@testable import Levixel

final class LevixelDismissalTests: XCTestCase {
    func testProgrammaticClosePublishesStateBeforeDismissalAndRestoresSource() throws {
        let fixture = try LevixelDismissalFixture()
        let opened = expectation(description: "Opened")
        let closed = expectation(description: "Closed")
        var events: [String] = []
        let configuration = LevixelViewerConfiguration(onEvent: { event in
            events.append(event.type)
            if event.type == "opened" { opened.fulfill() }
        })
        let session = try XCTUnwrap(fixture.source.presentLevixelViewer(
            dataSource: LevixelArrayDataSource(items: [.image(fixture.source.image)]),
            configuration: configuration, from: fixture.presenter))
        defer { session.close(animated: false) }
        wait(for: [opened], timeout: 3)
        XCTAssertFalse(session.isClosing)
        session.close { closed.fulfill() }
        XCTAssertTrue(session.isClosing)
        XCTAssertFalse(events.contains("dismiss"), "Closing must be observable before the final event")
        wait(for: [closed], timeout: 3)
        XCTAssertTrue(session.isClosing, "An invalidated session must not accept new source state")
        XCTAssertNil(session.sessionId)
        XCTAssertEqual(fixture.source.alpha, 0.6)
        XCTAssertEqual(events.filter { $0 == "dismiss" }.count, 1)
    }

    func testGestureClosePublishesStateOnlyAfterCommit() throws {
        let fixture = try LevixelDismissalFixture()
        let opened = expectation(description: "Opened")
        let closed = expectation(description: "Closed")
        var dismissCount = 0
        let configuration = LevixelViewerConfiguration(onEvent: { event in
            if event.type == "opened" { opened.fulfill() }
            if event.type == "dismiss" { dismissCount += 1; closed.fulfill() }
        })
        let session = try XCTUnwrap(fixture.source.presentLevixelViewer(
            dataSource: LevixelArrayDataSource(items: [.image(fixture.source.image)]),
            configuration: configuration, from: fixture.presenter))
        defer { session.close(animated: false) }
        wait(for: [opened], timeout: 3)
        let viewer = try XCTUnwrap(fixture.presenter.presentedViewController as? LevixelViewerController)
        let pan = LevixelDismissalPan()
        pan.send(.changed, translation: 20, to: viewer)
        XCTAssertFalse(session.isClosing, "A drag can still be cancelled")
        pan.send(.cancelled, translation: 20, to: viewer)
        let restored = expectation(description: "Cancelled drag restored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { restored.fulfill() }
        wait(for: [restored], timeout: 2)
        XCTAssertFalse(session.isClosing)
        XCTAssertEqual(dismissCount, 0)
        pan.send(.changed, translation: viewer.view.bounds.height * 0.3, to: viewer)
        pan.send(.ended, translation: viewer.view.bounds.height * 0.3, to: viewer)
        XCTAssertTrue(session.isClosing, "Native gestures must close the same session gate as close()")
        XCTAssertEqual(dismissCount, 0)
        wait(for: [closed], timeout: 3)
        XCTAssertTrue(session.isClosing)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(fixture.source.alpha, 0.6)
    }
}

// These tests drive the actual UIKit gesture handler and transition lifecycle.
// Gesture recognition and frame continuity still require device acceptance.
final class LevixelDismissalPan: UIPanGestureRecognizer {
    private var sampleState: UIGestureRecognizer.State = .possible
    private var sampleTranslation = CGPoint.zero
    private var sampleLocation = CGPoint.zero

    override var state: UIGestureRecognizer.State {
        get { sampleState }
        set { sampleState = newValue }
    }

    override func translation(in view: UIView?) -> CGPoint { sampleTranslation }
    override func velocity(in view: UIView?) -> CGPoint { CGPoint(x: 0, y: 200) }
    override func location(in view: UIView?) -> CGPoint { sampleLocation }

    func send(_ state: UIGestureRecognizer.State, translation: CGFloat, to viewer: LevixelViewerController) {
        sampleState = state
        sampleTranslation = CGPoint(x: 0, y: translation)
        sampleLocation = viewer.view.convert(CGPoint(x: viewer.view.bounds.midX, y: viewer.view.bounds.midY),
                                            to: viewer.view.window)
        _ = viewer.perform(NSSelectorFromString("handlePan:"), with: self)
    }
}

final class LevixelDismissalFixture {
    let window: UIWindow
    let presenter = UIViewController()
    let source = UIImageView(frame: CGRect(x: 20, y: 80, width: 80, height: 80))
    private let previousKeyWindow: UIWindow?

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        source.image = UIGraphicsImageRenderer(size: source.bounds.size).image { context in
            UIColor.blue.setFill()
            context.fill(source.bounds)
        }
        source.alpha = 0.6
        presenter.view.addSubview(source)
    }

    deinit {
        presenter.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        previousKeyWindow?.makeKeyAndVisible()
    }
}
