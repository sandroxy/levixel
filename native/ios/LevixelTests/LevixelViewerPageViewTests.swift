import XCTest
import UIKit
@testable import Levixel

final class LevixelViewerPageViewTests: XCTestCase {
    func testWideCoastPerformsInitialFitAfterBoundsBecomeValid() {
        let preview = makeImage(size: CGSize(width: 600, height: 400))
        let loader = DeferredImageLoader()
        let pageView = makePageView(frame: .zero, preview: preview, loader: loader)

        pageView.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        pageView.setNeedsLayout()
        pageView.layoutIfNeeded()

        let scrollView = requireImageScrollView(in: pageView)
        XCTAssertEqual(scrollView.minimumZoomScale, 0.69, accuracy: 0.0001)
        XCTAssertEqual(scrollView.zoomScale, scrollView.minimumZoomScale, accuracy: 0.0001)
        XCTAssertTrue(pageView.canPageHorizontally)
    }

    func testInitialFitIsConsumedOnlyOnce() {
        let preview = makeImage(size: CGSize(width: 600, height: 400))
        let pageView = makePageView(
            frame: CGRect(x: 0, y: 0, width: 414, height: 896),
            preview: preview,
            loader: DeferredImageLoader()
        )
        let scrollView = requireImageScrollView(in: pageView)
        let userZoomScale = scrollView.minimumZoomScale * 2

        scrollView.setZoomScale(userZoomScale, animated: false)
        pageView.setNeedsLayout()
        pageView.layoutIfNeeded()

        XCTAssertEqual(scrollView.zoomScale, userZoomScale, accuracy: 0.0001)
        XCTAssertFalse(pageView.canPageHorizontally)
    }

    func testOpenTransitionPreviewHandsOffToTheZoomableImageLayer() {
        let preview = makeImage(size: CGSize(width: 600, height: 400))
        let pageView = makePageView(
            frame: CGRect(x: 0, y: 0, width: 414, height: 896),
            preview: preview,
            loader: DeferredImageLoader()
        )

        XCTAssertEqual(visibleImageViews(in: pageView).count, 2)

        pageView.completeOpenTransitionPreviewHandoff()
        pageView.completeOpenTransitionPreviewHandoff()

        XCTAssertEqual(visibleImageViews(in: pageView).count, 1)
        XCTAssertTrue(pageView.sharedElementView?.superview is UIScrollView)
    }

    func testPreviewIsCopiedBeforeAnEmptyZoomLayerIsRevealed() {
        let preview = makeImage(size: CGSize(width: 600, height: 400))
        let pageView = makePageView(
            frame: CGRect(x: 0, y: 0, width: 414, height: 896),
            preview: nil,
            sourcePreview: preview,
            loader: DeferredImageLoader()
        )

        XCTAssertEqual(visibleImageViews(in: pageView).count, 1)

        pageView.completeOpenTransitionPreviewHandoff()

        XCTAssertEqual(visibleImageViews(in: pageView).count, 1)
        XCTAssertTrue(pageView.sharedElementView?.superview is UIScrollView)
        XCTAssertTrue(pageView.sharedElementView?.image === preview)
        XCTAssertTrue(pageView.canPageHorizontally)
    }

    func testLateThumbnailHandsOffDirectlyToTheZoomableLayer() {
        let thumbnail = makeImage(size: CGSize(width: 600, height: 400))
        let loader = DeferredImageLoader()
        let pageView = LevixelViewerPageView(frame: CGRect(x: 0, y: 0, width: 414, height: 896))
        pageView.configure(
            index: 0,
            item: .imageURL(
                URL(string: "https://example.com/\(UUID().uuidString)-full.jpg")!,
                thumbnailURL: URL(string: "https://example.com/\(UUID().uuidString)-thumb.jpg")!,
                placeholder: nil
            ),
            imageLoader: loader,
            mediaContentMode: .scaleAspectFit,
            sourcePreviewImage: nil
        )
        pageView.layoutIfNeeded()
        pageView.completeOpenTransitionPreviewHandoff()

        XCTAssertTrue(visibleImageViews(in: pageView).isEmpty)

        loader.completeRequest(at: 0, with: thumbnail)
        drainMainQueue()

        XCTAssertEqual(visibleImageViews(in: pageView).count, 1)
        XCTAssertTrue(pageView.sharedElementView?.superview is UIScrollView)
        XCTAssertTrue(pageView.sharedElementView?.image === thumbnail)
        XCTAssertTrue(pageView.canPageHorizontally)
    }

