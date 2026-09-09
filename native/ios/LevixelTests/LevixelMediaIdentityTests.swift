import UIKit
import XCTest
@testable import Levixel

private final class MutableIdentifiedDataSource: LevixelIdentifiedDataSource {
    var identifiers: [String?] = [nil, "detail"]
    func numberOfItems() -> Int { identifiers.count }
    func item(at index: Int) -> LevixelMediaItem { .image(nil) }
    func itemIdentifier(at index: Int) -> String? { identifiers[index] }
}

final class LevixelMediaIdentityTests: XCTestCase {
    func testCloseDuringOpeningSettlesSessionWithoutGhostOpenedEvent() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        let source = UIImageView(frame: CGRect(x: 20, y: 40, width: 80, height: 80))
        source.image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        presenter.view.addSubview(source)
        var events: [String] = []
        let closed = expectation(description: "Session closed")
        var configuration = LevixelViewerConfiguration()
        configuration.onEvent = { events.append($0.type) }
        configuration.onSession = { session in session.close(animated: false) { closed.fulfill() } }
        let session = source.presentLevixelViewer(dataSource: LevixelArrayDataSource(items: [.image(source.image)]),
            configuration: configuration, from: presenter)
        XCTAssertNotNil(session)
        wait(for: [closed], timeout: 2)
        let settled = expectation(description: "Original opening transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertFalse(events.contains("opened"))
        XCTAssertEqual(events.filter { $0 == "dismiss" }.count, 1)
        XCTAssertNil(session?.sessionId)
        XCTAssertNil(presenter.presentedViewController)
    }

    func testArrayDataSourcePreservesStableItemIdentifiers() {
        let dataSource = LevixelArrayDataSource(
            items: [.image(nil), .image(nil)],
            itemIdentifiers: ["cover", "detail"]
        )

        XCTAssertEqual(dataSource.itemIdentifier(at: 0), "cover")
        XCTAssertEqual(dataSource.itemIdentifier(at: 1), "detail")
    }

