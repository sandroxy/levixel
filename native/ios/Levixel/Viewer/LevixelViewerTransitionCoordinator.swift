import UIKit

private final class LevixelTransitionSnapshotView: UIView {
    private let imageView = UIImageView()

    init(image: UIImage) {
        super.init(frame: .zero)
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false

        imageView.image = image
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateImage(_ image: UIImage) {
        imageView.image = image
    }

    func applyContentFrame(_ frame: CGRect) {
        imageView.frame = frame
    }
}

final class LevixelViewerTransitionCoordinator {
    private weak var containerView: UIView?
    private weak var hiddenAnchorView: UIView?
    private weak var hiddenPageView: LevixelViewerPageView?
    private var activeSnapshotView: UIView?

    init(containerView: UIView) {
        self.containerView = containerView
    }

    static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return bounds }

        let widthRatio = bounds.width / imageSize.width
        let heightRatio = bounds.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: bounds.midX - fittedSize.width * 0.5,
            y: bounds.midY - fittedSize.height * 0.5,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    func performOpenTransition(
        from sourceView: UIImageView?,
        sourceCornerRadius: CGFloat?,
        to pageView: LevixelViewerPageView?,
        backgroundView: UIView,
        contentView: UIView,
        completion: @escaping () -> Void
    ) {
        guard let containerView = containerView else {
            pageView?.completeOpenTransitionPreviewHandoff()
            completion()
            return
        }

        restoreHiddenViews()
        activeSnapshotView?.removeFromSuperview()
        activeSnapshotView = nil

        backgroundView.alpha = 0
        contentView.alpha = 0

        flushLayoutForSharedElementSampling(of: sourceView)
        guard
            let sourceView = sourceView,
            let sourceState = sourceView.levixelSharedElementState(
                cornerRadius: sourceCornerRadius
            )
        else {
            pageView?.completeOpenTransitionPreviewHandoff()
            animateSimpleAppearance(
                backgroundView: backgroundView,
                contentView: contentView,
                completion: completion
            )
            return
        }

        let snapshotView = makeSnapshot(from: sourceState)
        apply(sourceState.geometry, to: snapshotView)
        containerView.addSubview(snapshotView)
        activeSnapshotView = snapshotView

        hiddenAnchorView = sourceView
        sourceView.alpha = 0
        pageView?.setMediaHidden(true)
        hiddenPageView = pageView

        let animateIntoPage: (Bool) -> Void = { [weak self] isReady in
            guard let self = self, let containerView = self.containerView else {
                pageView?.completeOpenTransitionPreviewHandoff()
                completion()
                return
            }

            let windowBounds = containerView.window?.bounds ?? UIScreen.main.bounds
            let targetGeometry: LevixelSharedElementGeometry
            if isReady, let pageState = pageView?.sharedElementState() {
                targetGeometry = pageState.geometry
            } else if let pageView = pageView {
                targetGeometry = pageView.defaultTransitionGeometry(in: windowBounds)
            } else {
                targetGeometry = self.defaultGeometry(for: sourceState.image.size, in: windowBounds)
            }

            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.94,
                initialSpringVelocity: 0.08,
                options: [.curveEaseInOut, .allowUserInteraction]
            ) {
                backgroundView.alpha = 1
                self.apply(targetGeometry, to: snapshotView)
            } completion: { _ in
                pageView?.completeOpenTransitionPreviewHandoff()
                self.restoreHiddenViews()
                contentView.alpha = 1
                snapshotView.removeFromSuperview()
                self.activeSnapshotView = nil
                completion()
            }
        }

        guard let pageView = pageView else {
            animateIntoPage(false)
            return
        }

