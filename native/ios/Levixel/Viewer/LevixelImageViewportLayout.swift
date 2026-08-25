import Foundation

struct LevixelImageViewportState {
    let relativeZoomScale: CGFloat
    let normalizedCenter: CGPoint
}

enum LevixelImageViewportLayout {
    static let zoomTolerance: CGFloat = 0.01

    static func minimumZoomScale(
        imageSize: CGSize,
        viewportSize: CGSize,
        aspectFill: Bool
    ) -> CGFloat? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let widthRatio = viewportSize.width / imageSize.width
        let heightRatio = viewportSize.height / imageSize.height
        return aspectFill ? max(widthRatio, heightRatio) : min(widthRatio, heightRatio)
    }

    static func captureZoomedState(
        zoomScale: CGFloat,
        minimumZoomScale: CGFloat,
        imageFrame: CGRect,
        contentOffset: CGPoint,
        viewportSize: CGSize
    ) -> LevixelImageViewportState? {
        guard minimumZoomScale > 0 else { return nil }
        guard zoomScale > minimumZoomScale + zoomTolerance else { return nil }
        guard imageFrame.size.width > 0, imageFrame.size.height > 0 else { return nil }
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

        let visibleCenter = CGPoint(
            x: contentOffset.x + viewportSize.width * 0.5,
            y: contentOffset.y + viewportSize.height * 0.5
        )
        let normalizedCenter = CGPoint(
            x: clamp(
                (visibleCenter.x - imageFrame.origin.x) / imageFrame.size.width,
                lower: 0,
                upper: 1
            ),
            y: clamp(
                (visibleCenter.y - imageFrame.origin.y) / imageFrame.size.height,
                lower: 0,
                upper: 1
            )
        )
        return LevixelImageViewportState(
            relativeZoomScale: max(zoomScale / minimumZoomScale, 1),
            normalizedCenter: normalizedCenter
        )
    }

    static func restoredZoomScale(
        for state: LevixelImageViewportState,
        minimumZoomScale: CGFloat,
        maximumZoomScale: CGFloat
    ) -> CGFloat {
        clamp(
            minimumZoomScale * max(state.relativeZoomScale, 1),
            lower: minimumZoomScale,
            upper: maximumZoomScale
        )
    }

    static func restoredContentOffset(
        for state: LevixelImageViewportState,
        imageFrame: CGRect,
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGPoint {
        let imageCenter = CGPoint(
            x: imageFrame.origin.x + imageFrame.size.width * state.normalizedCenter.x,
            y: imageFrame.origin.y + imageFrame.size.height * state.normalizedCenter.y
        )
        let maximumOffset = CGPoint(
            x: max(contentSize.width - viewportSize.width, 0),
            y: max(contentSize.height - viewportSize.height, 0)
        )
        return CGPoint(
            x: clamp(imageCenter.x - viewportSize.width * 0.5, lower: 0, upper: maximumOffset.x),
            y: clamp(imageCenter.y - viewportSize.height * 0.5, lower: 0, upper: maximumOffset.y)
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
