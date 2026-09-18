import XCTest
import UIKit
@testable import Levixel

@MainActor
final class LevixelSourceSelectionTests: XCTestCase {
    func testEverySourceCanBeSelectedWithoutHidingItsSiblings() {
        for count in [1, 2, 3, 5, 10] {
            let fixture = Fixture()
            defer { fixture.close() }
            let sources = (0..<count).map { fixture.source("source-\($0)", radius: CGFloat($0)) }
            for selected in 0..<count {
                let selection = fixture.selection("source-\(selected)")
                XCTAssertTrue(selection.imageView === sources[selected].image)
                XCTAssertEqual(selection.cornerRadius, CGFloat(selected))
                let lease = LevixelSourceViewRegistry.shared.hide(selection)
                selection.allowFallback()
                for i in (0..<count).reversed() {
                    sources[i].registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: CGFloat(i))
                    XCTAssertTrue(selection.imageView === sources[selected].image)
                    XCTAssertEqual(sources[i].view.alpha, i == selected ? 0 : sources[i].originalAlpha)
                }
                lease.close()
                lease.close()
                XCTAssertEqual(sources[selected].view.alpha, sources[selected].originalAlpha)
            }
        }
    }

    func testSelectionSurvivesAnImageGapAndUsesTheReplacementImage() {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = fixture.source("first")
        let selected = fixture.source("selected", radius: 12)
        let selection = fixture.selection("selected")
        let lease = LevixelSourceViewRegistry.shared.hide(selection)
        defer { lease.close() }
        selection.allowFallback()
        selected.image.removeFromSuperview()
        XCTAssertNil(selection.imageView)
        XCTAssertEqual(selected.view.alpha, 0)
        XCTAssertEqual(first.view.alpha, first.originalAlpha)
        let replacement = fixture.image(in: selected.view)
        XCTAssertTrue(selection.imageView === replacement)
        XCTAssertEqual(selection.cornerRadius, 12)
        XCTAssertEqual(selected.view.alpha, 0)
    }

    func testMissingClickedSourceFadesBeforeAllowingReturnFallback() {
        let fixture = Fixture()
        defer { fixture.close() }
        let other = fixture.source("other")
        let selection = fixture.selection("gone")
        let lease = LevixelSourceViewRegistry.shared.hide(selection)
        defer { lease.close() }
        XCTAssertNil(selection.imageView)
        XCTAssertEqual(other.view.alpha, other.originalAlpha)
        selection.allowFallback()
        XCTAssertTrue(selection.imageView === other.image)
        XCTAssertEqual(other.view.alpha, 0)
    }

    func testRebindingRestoresTheOldIdentityAndKeepsFallbackStable() {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = fixture.source("first")
        let selected = fixture.source("selected")
        let selection = fixture.selection("selected")
        let lease = LevixelSourceViewRegistry.shared.hide(selection)
        defer { lease.close() }
        selection.allowFallback()
        selected.registration.register(galleryId: fixture.galleryId, itemIdentifier: "other", cornerRadius: 0)
        XCTAssertTrue(selection.imageView === first.image)
        XCTAssertEqual(selected.view.alpha, selected.originalAlpha)
        XCTAssertEqual(first.view.alpha, 0)
        selected.registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 0)
        XCTAssertTrue(selection.imageView === first.image)
        first.registration.unregister()
        XCTAssertTrue(selection.imageView === selected.image)
        XCTAssertEqual(first.view.alpha, first.originalAlpha)
    }

    func testRecyclingBetweenHiddenIdentitiesDoesNotSaveZeroAlpha() {
        let fixture = Fixture()
        defer { fixture.close() }
        let source = fixture.source("selected")
        let first = LevixelSourceViewRegistry.shared.hide(fixture.selection(nil))
        let second = LevixelSourceViewRegistry.shared.hide(fixture.selection(nil, itemId: "other"))
        source.registration.register(galleryId: fixture.galleryId, itemIdentifier: "other", cornerRadius: 0)
        XCTAssertEqual(source.view.alpha, 0)
        first.close()
        XCTAssertEqual(source.view.alpha, 0)
        second.close()
        XCTAssertEqual(source.view.alpha, source.originalAlpha)
    }

    func testOverlappingLeasesRestoreOnlyAfterTheLastOwnerCloses() {
        let fixture = Fixture()
        defer { fixture.close() }
        let source = fixture.source("selected")
        let first = LevixelSourceViewRegistry.shared.hide(fixture.selection("selected"))
        let second = LevixelSourceViewRegistry.shared.hide(fixture.selection("selected"))
        first.close()
        XCTAssertEqual(source.view.alpha, 0)
        second.close()
        XCTAssertEqual(source.view.alpha, source.originalAlpha)
    }

    func testReregisteringHiddenSourceReassertsAlphaWithoutAddingOwners() {
        let fixture = Fixture()
        defer { fixture.close() }
        let source = fixture.source("selected", alpha: 0.8)
        let selection = fixture.selection("selected")
        let first = LevixelSourceViewRegistry.shared.hide(selection)
        let second = LevixelSourceViewRegistry.shared.hide(selection)
        defer { first.close(); second.close() }

        // RN may reapply the source's style when its corner radius changes.
        for radius in [CGFloat(16), 24, 16] {
            source.view.alpha = source.originalAlpha
            source.registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: radius)
            XCTAssertEqual(source.view.alpha, 0)
            XCTAssertTrue(selection.imageView === source.image)
            XCTAssertEqual(selection.cornerRadius, radius)
        }

        first.close()
        XCTAssertEqual(source.view.alpha, 0)
        second.close()
        XCTAssertEqual(source.view.alpha, source.originalAlpha)
    }

    func testProgrammaticSelectionRejectsClippedAndHostHiddenSources() {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = fixture.source("first")
        let second = fixture.source("second")
        first.view.frame.origin.x = 600
        let selection = fixture.selection(nil)
        XCTAssertTrue(selection.imageView === second.image)
        second.view.alpha = 0
        XCTAssertNil(selection.imageView)
        first.view.frame.origin.x = 20
        XCTAssertTrue(selection.imageView === first.image)
        fixture.host.alpha = 0
        XCTAssertNil(selection.imageView)
    }

    func testSourceSelectionIsScopedToThePresentingWindow() {
        let first = Fixture()
        let second = Fixture(galleryId: first.galleryId)
        defer { first.close(); second.close() }
        _ = first.source("first")
        let expected = second.source("second")
        XCTAssertTrue(second.selection(nil).imageView === expected.image)
        XCTAssertNil(second.selection("first").imageView)
    }

    func testRepeatedNativeRegistrationKeepsTheSameSelection() {
        let fixture = Fixture()
        defer { fixture.close() }
        let first = fixture.image(in: fixture.host)
        let second = fixture.image(in: fixture.host)
        first.registerLevixelSource(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 7)
        second.registerLevixelSource(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 9)
        defer { first.unregisterLevixelSource(); second.unregisterLevixelSource() }
        let selection = fixture.selection(nil)
        XCTAssertTrue(selection.imageView === first)
        first.registerLevixelSource(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 12)
        XCTAssertTrue(selection.imageView === first)
        XCTAssertEqual(selection.cornerRadius, 12)
    }

    func testIdentifiedNativeViewerWithoutGalleryKeepsItsInitialSource() {
        let fixture = Fixture()
        defer { fixture.close() }
        let source = fixture.image(in: fixture.host)
        let viewer = LevixelViewerController(sourceView: source,
            dataSource: LevixelArrayDataSource(items: [.image(source.image)], itemIdentifiers: ["media"]),
            imageLoader: LevixelURLSessionImageLoader())
        XCTAssertTrue(viewer.anchorView(for: 0) === source)
    }

    func testSelectionAndRestorationForEverySourceMutationCombination() {
        for count in [1, 2, 3, 5, 10] {
            for clicked in 0..<count {
                for changed in 0..<count {
                    for operation in ["refresh", "image-gap", "remove", "rebind", "clip", "host-hide"] {
                        verifyMutationCombination(count: count, clicked: clicked, changed: changed, operation: operation)
                    }
                }
            }
        }
    }

    private func verifyMutationCombination(count: Int, clicked: Int, changed: Int, operation: String) {
        let context = "count=\(count), clicked=\(clicked), changed=\(changed), \(operation)"
        let fixture = Fixture()
        defer { fixture.close() }
        let sources = (0..<count).map { fixture.source("source-\($0)", radius: CGFloat($0), alpha: 0.25 + CGFloat($0) * 0.05) }
        var images = sources.map(\.image)
        let selection = fixture.selection("source-\(clicked)")
        var lease = LevixelSourceViewRegistry.shared.hide(selection)
        defer { lease.close(); lease.close() }
        selection.allowFallback()
        XCTAssertTrue(selection.imageView === images[clicked], context)
        // Updating surviving registrations must not change their fallback order.
        for i in (0..<count).reversed() {
            sources[i].registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: CGFloat(i))
        }
        let target = sources[changed]
        var expected: Int? = clicked
        switch operation {
        case "refresh":
            target.registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 24)
        case "image-gap":
            images[changed].removeFromSuperview()
            XCTAssertTrue(selection.imageView === (clicked == changed ? nil : images[clicked]), context)
            assertSourceAlphas(sources, hidden: clicked, context: context)
            images[changed] = fixture.image(in: target.view)
            target.registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 12)
        case "remove", "rebind", "clip", "host-hide":
            if operation == "remove" { target.registration.unregister() }
            if operation == "rebind" { target.registration.register(galleryId: fixture.galleryId, itemIdentifier: "other-media", cornerRadius: 0) }
            if operation == "clip" { target.view.frame.origin.x = 600 }
            if operation == "host-hide" { target.view.isHidden = true }
            if clicked == changed { expected = (0..<count).first { $0 != changed } }
        default:
            XCTFail("Unknown mutation: \(operation)")
        }
        XCTAssertTrue(selection.imageView === expected.map { images[$0] }, context)
        assertSourceAlphas(sources, hidden: expected, context: context)
        target.view.frame.origin.x = 20
        target.view.isHidden = false
        target.registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 12)
        if expected == nil { expected = changed }
        XCTAssertTrue(selection.imageView === expected.map { images[$0] }, context + " after restoration")
        assertSourceAlphas(sources, hidden: expected, context: context)
        lease.close()
        assertSourceAlphas(sources, hidden: nil, context: context + " after paging away")
        lease = LevixelSourceViewRegistry.shared.hide(selection)
        XCTAssertTrue(selection.imageView === expected.map { images[$0] }, context + " after paging back")
        assertSourceAlphas(sources, hidden: expected, context: context)
        sources.forEach { $0.registration.unregister() }
        XCTAssertNil(selection.imageView, context + " after removing all sources")
        assertSourceAlphas(sources, hidden: nil, context: context)
    }

    func testViewerSnapshotPagingAndClosingForEveryDemoOperation() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for clicked in 0..<3 {
            for operation in ["none", "prepend", "reorder", "replace-images", "refresh-cover", "remove-thumbnail", "remove-sources"] {
                let context = "source=\(clicked), \(operation)"
                let fixture = Fixture(scene: scene)
                defer { fixture.close() }
                let presenter = try XCTUnwrap(fixture.presenter)
                let alphas: [CGFloat] = [0.8, 0.6, 1]
                let sources = (0..<3).map { fixture.source("source-\($0)", radius: CGFloat($0 * 8), alpha: alphas[$0]) }
                for i in sources.indices { sources[i].view.frame.origin = CGPoint(x: CGFloat(20 + i * 100), y: 100) }
                var images = sources.map(\.image)
                let dataSource = MutableSourceSelectionDataSource(image: try XCTUnwrap(images[0].image))
                var events: [LevixelViewerEvent] = []
                let opened = expectation(description: context + " opened")
                let closed = expectation(description: context + " closed")
                let configuration = LevixelViewerConfiguration(onEvent: { event in
                    events.append(event)
                    if event.type == "opened" { opened.fulfill() }
                })
                let session = try XCTUnwrap(LevixelViewerSession.present(dataSource: dataSource,
                    configuration: configuration, from: presenter, galleryId: fixture.galleryId,
                    sourceIdentifier: "source-\(clicked)"))
                defer { session.close(animated: false) }
                wait(for: [opened], timeout: 3)
                let viewer = try XCTUnwrap(presenter.presentedViewController as? LevixelViewerController)
                let pager = try XCTUnwrap(firstCollectionView(in: viewer.view))
                assertSourceAlphas(sources, hidden: clicked, context: context)
                var expected: Int? = clicked
                switch operation {
                case "prepend": dataSource.identifiers.insert("history", at: 0)
                case "reorder": dataSource.identifiers.reverse()
                case "replace-images":
                    for i in sources.indices {
                        images[i].removeFromSuperview()
                        images[i] = fixture.image(in: sources[i].view)
                        sources[i].registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: CGFloat(i * 8))
                    }
                case "refresh-cover":
                    sources[0].registration.register(galleryId: fixture.galleryId, itemIdentifier: "media", cornerRadius: 24)
                case "remove-thumbnail":
                    sources[1].registration.unregister()
                    sources[1].view.removeFromSuperview()
                    if clicked == 1 { expected = 0 }
                case "remove-sources":
                    sources.forEach { $0.registration.unregister(); $0.view.removeFromSuperview() }
                    expected = nil
                case "none": break
                default: XCTFail("Unknown operation: \(operation)")
                }
                XCTAssertTrue(viewer.anchorView(for: 0) === expected.map { images[$0] }, context)
                assertSourceAlphas(sources, hidden: expected, context: context)
                XCTAssertEqual(pager.numberOfItems(inSection: 0), 2, context)
                // Drive UIKit's paging callback with its real collection view;
                // gesture recognition and visual smoothness remain device checks.
                for index in [1, 0] {
                    pager.scrollToItem(at: IndexPath(item: index, section: 0), at: .centeredHorizontally, animated: false)
                    pager.layoutIfNeeded()
                    viewer.scrollViewDidEndScrollingAnimation(pager)
                    assertSourceAlphas(sources, hidden: index == 0 ? expected : nil, context: context + " page \(index)")
                }
                session.close(animated: clicked == 1) { closed.fulfill() }
                wait(for: [closed], timeout: 3)
                assertSourceAlphas(sources, hidden: nil, context: context + " after closing")
                XCTAssertEqual(events.filter { $0.type == "indexChange" }.map { $0.context.itemId }, ["media", "next", "media"], context)
                XCTAssertEqual(events.filter { $0.type == "opened" }.count, 1, context)
                XCTAssertEqual(events.filter { $0.type == "dismiss" }.count, 1, context)
                XCTAssertNil(presenter.presentedViewController, context)
                XCTAssertNil(session.sessionId, context)
            }
        }
    }

    private func firstCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for child in view.subviews {
            if let collection = firstCollectionView(in: child) { return collection }
        }
        return nil
    }

    private func assertSourceAlphas(_ sources: [Fixture.Source], hidden: Int?, context: String) {
        for i in sources.indices {
            XCTAssertEqual(sources[i].view.alpha, i == hidden ? 0 : sources[i].originalAlpha, context + ", opacity \(i)")
        }
    }
}

