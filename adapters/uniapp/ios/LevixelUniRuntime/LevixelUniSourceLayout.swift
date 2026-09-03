import UIKit

struct LevixelUniSourceViewport {
    let frameInWindow: CGRect
    let visibleFrameInWindow: CGRect
    let sourceViewName: String

    static func resolve(rootView: UIView, window: UIWindow) -> LevixelUniSourceViewport {
        let viewportView = bestWebViewport(in: rootView, window: window) ?? rootView
        return LevixelUniSourceViewport(
            frameInWindow: viewportView.convert(viewportView.bounds, to: nil),
            visibleFrameInWindow: visibleFrame(of: viewportView, in: window) ?? .null,
            sourceViewName: NSStringFromClass(type(of: viewportView))
        )
    }

    func frameInWindow(for hint: LevixelUniSourceHint) -> CGRect {
        let rect = CGRect(
            x: hint.rect.minX * hint.rectScale,
            y: hint.rect.minY * hint.rectScale,
            width: hint.rect.width * hint.rectScale,
            height: hint.rect.height * hint.rectScale
        )
        switch hint.coordinateSpace {
        case .viewport:
            return rect.offsetBy(dx: frameInWindow.minX, dy: frameInWindow.minY)
        case .screen:
            return rect
        }
    }

    func clippingFrameInWindow(for hint: LevixelUniSourceHint, window: UIWindow) -> CGRect? {
        let windowFrame = window.convert(window.bounds, to: nil)
        switch hint.coordinateSpace {
        case .viewport:
            return LevixelUniSourceGeometry.positiveIntersection(visibleFrameInWindow, windowFrame)
        case .screen:
            return windowFrame
        }
    }

    private static func bestWebViewport(in rootView: UIView, window: UIWindow) -> UIView? {
        var candidates: [UIView] = []

        func collect(from view: UIView) {
            if NSStringFromClass(type(of: view)).contains("WKWebView") {
                candidates.append(view)
            }
            view.subviews.forEach(collect)
        }

        collect(from: rootView)
        return candidates
            .filter {
                $0.window === window
                    && $0.isHidden == false
                    && $0.alpha > 0.01
                    && $0.bounds.width > 1
                    && $0.bounds.height > 1
                    && visibleArea(of: $0, in: window) > 0
            }
            .max {
                visibleArea(of: $0, in: window) < visibleArea(of: $1, in: window)
            }
    }

    private static func visibleArea(of view: UIView, in window: UIWindow) -> CGFloat {
        guard let frame = visibleFrame(of: view, in: window) else { return 0 }
        return frame.width * frame.height
    }

    private static func visibleFrame(of view: UIView, in window: UIWindow) -> CGRect? {
        guard view.window === window else { return nil }

        var current: UIView? = view
        while let candidate = current {
            guard candidate.isHidden == false, candidate.alpha > 0.01 else { return nil }
            current = candidate.superview
        }

        guard var visibleFrame = LevixelUniSourceGeometry.positiveIntersection(
            view.convert(view.bounds, to: nil),
            window.convert(window.bounds, to: nil)
        ) else {
            return nil
        }

        current = view.superview
        while let ancestor = current, ancestor !== window {
            if ancestor.clipsToBounds || ancestor.layer.masksToBounds {
                guard let clipped = LevixelUniSourceGeometry.positiveIntersection(
                    visibleFrame,
                    ancestor.convert(ancestor.bounds, to: nil)
                ) else {
                    return nil
                }
                visibleFrame = clipped
            }
            current = ancestor.superview
        }
        return visibleFrame
    }
}
