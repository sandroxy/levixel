import UIKit

struct LevixelUniSourceViewport {
    let frameInWindow: CGRect
    let sourceViewName: String

    static func resolve(rootView: UIView, window: UIWindow) -> LevixelUniSourceViewport {
        let viewportView = bestWebViewport(in: rootView, window: window) ?? rootView
        return LevixelUniSourceViewport(
            frameInWindow: viewportView.convert(viewportView.bounds, to: nil),
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
            }
            .max {
                visibleArea(of: $0, in: window) < visibleArea(of: $1, in: window)
            }
    }

    private static func visibleArea(of view: UIView, in window: UIWindow) -> CGFloat {
        let frame = view.convert(view.bounds, to: nil).intersection(window.bounds)
        guard frame.isNull == false, frame.isEmpty == false else { return 0 }
        return frame.width * frame.height
    }
}

extension CGRect {
    var isLevixelUniUsable: Bool {
        minX.isFinite
            && minY.isFinite
            && width.isFinite
            && height.isFinite
            && width > 1
            && height > 1
    }
}
