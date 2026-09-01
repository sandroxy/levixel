import UIKit
import XCTest
@testable import Levixel

final class LevixelMediaIdentityTests: XCTestCase {
    func testArrayDataSourcePreservesStableItemIdentifiers() {
        let dataSource = LevixelArrayDataSource(
            items: [.image(nil), .image(nil)],
            itemIdentifiers: ["cover", "detail"]
        )

        XCTAssertEqual(dataSource.itemIdentifier(at: 0), "cover")
        XCTAssertEqual(dataSource.itemIdentifier(at: 1), "detail")
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