    func testFullImageHandoffPreservesUserRelativeZoomAndCenter() {
        let preview = makeImage(size: CGSize(width: 600, height: 400))
        let fullImage = makeImage(size: CGSize(width: 2400, height: 1600))
        let loader = DeferredImageLoader()
        let pageView = makePageView(
            frame: CGRect(x: 0, y: 0, width: 414, height: 896),
            preview: preview,
            loader: loader
        )
        pageView.completeOpenTransitionPreviewHandoff()

        let scrollView = requireImageScrollView(in: pageView)
        scrollView.setZoomScale(scrollView.minimumZoomScale * 2, animated: false)
        scrollView.contentOffset = CGPoint(x: 280, y: 0)
        let stateBefore = requireZoomedState(from: scrollView)

        loader.completeFirstRequest(with: fullImage)
        drainMainQueue()

        let stateAfter = requireZoomedState(from: scrollView)
        XCTAssertEqual(stateAfter.relativeZoomScale, stateBefore.relativeZoomScale, accuracy: 0.0001)
        XCTAssertEqual(stateAfter.normalizedCenter.x, stateBefore.normalizedCenter.x, accuracy: 0.0001)
        XCTAssertEqual(stateAfter.normalizedCenter.y, stateBefore.normalizedCenter.y, accuracy: 0.0001)
        XCTAssertEqual(visibleImageViews(in: pageView).count, 1)
        XCTAssertFalse(pageView.canPageHorizontally)
    }

    func testFullImageHandoffKeepsAnUntouchedPageAtFit() {
        let preview = makeImage(size: CGSize(width: 600, height: 400))
        let fullImage = makeImage(size: CGSize(width: 2400, height: 1600))
        let loader = DeferredImageLoader()
        let pageView = makePageView(
            frame: CGRect(x: 0, y: 0, width: 414, height: 896),
            preview: preview,
            loader: loader
        )
        pageView.completeOpenTransitionPreviewHandoff()

        loader.completeFirstRequest(with: fullImage)
        drainMainQueue()

        let scrollView = requireImageScrollView(in: pageView)
        XCTAssertEqual(scrollView.minimumZoomScale, 0.1725, accuracy: 0.0001)
        XCTAssertEqual(scrollView.zoomScale, scrollView.minimumZoomScale, accuracy: 0.0001)
        XCTAssertEqual(scrollView.contentOffset, .zero)
        XCTAssertTrue(pageView.canPageHorizontally)
    }

    func testLateCallbackFromAReusedCellCannotRestoreTheOldImage() {
        let oldPreview = makeImage(size: CGSize(width: 600, height: 400))
        let oldFullImage = makeImage(size: CGSize(width: 2400, height: 1600))
        let newPreview = makeImage(size: CGSize(width: 400, height: 600))
        let oldLoader = DeferredImageLoader()
        let pageView = makePageView(
            frame: CGRect(x: 0, y: 0, width: 414, height: 896),
            preview: oldPreview,
            loader: oldLoader
        )

        pageView.prepareForReuse()
        pageView.configure(
            index: 1,
            item: .imageURL(
                URL(string: "https://example.com/\(UUID().uuidString)-new.jpg")!,
                placeholder: newPreview
            ),
            imageLoader: DeferredImageLoader(),
            mediaContentMode: .scaleAspectFit,
            sourcePreviewImage: newPreview
        )
        pageView.layoutIfNeeded()
        pageView.completeOpenTransitionPreviewHandoff()

        oldLoader.completeFirstRequest(with: oldFullImage)
        drainMainQueue()

        XCTAssertTrue(pageView.sharedElementView?.image === newPreview)
        XCTAssertEqual(visibleImageViews(in: pageView).count, 1)
    }

