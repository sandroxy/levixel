import ObjectiveC
import UIKit

public final class LevixelViewerSession {
    private weak var viewerController: LevixelViewerController?
    private let dataSource: LevixelDataSource
    private let imageLoader: LevixelImageLoading

    fileprivate init(
        viewerController: LevixelViewerController,
        dataSource: LevixelDataSource,
        imageLoader: LevixelImageLoading
    ) {
        self.viewerController = viewerController
        self.dataSource = dataSource
        self.imageLoader = imageLoader
    }

    public func close(animated: Bool = true) {
        let closeViewer: () -> Void = { [weak self] in
            guard let viewerController = self?.viewerController else { return }
            viewerController.requestDismissal(animated: animated)
        }
        if Thread.isMainThread {
            closeViewer()
        } else {
            DispatchQueue.main.async(execute: closeViewer)
        }
    }

    func invalidate() {
        viewerController = nil
    }
}

extension UIImageView {
    private enum LevixelAnchorReference {
        case index(Int)
        case itemIdentifier(String)
    }

    private struct LevixelAnchorRegistration {
        let galleryId: String
        let reference: LevixelAnchorReference
    }

    private final class LevixelTapGestureRecognizer: UITapGestureRecognizer {
        weak var fromViewController: UIViewController?
        var dataSource: LevixelDataSource?
        var imageLoader: LevixelImageLoading?
        var initialIndex = 0
        var galleryId: String?
        var configuration = LevixelViewerConfiguration()
    }

    private static var anchorRegistrationKey: UInt8 = 0
    private static var gestureRecognizerKey: UInt8 = 0

