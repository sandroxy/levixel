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

private final class DeferredImageLoader: LevixelImageLoading {
    private struct Request {
        let imageView: UIImageView
        let completion: (UIImage?) -> Void
    }

    private var requests: [Request] = []

    func loadImage(
        _ url: URL,
        placeholder: UIImage?,
        imageView: UIImageView,
        completion: @escaping (UIImage?) -> Void
    ) {
        imageView.image = placeholder
        requests.append(Request(imageView: imageView, completion: completion))
    }

    func completeFirstRequest(with image: UIImage) {
        completeRequest(at: 0, with: image)
    }

    func completeRequest(at index: Int, with image: UIImage) {
        precondition(!requests.isEmpty, "Expected a pending image request")
        precondition(requests.indices.contains(index), "Expected a pending request at index \(index)")
        let request = requests.remove(at: index)
        request.imageView.image = image
        request.completion(image)
    }
}