    func testWeakTargetImageLoaderCompletesAndReleasesItsRequestView() {
        let loader = WeakTargetImageLoader()
        let page = LevixelViewerPageView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let observer = MediaStateObserver()
        page.delegate = observer
        autoreleasepool {
            page.configure(index: 0, item: .imageURL(URL(string: "https://example.com/\(UUID().uuidString).jpg")!, placeholder: nil),
                imageLoader: loader, mediaContentMode: .scaleAspectFit)
        }
        XCTAssertNotNil(loader.target, "The page must retain the temporary target until loading completes")
        page.completeOpenTransitionPreviewHandoff()
        let image = makeImage(size: CGSize(width: 120, height: 80))
        autoreleasepool { loader.complete(with: image) }
        drainMainQueue()
        XCTAssertEqual(observer.states, [true])
        XCTAssertTrue(page.sharedElementView?.image === image)
        XCTAssertNil(loader.target, "Completed requests must not retain their temporary views")
    }

    func testPageReuseReleasesAnUnfinishedWeakTargetImageRequest() {
        let loader = WeakTargetImageLoader()
        let page = LevixelViewerPageView(frame: .zero)
        autoreleasepool {
            page.configure(index: 0, item: .imageURL(URL(string: "https://example.com/\(UUID().uuidString).jpg")!, placeholder: nil),
                imageLoader: loader, mediaContentMode: .scaleAspectFit)
        }
        XCTAssertNotNil(loader.target)
        page.prepareForReuse()
        XCTAssertNil(loader.target, "An obsolete request must not keep its target alive")
    }