        waitUntilReady(pageView: pageView, timeout: 0.42) { ready in
            animateIntoPage(ready)
        }
    }

    func performCloseTransition(
        from pageView: LevixelViewerPageView?,
        to anchorView: UIImageView?,
        anchorCornerRadius: CGFloat?,
        backgroundView: UIView,
        contentView: UIView,
        completion: @escaping () -> Void
    ) {
        guard let containerView = containerView else {
            completion()
            return
        }

        restoreHiddenViews()
        activeSnapshotView?.removeFromSuperview()
        activeSnapshotView = nil

        guard
            let pageView,
            let pageState = pageView.sharedElementState()
        else {
            animateSimpleDismissal(
                backgroundView: backgroundView,
                contentView: contentView,
                completion: completion
            )
            return
        }

        let snapshotView = makeSnapshot(from: pageState)
        apply(pageState.geometry, to: snapshotView)
        containerView.addSubview(snapshotView)
        activeSnapshotView = snapshotView

        hiddenPageView = pageView
        pageView.setMediaHidden(true)

        var targetGeometry: LevixelSharedElementGeometry?
        flushLayoutForSharedElementSampling(of: anchorView)
        if let anchorView = anchorView,
           let anchorState = anchorView.levixelSharedElementState(
               cornerRadius: anchorCornerRadius
           ) {
            hiddenAnchorView = anchorView
            anchorView.alpha = 0
            targetGeometry = anchorState.geometry
        }

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            backgroundView.alpha = 0
            contentView.alpha = 0
            if let targetGeometry = targetGeometry {
                self.apply(targetGeometry, to: snapshotView)
            } else {
                snapshotView.alpha = 0
                snapshotView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        } completion: { [weak self] _ in
            self?.restoreHiddenViews()
            snapshotView.removeFromSuperview()
            self?.activeSnapshotView = nil
            completion()
        }
    }

    private func animateSimpleAppearance(
        backgroundView: UIView,
        contentView: UIView,
        completion: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            backgroundView.alpha = 1
            contentView.alpha = 1
        } completion: { _ in
            completion()
        }
    }

    private func animateSimpleDismissal(
        backgroundView: UIView,
        contentView: UIView,
        completion: @escaping () -> Void
    ) {
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            backgroundView.alpha = 0
            contentView.alpha = 0
        } completion: { _ in
            completion()
        }
    }

    private func waitUntilReady(
        pageView: LevixelViewerPageView,
        timeout: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = CACurrentMediaTime() + timeout
        var lastStableState: LevixelSharedElementState?
        var stableFrameCount = 0

        func poll() {
            pageView.layoutIfNeeded()
            if let currentState = pageView.sharedElementState() {
                if let lastStableState = lastStableState, lastStableState.approximatelyEquals(currentState) {
                    stableFrameCount += 1
                } else {
                    lastStableState = currentState
                    stableFrameCount = 1
                }

                if stableFrameCount >= 2 {
                    completion(true)
                    return
                }
            }
            if CACurrentMediaTime() >= deadline {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: poll)
        }

        poll()
    }

    private func frameInContainer(fromWindowFrame windowFrame: CGRect) -> CGRect {
        guard let containerView = containerView else { return windowFrame }
        return containerView.convert(windowFrame, from: nil)
    }

    private func flushLayoutForSharedElementSampling(of imageView: UIImageView?) {
        imageView?.superview?.layoutIfNeeded()
        imageView?.layoutIfNeeded()
        containerView?.layoutIfNeeded()
    }

    private func makeSnapshot(from state: LevixelSharedElementState) -> LevixelTransitionSnapshotView {
        LevixelTransitionSnapshotView(image: state.image)
    }

    private func apply(_ geometry: LevixelSharedElementGeometry, to snapshotView: LevixelTransitionSnapshotView) {
        snapshotView.frame = frameInContainer(fromWindowFrame: geometry.visibleFrameInWindow)
        snapshotView.applyContentFrame(geometry.contentFrameInVisibleBounds)
        snapshotView.layer.cornerRadius = geometry.cornerRadius
    }

    private func defaultGeometry(for imageSize: CGSize, in windowBounds: CGRect) -> LevixelSharedElementGeometry {
        let visibleFrame = Self.aspectFitRect(for: imageSize, in: windowBounds)
        return LevixelSharedElementGeometry(
            visibleFrameInWindow: visibleFrame,
            contentFrameInVisibleBounds: CGRect(origin: .zero, size: visibleFrame.size),
            cornerRadius: 0
        )
    }

    private func restoreHiddenViews() {
        hiddenAnchorView?.alpha = 1
        hiddenAnchorView = nil
        hiddenPageView?.setMediaHidden(false)
        hiddenPageView = nil
    }
}