    private var topMostHostViewController: UIViewController? {
        let keyWindow: UIWindow? = {
            if #available(iOS 13.0, *) {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
                return activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
            } else {
                return UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first
            }
        }()
        guard let rootViewController = keyWindow?.rootViewController else { return nil }
        return rootViewController.presentedViewController ?? rootViewController
    }

    public func setupLevixelViewer(
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        from viewController: UIViewController? = nil,
        imageLoader: LevixelImageLoading? = nil,
        galleryId: String? = nil
    ) {
        configureLevixelViewer(
            dataSource: LevixelArrayDataSource(items: [.image(image)]),
            initialIndex: 0,
            configuration: configuration,
            from: viewController,
            imageLoader: imageLoader,
            galleryId: galleryId
        )
    }

    public func setupLevixelViewer(
        url: URL,
        initialIndex: Int = 0,
        placeholder: UIImage? = nil,
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        from viewController: UIViewController? = nil,
        imageLoader: LevixelImageLoading? = nil,
        galleryId: String? = nil
    ) {
        configureLevixelViewer(
            dataSource: LevixelArrayDataSource(items: [.imageURL(url, placeholder: placeholder)]),
            initialIndex: initialIndex,
            configuration: configuration,
            from: viewController,
            imageLoader: imageLoader,
            galleryId: galleryId
        )
    }

    public func setupLevixelViewer(
        images: [UIImage],
        initialIndex: Int = 0,
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        from viewController: UIViewController? = nil,
        imageLoader: LevixelImageLoading? = nil,
        galleryId: String? = nil
    ) {
        let items = images.map { LevixelMediaItem.image($0) }
        configureLevixelViewer(
            dataSource: LevixelArrayDataSource(items: items),
            initialIndex: initialIndex,
            configuration: configuration,
            from: viewController,
            imageLoader: imageLoader,
            galleryId: galleryId
        )
    }

    public func setupLevixelViewer(
        urls: [URL],
        initialIndex: Int = 0,
        placeholder: UIImage? = nil,
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        from viewController: UIViewController? = nil,
        imageLoader: LevixelImageLoading? = nil,
        galleryId: String? = nil
    ) {
        let items = urls.map { LevixelMediaItem.imageURL($0, placeholder: placeholder) }
        configureLevixelViewer(
            dataSource: LevixelArrayDataSource(items: items),
            initialIndex: initialIndex,
            configuration: configuration,
            from: viewController,
            imageLoader: imageLoader,
            galleryId: galleryId
        )
    }

    public func setupLevixelViewer(
        dataSource: LevixelDataSource,
        initialIndex: Int = 0,
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        from viewController: UIViewController? = nil,
        imageLoader: LevixelImageLoading? = nil,
        galleryId: String? = nil
    ) {
        configureLevixelViewer(
            dataSource: dataSource,
            initialIndex: initialIndex,
            configuration: configuration,
            from: viewController,
            imageLoader: imageLoader,
            galleryId: galleryId
        )
    }

    public func removeLevixelViewerInteraction() {
        if let recognizer = levixelTapGestureRecognizer {
            removeGestureRecognizer(recognizer)
        }
        levixelTapGestureRecognizer = nil

        unregisterLevixelSource()
    }

    public func registerLevixelSource(galleryId: String, index: Int) {
        updateLevixelAnchorRegistration(galleryId: galleryId, reference: .index(index))
    }

    public func registerLevixelSource(galleryId: String, itemIdentifier: String) {
        let reference = itemIdentifier.isEmpty
            ? nil
            : LevixelAnchorReference.itemIdentifier(itemIdentifier)
        updateLevixelAnchorRegistration(galleryId: galleryId, reference: reference)
    }

    public func unregisterLevixelSource() {
        guard let registration = levixelAnchorRegistration else { return }
        switch registration.reference {
        case .index(let index):
            LevixelSourceViewRegistry.shared.unregister(
                self,
                galleryId: registration.galleryId,
                index: index
            )
        case .itemIdentifier(let itemIdentifier):
            LevixelSourceViewRegistry.shared.unregister(
                self,
                galleryId: registration.galleryId,
                itemIdentifier: itemIdentifier
            )
        }
        levixelAnchorRegistration = nil
    }

    @discardableResult
    public func presentLevixelViewer(
        dataSource: LevixelDataSource,
        initialIndex: Int = 0,
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        from viewController: UIViewController? = nil,
        imageLoader: LevixelImageLoading? = nil,
        galleryId: String? = nil,
        completion: (() -> Void)? = nil
    ) -> LevixelViewerSession? {
        let itemCount = dataSource.numberOfItems()
        guard itemCount > 0 else { return nil }
        let safeInitialIndex = min(max(initialIndex, 0), itemCount - 1)

        let resolvedImageLoader = imageLoader ?? LevixelImageLoaderFactory.makeDefault()
        let viewerController = LevixelViewerController(
            sourceView: self,
            dataSource: dataSource,
            imageLoader: resolvedImageLoader,
            configuration: configuration,
            initialIndex: safeInitialIndex,
            galleryId: galleryId
        )
        let rootViewController = viewController ?? topMostHostViewController
        guard let presenter = rootViewController.map(topMostPresentedController(from:)) else {
            return nil
        }

        if let galleryId, galleryId.isEmpty == false {
            updateLevixelAnchorRegistration(
                galleryId: galleryId,
                reference: anchorReference(for: dataSource, index: safeInitialIndex)
            )
        }

        let session = LevixelViewerSession(
            viewerController: viewerController,
            dataSource: dataSource,
            imageLoader: resolvedImageLoader
        )
        viewerController.attachPresentationSession(session)
        presenter.present(viewerController, animated: false, completion: completion)
        return session
    }

    private func configureLevixelViewer(
        dataSource: LevixelDataSource?,
        initialIndex: Int,
        configuration: LevixelViewerConfiguration,
        from viewController: UIViewController?,
        imageLoader: LevixelImageLoading?,
        galleryId: String?
    ) {
        let safeInitialIndex = clampedIndex(initialIndex, for: dataSource)
        let recognizer = levixelTapGestureRecognizer ?? {
            let recognizer = LevixelTapGestureRecognizer(target: self, action: #selector(showLevixelViewer(_:)))
            recognizer.numberOfTouchesRequired = 1
            recognizer.numberOfTapsRequired = 1
            levixelTapGestureRecognizer = recognizer
            return recognizer
        }()

        isUserInteractionEnabled = true
        clipsToBounds = true

        recognizer.dataSource = dataSource
        recognizer.imageLoader = imageLoader
        recognizer.initialIndex = safeInitialIndex
        recognizer.galleryId = galleryId
        recognizer.configuration = configuration
        recognizer.fromViewController = viewController

        if recognizer.view !== self {
            addGestureRecognizer(recognizer)
        }

        updateLevixelAnchorRegistration(
            galleryId: galleryId,
            reference: anchorReference(for: dataSource, index: safeInitialIndex)
        )
    }

    private var levixelTapGestureRecognizer: LevixelTapGestureRecognizer? {
        get {
            objc_getAssociatedObject(self, &Self.gestureRecognizerKey) as? LevixelTapGestureRecognizer
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.gestureRecognizerKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    private var levixelAnchorRegistration: LevixelAnchorRegistration? {
        get {
            objc_getAssociatedObject(self, &Self.anchorRegistrationKey) as? LevixelAnchorRegistration
        }
        set {
            objc_setAssociatedObject(
                self,
                &Self.anchorRegistrationKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    @objc
    private func showLevixelViewer(_ recognizer: LevixelTapGestureRecognizer) {
        guard let sourceView = recognizer.view as? UIImageView else { return }
        guard let dataSource = recognizer.dataSource else { return }
        sourceView.presentLevixelViewer(
            dataSource: dataSource,
            initialIndex: recognizer.initialIndex,
            configuration: recognizer.configuration,
            from: recognizer.fromViewController,
            imageLoader: recognizer.imageLoader,
            galleryId: recognizer.galleryId
        )
    }

    private func topMostPresentedController(from rootViewController: UIViewController) -> UIViewController {
        var controller = rootViewController
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }

    private func clampedIndex(_ index: Int, for dataSource: LevixelDataSource?) -> Int {
        let itemCount = dataSource?.numberOfItems() ?? 0
        guard itemCount > 0 else { return 0 }
        return min(max(index, 0), itemCount - 1)
    }

    private func anchorReference(
        for dataSource: LevixelDataSource?,
        index: Int
    ) -> LevixelAnchorReference? {
        guard let dataSource, dataSource.numberOfItems() > 0 else { return nil }
        if let identifiedDataSource = dataSource as? LevixelIdentifiedDataSource,
           let itemIdentifier = identifiedDataSource.itemIdentifier(at: index),
           itemIdentifier.isEmpty == false {
            return .itemIdentifier(itemIdentifier)
        }
        return .index(index)
    }

    private func updateLevixelAnchorRegistration(
        galleryId: String?,
        reference: LevixelAnchorReference?
    ) {
        unregisterLevixelSource()

        guard
            let galleryId = galleryId,
            galleryId.isEmpty == false,
            let reference
        else {
            return
        }

        switch reference {
        case .index(let index):
            LevixelSourceViewRegistry.shared.register(self, galleryId: galleryId, index: index)
        case .itemIdentifier(let itemIdentifier):
            LevixelSourceViewRegistry.shared.register(
                self,
                galleryId: galleryId,
                itemIdentifier: itemIdentifier
            )
        }
        levixelAnchorRegistration = LevixelAnchorRegistration(
            galleryId: galleryId,
            reference: reference
        )
    }
}