@MainActor
private final class Fixture {
    struct Source {
        let view: UIView
        let image: UIImageView
        let registration: LevixelSourceRegistration
        let originalAlpha: CGFloat
    }

    let galleryId: String
    let window: UIWindow
    let host: UIView
    let presenter: UIViewController?
    private weak var previousKeyWindow: UIWindow?
    private var registrations: [LevixelSourceRegistration] = []

    init(galleryId: String = UUID().uuidString, scene: UIWindowScene? = nil) {
        self.galleryId = galleryId
        if let scene {
            previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
            window = UIWindow(windowScene: scene)
            let controller = UIViewController()
            presenter = controller
            host = controller.view
            window.rootViewController = controller
            window.makeKeyAndVisible()
        } else {
            presenter = nil
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
            host = UIView(frame: window.bounds)
            window.isHidden = false
            window.addSubview(host)
        }
    }

    func source(_ id: String, radius: CGFloat = 0, alpha: CGFloat = 0.6) -> Source {
        let view = UIView(frame: CGRect(x: 20, y: 20, width: 80, height: 80))
        view.alpha = alpha
        let originalAlpha = view.alpha
        host.addSubview(view)
        let image = image(in: view)
        let registration = LevixelSourceRegistration(view: view, sourceIdentifier: id, imageViewProvider: { owner in
            owner.subviews.reversed().compactMap { $0 as? UIImageView }.first { !$0.isHidden && $0.image != nil }
        })
        registration.register(galleryId: galleryId, itemIdentifier: "media", cornerRadius: radius)
        registrations.append(registration)
        return Source(view: view, image: image, registration: registration, originalAlpha: originalAlpha)
    }

    func image(in view: UIView) -> UIImageView {
        let image = UIImageView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        image.image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        view.addSubview(image)
        return image
    }

    func selection(_ sourceId: String?, itemId: String = "media") -> LevixelSourceViewRegistry.Selection {
        LevixelSourceViewRegistry.shared.selection(galleryId: galleryId, key: .itemIdentifier(itemId),
            window: window, sourceIdentifier: sourceId)
    }

    func close() {
        registrations.forEach { $0.unregister() }
        registrations.removeAll()
        window.isHidden = true
        previousKeyWindow?.makeKeyAndVisible()
    }
}

private final class MutableSourceSelectionDataSource: LevixelIdentifiedDataSource {
    var identifiers = ["media", "next"]
    private let image: UIImage
    init(image: UIImage) { self.image = image }
    func numberOfItems() -> Int { identifiers.count }
    func item(at index: Int) -> LevixelMediaItem { .image(image) }
    func itemIdentifier(at index: Int) -> String? { identifiers[index] }
}