    func testFailedFullImageWithPlaceholderShowsRetryAndCanRecover() {
        let loader = DeferredImageLoader()
        let page = makePageView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
            preview: makeImage(size: CGSize(width: 60, height: 40)), loader: loader)
        let observer = MediaStateObserver()
        page.delegate = observer
        page.completeOpenTransitionPreviewHandoff()
        loader.completeFirstRequest(with: nil)
        drainMainQueue()
        XCTAssertEqual(observer.states, [false], "A placeholder must not count as full media load success")
        XCTAssertTrue(page.retry())
        XCTAssertFalse(page.retry(), "A retry already in progress must not create another request")
        loader.completeFirstRequest(with: makeImage(size: CGSize(width: 120, height: 80)))
        drainMainQueue()
        XCTAssertEqual(observer.states, [false, true])
        XCTAssertFalse(page.retry())
    }

    func testFailureFromReusedPageCannotCreateRetryForAnotherItem() {
        let loader = DeferredImageLoader()
        let page = makePageView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), preview: nil, loader: loader)
        let observer = MediaStateObserver()
        page.delegate = observer
        page.prepareForReuse()
        loader.completeFirstRequest(with: nil)
        drainMainQueue()
        XCTAssertTrue(observer.states.isEmpty)
        XCTAssertFalse(page.retry())
    }

    func testActionDrawerContainsAllGroupsWithinSmallViewport() {
        let actions = (0..<30).map { LevixelAction(id: "custom-\($0)", label: "Custom action \($0)", group: "group-\($0 / 6)", disabled: $0 == 0) }
        let drawer = LevixelActionSheetView(actions: actions, imageLoader: DeferredImageLoader(), select: { _ in }, cancel: {})
        drawer.frame = CGRect(x: 0, y: 0, width: 320, height: 360)
        drawer.layoutIfNeeded()
        let buttons = descendants(of: drawer).compactMap { $0 as? UIButton }.filter { $0.accessibilityIdentifier?.hasPrefix("levixel-action-") == true }
        XCTAssertEqual(buttons.count, 30)
        XCTAssertFalse(buttons[0].isEnabled)
        let sheet = drawer.subviews.compactMap { $0 as? UIScrollView }.first!
        XCTAssertLessThanOrEqual(sheet.frame.height, 360)
        XCTAssertGreaterThan(sheet.contentSize.height, sheet.frame.height)
        XCTAssertGreaterThanOrEqual(buttons[1].bounds.height, 64)
    }

    func testActionSheetFollowsLargerSystemTextWithoutClipping() throws {
        try verifyActionSheetTextScaling(layout: .grid)
    }

    func testActionListFollowsLargerSystemTextWithoutClipping() throws {
        try verifyActionSheetTextScaling(layout: .list)
    }

    private func verifyActionSheetTextScaling(layout: LevixelActionLayout) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let parent = UIViewController()
        let child = UIViewController()
        let actions = (0..<12).map { LevixelAction(id: "custom-\($0)", label: "A long action description", icon: URL(string: "https://example.com/icon.png"), group: "group-\($0 / 3)") }
        let drawer = LevixelActionSheetView(actions: actions, imageLoader: DeferredImageLoader(), layout: layout, listIcons: false, select: { _ in }, cancel: {})
        child.view = drawer
        parent.addChild(child)
        parent.view.addSubview(drawer)
        child.didMove(toParent: parent)
        parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .large), forChild: child)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        drawer.frame = CGRect(x: 0, y: 0, width: 320, height: 360)
        drawer.layoutIfNeeded()
        let normalHeight = drawer.preferredHeight
        let button = try XCTUnwrap(descendants(of: drawer).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "levixel-action-custom-0" })
        let label = try XCTUnwrap(button.subviews.compactMap { $0 as? UILabel }.first)
        let baseSize: CGFloat = layout == .grid ? 12 : 16
        XCTAssertEqual(label.font.pointSize, baseSize, accuracy: 0.1)

        parent.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge), forChild: child)
        parent.view.setNeedsLayout()
        parent.view.layoutIfNeeded()
        drainMainQueue()
        drawer.layoutIfNeeded()
        XCTAssertEqual(drawer.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
        XCTAssertGreaterThan(label.font.pointSize, baseSize)
        XCTAssertGreaterThan(drawer.preferredHeight, normalHeight)
        XCTAssertGreaterThanOrEqual(label.bounds.height + 1, label.font.lineHeight * 2)
        XCTAssertGreaterThan(drawer.scrollView.contentSize.height, drawer.scrollView.bounds.height)
        let cancel = try XCTUnwrap(drawer.subviews.compactMap { $0 as? UIButton }.first)
        XCTAssertGreaterThanOrEqual(cancel.frame.minY, drawer.scrollView.frame.maxY)
        XCTAssertLessThanOrEqual(cancel.frame.maxY, drawer.bounds.height)
    }

    func testExplicitLayoutAndOptionalListIcons() throws {
        let loader = DeferredImageLoader()
        let actions = (0..<10).map { LevixelAction(id: "custom-\($0)", label: "Action \($0)",
            icon: $0 == 9 ? nil : URL(string: "https://example.com/icon.png")) }
        let list = LevixelActionSheetView(actions: actions, imageLoader: loader, select: { _ in }, cancel: {})
        list.frame = CGRect(x: 0, y: 0, width: 320, height: 360)
        list.layoutIfNeeded()
        XCTAssertEqual(loader.requestCount, 0, "Hidden list icons must not load")
        let button = try XCTUnwrap(descendants(of: list).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "levixel-action-custom-0" })
        XCTAssertEqual(button.bounds.width, 320, accuracy: 1)
        let iconList = LevixelActionSheetView(actions: actions, imageLoader: loader, layout: .list, listIcons: true, select: { _ in }, cancel: {})
        XCTAssertEqual(loader.requestCount, 9, "Missing list icons remain optional")
        XCTAssertFalse(iconList.subviews.isEmpty)
        let grid = LevixelActionSheetView(actions: [actions[0]], imageLoader: loader, layout: .grid, listIcons: false, select: { _ in }, cancel: {})
        grid.frame = CGRect(x: 0, y: 0, width: 320, height: 300)
        grid.layoutIfNeeded()
        let tile = try XCTUnwrap(descendants(of: grid).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "levixel-action-custom-0" })
        XCTAssertEqual(tile.bounds.width, 72, accuracy: 1, "One action must retain the chosen grid layout")
    }

    func testActionSheetSelectsOnlyOnceAfterNativeDismissal() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        let presented = expectation(description: "Sheet presented")
        let dismissed = expectation(description: "Selection after dismissal")
        var selections: [String] = []
        let sheet = LevixelActionSheetController(actions: [.init(id: "inspect", label: "Inspect")],
            imageLoader: DeferredImageLoader()) { action in
                XCTAssertNil(presenter.presentedViewController)
                selections.append(action?.id ?? "cancel")
                dismissed.fulfill()
            }
        presenter.present(sheet, animated: true) { sheet.presentationDidComplete(); presented.fulfill() }
        wait(for: [presented], timeout: 3)
        if #available(iOS 15.0, *) { XCTAssertNotNil(sheet.sheetPresentationController) }
        XCTAssertGreaterThan(sheet.view.bounds.height, 150)
        XCTAssertLessThan(sheet.view.bounds.height, window.bounds.height)
        let button = try XCTUnwrap(descendants(of: sheet.view).compactMap { $0 as? UIButton }
            .first { $0.accessibilityIdentifier == "levixel-action-inspect" })
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertTrue(selections.isEmpty, "Business callbacks must wait for the closing transition")
        wait(for: [dismissed], timeout: 3)
        XCTAssertEqual(selections, ["inspect"])
    }

    func testViewerCloseDuringActionSheetPresentationLeavesNoPresentedController() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKeyAndVisible() }
        let source = UIImageView(frame: CGRect(x: 20, y: 40, width: 80, height: 80))
        source.image = makeImage(size: CGSize(width: 80, height: 80))
        presenter.view.addSubview(source)
        let opened = expectation(description: "Viewer opened")
        let closed = expectation(description: "Viewer and sheet closed")
        var events: [String] = []
        var configuration = LevixelViewerConfiguration(actions: [.init(id: "inspect", label: "Inspect")])
        configuration.onEvent = { event in
            events.append(event.type)
            if event.type == "opened" { opened.fulfill() }
        }
        let session = source.presentLevixelViewer(dataSource: LevixelArrayDataSource(items: [.image(source.image)]),
            configuration: configuration, from: presenter)
        wait(for: [opened], timeout: 3)
        let viewer = try XCTUnwrap(presenter.presentedViewController as? LevixelViewerController)
        let page = try XCTUnwrap(descendants(of: viewer.view).compactMap { $0 as? LevixelViewerPageView }.first)
        viewer.levixelViewerPageViewDidLongPress(page)
        session?.close { closed.fulfill() }
        wait(for: [closed], timeout: 4)
        XCTAssertNil(presenter.presentedViewController)
        XCTAssertEqual(events.filter { $0 == "dismiss" }.count, 1)
        XCTAssertFalse(events.contains("action"))
    }

    private func makePageView(
        frame: CGRect,
        preview: UIImage?,
        sourcePreview: UIImage? = nil,
        loader: DeferredImageLoader
    ) -> LevixelViewerPageView {
        let pageView = LevixelViewerPageView(frame: frame)
        let item = LevixelMediaItem.imageURL(
            URL(string: "https://example.com/\(UUID().uuidString).jpg")!,
            placeholder: preview
        )
        pageView.configure(
            index: 0,
            item: item,
            imageLoader: loader,
            mediaContentMode: .scaleAspectFit,
            sourcePreviewImage: sourcePreview ?? preview
        )
        pageView.setNeedsLayout()
        pageView.layoutIfNeeded()
        return pageView
    }

    private func makeImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func requireImageScrollView(in rootView: UIView) -> UIScrollView {
        guard let scrollView = descendants(of: rootView).compactMap({ $0 as? UIScrollView }).first else {
            preconditionFailure("Expected an image scroll view")
        }
        return scrollView
    }

    private func visibleImageViews(in rootView: UIView) -> [UIImageView] {
        descendants(of: rootView).compactMap { view in
            guard let imageView = view as? UIImageView else { return nil }
            guard imageView.image != nil, isVisible(imageView, inside: rootView) else { return nil }
            return imageView
        }
    }

    private func isVisible(_ view: UIView, inside rootView: UIView) -> Bool {
        var candidate: UIView? = view
        while let current = candidate {
            guard !current.isHidden, current.alpha > 0.01 else { return false }
            if current === rootView {
                return true
            }
            candidate = current.superview
        }
        return false
    }

    private func descendants(of rootView: UIView) -> [UIView] {
        rootView.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func requireZoomedState(from scrollView: UIScrollView) -> LevixelImageViewportState {
        guard let imageView = scrollView.subviews.compactMap({ $0 as? UIImageView }).first else {
            preconditionFailure("Expected a zoomable image view")
        }
        guard let state = LevixelImageViewportLayout.captureZoomedState(
            zoomScale: scrollView.zoomScale,
            minimumZoomScale: scrollView.minimumZoomScale,
            imageFrame: imageView.frame,
            contentOffset: scrollView.contentOffset,
            viewportSize: scrollView.bounds.size
        ) else {
            preconditionFailure("Expected a zoomed viewport state")
        }
        return state
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "Drain image handoff callbacks")
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 1)
    }
}