    func testMixedIdentitySnapshotRetainsAnchorsAfterSourceMutation() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let source = UIImageView(frame: CGRect(x: 10, y: 10, width: 80, height: 80))
        let identifiedSource = UIImageView(frame: CGRect(x: 110, y: 10, width: 80, height: 80))
        window.addSubview(source)
        window.addSubview(identifiedSource)
        source.registerLevixelSource(galleryId: galleryId, index: 0)
        identifiedSource.registerLevixelSource(galleryId: galleryId, itemIdentifier: "detail")
        defer {
            source.unregisterLevixelSource()
            identifiedSource.unregisterLevixelSource()
            window.isHidden = true
        }
        let dataSource = MutableIdentifiedDataSource()
        let controller = LevixelViewerController(sourceView: source, dataSource: dataSource,
            imageLoader: LevixelURLSessionImageLoader(), galleryId: galleryId)
        dataSource.identifiers = ["replacement"]
        XCTAssertTrue(controller.anchorView(for: 0) === source)
        XCTAssertTrue(controller.anchorView(for: 1) === identifiedSource,
            "A missing ID on another item must not erase this item's stable identity")
    }

    func testPresentingPreservesRegisteredSourceCornerRadius() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        let source = UIImageView(frame: CGRect(x: 20, y: 40, width: 80, height: 80))
        source.image = UIGraphicsImageRenderer(size: source.bounds.size).image { context in
            UIColor.blue.setFill()
            context.fill(source.bounds)
        }
        presenter.view.addSubview(source)
        let galleryId = "test-\(UUID().uuidString)"
        source.registerLevixelSource(galleryId: galleryId, itemIdentifier: "cover", cornerRadius: 18)
        let opened = expectation(description: "Viewer opened")
        let closed = expectation(description: "Viewer closed")
        let configuration = LevixelViewerConfiguration(onEvent: { event in
            if event.type == "opened" { opened.fulfill() }
        })
        let session = source.presentLevixelViewer(dataSource: LevixelArrayDataSource(items: [.image(source.image)], itemIdentifiers: ["cover"]),
            configuration: configuration, from: presenter, galleryId: galleryId)
        wait(for: [opened], timeout: 3)
        XCTAssertEqual(source.levixelConfiguredSourceCornerRadius, 18)
        session?.close(animated: false) { closed.fulfill() }
        wait(for: [closed], timeout: 2)
        source.unregisterLevixelSource()
        XCTAssertNil(source.levixelConfiguredSourceCornerRadius)
    }

    func testLegacyArrayDataSourceResolvesAnIndexAnchor() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let initialSource = UIImageView(frame: CGRect(x: 10, y: 10, width: 80, height: 80))
        let secondSource = UIImageView(frame: CGRect(x: 110, y: 10, width: 80, height: 80))
        window.addSubview(initialSource)
        window.addSubview(secondSource)

        let dataSource = LevixelArrayDataSource(items: [.image(nil), .image(nil)])
        LevixelSourceViewRegistry.shared.register(secondSource, galleryId: galleryId, index: 1)
        let controller = LevixelViewerController(
            sourceView: initialSource,
            dataSource: dataSource,
            imageLoader: LevixelURLSessionImageLoader(),
            initialIndex: 0,
            galleryId: galleryId
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                secondSource,
                galleryId: galleryId,
                index: 1
            )
            window.isHidden = true
        }

        XCTAssertNil(dataSource.itemIdentifier(at: 1))
        XCTAssertTrue(controller.anchorView(for: 1) === secondSource)
    }

    func testStableIdentityDoesNotFallBackToAReusedIndexOrInitialSource() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let reusedInitialSource = UIImageView(
            frame: CGRect(x: 10, y: 10, width: 80, height: 80)
        )
        window.addSubview(reusedInitialSource)

        let dataSource = LevixelArrayDataSource(
            items: [.image(nil), .image(nil)],
            itemIdentifiers: ["removed", "replacement"]
        )
        reusedInitialSource.registerLevixelSource(
            galleryId: galleryId,
            itemIdentifier: "replacement"
        )
        LevixelSourceViewRegistry.shared.register(
            reusedInitialSource,
            galleryId: galleryId,
            index: 0
        )
        let controller = LevixelViewerController(
            sourceView: reusedInitialSource,
            dataSource: dataSource,
            imageLoader: LevixelURLSessionImageLoader(),
            initialIndex: 0,
            galleryId: galleryId
        )
        defer {
            reusedInitialSource.unregisterLevixelSource()
            LevixelSourceViewRegistry.shared.unregister(
                reusedInitialSource,
                galleryId: galleryId,
                index: 0
            )
            window.isHidden = true
        }

        XCTAssertNil(controller.anchorView(for: 0))
    }

    func testIdentifierAndIndexAnchorsUseIndependentRegistryKeys() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false

        let indexAnchor = UIImageView(frame: CGRect(x: 10, y: 10, width: 80, height: 80))
        let identifierAnchor = UIImageView(frame: CGRect(x: 110, y: 10, width: 80, height: 80))
        window.addSubview(indexAnchor)
        window.addSubview(identifierAnchor)

        LevixelSourceViewRegistry.shared.register(indexAnchor, galleryId: galleryId, index: 0)
        LevixelSourceViewRegistry.shared.register(
            identifierAnchor,
            galleryId: galleryId,
            itemIdentifier: "0"
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                indexAnchor,
                galleryId: galleryId,
                index: 0
            )
            LevixelSourceViewRegistry.shared.unregister(
                identifierAnchor,
                galleryId: galleryId,
                itemIdentifier: "0"
            )
            window.isHidden = true
        }

        XCTAssertTrue(
            LevixelSourceViewRegistry.shared.sourceView(for: galleryId, index: 0) === indexAnchor
        )
        XCTAssertTrue(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "0"
            ) === identifierAnchor
        )
    }

    func testViewerSetupRegistersTheClampedItemByStableIdentifier() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let imageView = UIImageView(frame: CGRect(x: 10, y: 10, width: 80, height: 80))
        window.addSubview(imageView)

        let dataSource = LevixelArrayDataSource(
            items: [.image(nil), .image(nil)],
            itemIdentifiers: ["cover", "detail"]
        )
        imageView.setupLevixelViewer(
            dataSource: dataSource,
            initialIndex: 99,
            galleryId: galleryId
        )
        defer {
            imageView.removeLevixelViewerInteraction()
            window.isHidden = true
        }

        XCTAssertTrue(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "detail"
            ) === imageView
        )
        XCTAssertNil(LevixelSourceViewRegistry.shared.sourceView(for: galleryId, index: 1))
    }

    func testRegistryRejectsAVisibleWindowFrameClippedByAnAncestor() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let clippingView = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        clippingView.clipsToBounds = true
        let imageView = UIImageView(frame: CGRect(x: 140, y: 0, width: 80, height: 80))
        window.addSubview(clippingView)
        clippingView.addSubview(imageView)
        LevixelSourceViewRegistry.shared.register(
            imageView,
            galleryId: galleryId,
            itemIdentifier: "clipped"
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                imageView,
                galleryId: galleryId,
                itemIdentifier: "clipped"
            )
            window.isHidden = true
        }

        XCTAssertNil(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "clipped"
            )
        )
    }

    func testSharedElementGeometryUsesTheEffectiveAncestorClip() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let clippingView = UIView(frame: CGRect(x: 20, y: 30, width: 100, height: 100))
        clippingView.clipsToBounds = true
        let imageView = UIImageView(frame: CGRect(x: 60, y: 10, width: 80, height: 80))
        imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 80)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
        }
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        window.addSubview(clippingView)
        clippingView.addSubview(imageView)
        defer { window.isHidden = true }

        let state = try XCTUnwrap(imageView.levixelSharedElementState())
        XCTAssertEqual(
            state.geometry.visibleFrameInWindow,
            CGRect(x: 80, y: 40, width: 40, height: 80)
        )
        XCTAssertEqual(
            state.geometry.contentFrameInVisibleBounds,
            CGRect(x: 0, y: 0, width: 80, height: 80)
        )
        XCTAssertEqual(state.geometry.cornerRadius, 0)
    }

    func testConfiguredSourceCornerRadiusDrivesTheFullSourceTransition() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let imageView = UIImageView(frame: CGRect(x: 20, y: 30, width: 80, height: 60))
        imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 60)).image {
            context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        }
        imageView.contentMode = .scaleToFill
        window.addSubview(imageView)
        imageView.setupLevixelViewer(
            configuration: LevixelViewerConfiguration(sourceCornerRadius: 12)
        )
        defer {
            imageView.removeLevixelViewerInteraction()
            window.isHidden = true
        }

        let state = try XCTUnwrap(imageView.levixelSharedElementState())
        XCTAssertEqual(state.geometry.cornerRadius, 12)

        imageView.removeLevixelViewerInteraction()
        let stateAfterRemoval = try XCTUnwrap(imageView.levixelSharedElementState())
        XCTAssertEqual(stateAfterRemoval.geometry.cornerRadius, 0)
    }

    func testConfiguredSourceCornerRadiusDoesNotRoundInsetAspectFitContent() throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let imageView = UIImageView(frame: CGRect(x: 20, y: 30, width: 80, height: 80))
        imageView.image = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image {
            context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        }
        imageView.contentMode = .scaleAspectFit
        window.addSubview(imageView)
        imageView.setupLevixelViewer(
            configuration: LevixelViewerConfiguration(sourceCornerRadius: 12)
        )
        defer {
            imageView.removeLevixelViewerInteraction()
            window.isHidden = true
        }

        let state = try XCTUnwrap(imageView.levixelSharedElementState())
        XCTAssertEqual(state.geometry.cornerRadius, 0)
    }

    func testRegistryKeepsThePluginHiddenSourceAnchorResolvable() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let imageView = UIImageView(frame: CGRect(x: 20, y: 20, width: 80, height: 80))
        imageView.alpha = 0
        window.addSubview(imageView)
        LevixelSourceViewRegistry.shared.register(
            imageView,
            galleryId: galleryId,
            itemIdentifier: "hidden-by-transition"
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                imageView,
                galleryId: galleryId,
                itemIdentifier: "hidden-by-transition"
            )
            window.isHidden = true
        }

        XCTAssertTrue(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "hidden-by-transition"
            ) === imageView
        )
    }

    func testRegistryKeepsATransparentSourceInsideAVisibleHostResolvable() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let host = UIView(frame: window.bounds)
        host.backgroundColor = .clear
        let imageView = UIImageView(frame: CGRect(x: 20, y: 20, width: 80, height: 80))
        imageView.alpha = 0
        window.addSubview(host)
        host.addSubview(imageView)
        LevixelSourceViewRegistry.shared.register(
            imageView,
            galleryId: galleryId,
            itemIdentifier: "synthetic-anchor"
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                imageView,
                galleryId: galleryId,
                itemIdentifier: "synthetic-anchor"
            )
            window.isHidden = true
        }

        XCTAssertTrue(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "synthetic-anchor"
            ) === imageView
        )
    }

    func testRegistryRejectsATransparentSourceHost() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let host = UIView(frame: window.bounds)
        host.alpha = 0
        let imageView = UIImageView(frame: CGRect(x: 20, y: 20, width: 80, height: 80))
        window.addSubview(host)
        host.addSubview(imageView)
        LevixelSourceViewRegistry.shared.register(
            imageView,
            galleryId: galleryId,
            itemIdentifier: "transparent-host"
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                imageView,
                galleryId: galleryId,
                itemIdentifier: "transparent-host"
            )
            window.isHidden = true
        }

        XCTAssertNil(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "transparent-host"
            )
        )
    }

    func testRegistryRejectsAHiddenAncestor() {
        let galleryId = "test-\(UUID().uuidString)"
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.isHidden = false
        let hiddenContainer = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        hiddenContainer.isHidden = true
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        window.addSubview(hiddenContainer)
        hiddenContainer.addSubview(imageView)
        LevixelSourceViewRegistry.shared.register(
            imageView,
            galleryId: galleryId,
            itemIdentifier: "hidden-ancestor"
        )
        defer {
            LevixelSourceViewRegistry.shared.unregister(
                imageView,
                galleryId: galleryId,
                itemIdentifier: "hidden-ancestor"
            )
            window.isHidden = true
        }

        XCTAssertNil(
            LevixelSourceViewRegistry.shared.sourceView(
                for: galleryId,
                itemIdentifier: "hidden-ancestor"
            )
        )
    }
}
