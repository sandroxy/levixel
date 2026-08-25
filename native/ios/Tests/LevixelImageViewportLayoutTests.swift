import Foundation

@main
private enum LevixelImageViewportLayoutTests {
    static func main() {
        wideCoastUsesASubunitFitScale()
        fitStateIsNotCapturedAsUserZoom()
        relativeZoomAndCenterSurviveTheFullImageSwap()
        restoredViewportIsClampedToScrollableBounds()
        invalidGeometryDoesNotProduceLayoutState()
    }

    private static func wideCoastUsesASubunitFitScale() {
        let minimumScale = require(
            LevixelImageViewportLayout.minimumZoomScale(
                imageSize: CGSize(width: 600, height: 400),
                viewportSize: CGSize(width: 414, height: 896),
                aspectFill: false
            )
        )

        expectApproximatelyEqual(minimumScale, 0.69)
        precondition(
            1 > minimumScale + LevixelImageViewportLayout.zoomTolerance,
            "A raw zoomScale of 1 must be recognized as zoomed for the Wide Coast preview"
        )
    }

    private static func fitStateIsNotCapturedAsUserZoom() {
        let state = LevixelImageViewportLayout.captureZoomedState(
            zoomScale: 0.69,
            minimumZoomScale: 0.69,
            imageFrame: CGRect(
                origin: CGPoint(x: 0, y: 310),
                size: CGSize(width: 414, height: 276)
            ),
            contentOffset: CGPoint(x: 0, y: 0),
            viewportSize: CGSize(width: 414, height: 896)
        )

        precondition(state == nil, "An image at minimum zoom must remain in fit mode")
    }

    private static func relativeZoomAndCenterSurviveTheFullImageSwap() {
        let viewportSize = CGSize(width: 414, height: 896)
        let previewMinimumScale = require(
            LevixelImageViewportLayout.minimumZoomScale(
                imageSize: CGSize(width: 600, height: 400),
                viewportSize: viewportSize,
                aspectFill: false
            )
        )
        let previewZoomScale = previewMinimumScale * 2
        let previewFrame = centeredImageFrame(
            imageSize: CGSize(width: 600, height: 400),
            zoomScale: previewZoomScale,
            viewportSize: viewportSize
        )
        let previewContentSize = contentSize(for: previewFrame, viewportSize: viewportSize)
        let previewOffset = CGPoint(x: 280, y: 0)
        precondition(previewOffset.x <= previewContentSize.width - viewportSize.width)

        let state = require(
            LevixelImageViewportLayout.captureZoomedState(
                zoomScale: previewZoomScale,
                minimumZoomScale: previewMinimumScale,
                imageFrame: previewFrame,
                contentOffset: previewOffset,
                viewportSize: viewportSize
            )
        )
        expectApproximatelyEqual(state.relativeZoomScale, 2)

        let fullMinimumScale = require(
            LevixelImageViewportLayout.minimumZoomScale(
                imageSize: CGSize(width: 2400, height: 1600),
                viewportSize: viewportSize,
                aspectFill: false
            )
        )
        let fullMaximumScale = max(fullMinimumScale * 4, 3)
        let fullZoomScale = LevixelImageViewportLayout.restoredZoomScale(
            for: state,
            minimumZoomScale: fullMinimumScale,
            maximumZoomScale: fullMaximumScale
        )
        let fullFrame = centeredImageFrame(
            imageSize: CGSize(width: 2400, height: 1600),
            zoomScale: fullZoomScale,
            viewportSize: viewportSize
        )
        let fullContentSize = contentSize(for: fullFrame, viewportSize: viewportSize)
        let fullOffset = LevixelImageViewportLayout.restoredContentOffset(
            for: state,
            imageFrame: fullFrame,
            contentSize: fullContentSize,
            viewportSize: viewportSize
        )

        expectApproximatelyEqual(fullZoomScale / fullMinimumScale, 2)
        expectApproximatelyEqual(fullOffset.x, previewOffset.x)
        expectApproximatelyEqual(fullOffset.y, previewOffset.y)
    }

    private static func restoredViewportIsClampedToScrollableBounds() {
        let state = LevixelImageViewportState(
            relativeZoomScale: 20,
            normalizedCenter: CGPoint(x: 1, y: 0)
        )
        let zoomScale = LevixelImageViewportLayout.restoredZoomScale(
            for: state,
            minimumZoomScale: 0.5,
            maximumZoomScale: 3
        )
        expectApproximatelyEqual(zoomScale, 3)

        let offset = LevixelImageViewportLayout.restoredContentOffset(
            for: state,
            imageFrame: CGRect(
                origin: CGPoint(x: 0, y: 0),
                size: CGSize(width: 1200, height: 900)
            ),
            contentSize: CGSize(width: 1200, height: 900),
            viewportSize: CGSize(width: 400, height: 800)
        )
        expectApproximatelyEqual(offset.x, 800)
        expectApproximatelyEqual(offset.y, 0)
    }

    private static func invalidGeometryDoesNotProduceLayoutState() {
        precondition(
            LevixelImageViewportLayout.minimumZoomScale(
                imageSize: CGSize(width: 0, height: 0),
                viewportSize: CGSize(width: 414, height: 896),
                aspectFill: false
            ) == nil
        )
        precondition(
            LevixelImageViewportLayout.captureZoomedState(
                zoomScale: 2,
                minimumZoomScale: 1,
                imageFrame: CGRect(
                    origin: CGPoint(x: 0, y: 0),
                    size: CGSize(width: 0, height: 0)
                ),
                contentOffset: CGPoint(x: 0, y: 0),
                viewportSize: CGSize(width: 414, height: 896)
            ) == nil
        )
    }

    private static func centeredImageFrame(
        imageSize: CGSize,
        zoomScale: CGFloat,
        viewportSize: CGSize
    ) -> CGRect {
        let scaledSize = CGSize(
            width: imageSize.width * zoomScale,
            height: imageSize.height * zoomScale
        )
        let resolvedContentSize = CGSize(
            width: max(scaledSize.width, viewportSize.width),
            height: max(scaledSize.height, viewportSize.height)
        )
        let origin = CGPoint(
            x: max((resolvedContentSize.width - scaledSize.width) * 0.5, 0),
            y: max((resolvedContentSize.height - scaledSize.height) * 0.5, 0)
        )
        return CGRect(
            origin: origin,
            size: scaledSize
        )
    }

    private static func contentSize(for imageFrame: CGRect, viewportSize: CGSize) -> CGSize {
        CGSize(
            width: max(imageFrame.size.width, viewportSize.width),
            height: max(imageFrame.size.height, viewportSize.height)
        )
    }

    private static func require<Value>(_ value: Value?) -> Value {
        guard let value else {
            preconditionFailure("Expected a non-nil value")
        }
        return value
    }

    private static func expectApproximatelyEqual(
        _ lhs: CGFloat,
        _ rhs: CGFloat,
        tolerance: CGFloat = 0.0001
    ) {
        precondition(abs(lhs - rhs) <= tolerance, "Expected \(lhs) to equal \(rhs)")
    }
}