// Like view-based loaders such as SDWebImage, completion requires a live target.
private final class WeakTargetImageLoader: LevixelImageLoading {
    private(set) weak var target: UIImageView?
    private var completion: ((UIImage?) -> Void)?

    func loadImage(_ url: URL, placeholder: UIImage?, imageView: UIImageView,
                   completion: @escaping (UIImage?) -> Void) {
        target = imageView
        imageView.image = placeholder
        self.completion = completion
    }

    func complete(with image: UIImage?) {
        let callback = completion
        completion = nil
        guard let target else { return }
        target.image = image
        callback?(image)
    }
}

private final class DeferredImageLoader: LevixelImageLoading {
    private struct Request {
        let imageView: UIImageView
        let completion: (UIImage?) -> Void
    }

    private var requests: [Request] = []
    var requestCount: Int { requests.count }

    func loadImage(
        _ url: URL,
        placeholder: UIImage?,
        imageView: UIImageView,
        completion: @escaping (UIImage?) -> Void
    ) {
        imageView.image = placeholder
        requests.append(Request(imageView: imageView, completion: completion))
    }

    func completeFirstRequest(with image: UIImage?) {
        completeRequest(at: 0, with: image)
    }

    func completeRequest(at index: Int, with image: UIImage?) {
        precondition(!requests.isEmpty, "Expected a pending image request")
        precondition(requests.indices.contains(index), "Expected a pending request at index \(index)")
        let request = requests.remove(at: index)
        request.imageView.image = image
        request.completion(image)
    }
}

private final class MediaStateObserver: LevixelViewerPageViewDelegate {
    var states: [Bool] = []
    func levixelViewerPageView(_ pageView: LevixelViewerPageView, didLoad loaded: Bool) { states.append(loaded) }
    func levixelViewerPageViewDidRequestDismiss(_ pageView: LevixelViewerPageView) {}
    func levixelViewerPageViewDidToggleVideoChrome(_ pageView: LevixelViewerPageView) {}
    func levixelViewerPageView(_ pageView: LevixelViewerPageView, setHorizontalPagingEnabled enabled: Bool) {}
    func levixelViewerPageViewDidBeginVideoControlsInteraction(_ pageView: LevixelViewerPageView) {}
    func levixelViewerPageViewDidEndVideoControlsInteraction(_ pageView: LevixelViewerPageView) {}
    func levixelViewerPageViewDidBeginMultiTouch(_ pageView: LevixelViewerPageView) {}
    func levixelViewerPageViewDidEndMultiTouch(_ pageView: LevixelViewerPageView) {}
}
