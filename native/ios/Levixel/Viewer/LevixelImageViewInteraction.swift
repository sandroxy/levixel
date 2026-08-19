import ObjectiveC
import UIKit

extension UIImageView {
    private struct LevixelAnchorRegistration {
        let galleryId: String
        let index: Int
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

    func removeLevixelViewerInteraction() {
        if let recognizer = levixelTapGestureRecognizer {
            removeGestureRecognizer(recognizer)
        }
        levixelTapGestureRecognizer = nil

        if let registration = levixelAnchorRegistration {
            LevixelSourceViewRegistry.shared.unregister(
                self,
                galleryId: registration.galleryId,
                index: registration.index
            )
        }
        levixelAnchorRegistration = nil
    }

    private func configureLevixelViewer(
        dataSource: LevixelDataSource?,
        initialIndex: Int,
        configuration: LevixelViewerConfiguration,
        from viewController: UIViewController?,
        imageLoader: LevixelImageLoading?,
        galleryId: String?
    ) {
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
        recognizer.initialIndex = initialIndex
        recognizer.galleryId = galleryId
        recognizer.configuration = configuration
        recognizer.fromViewController = viewController

        if recognizer.view !== self {
            addGestureRecognizer(recognizer)
        }

        updateLevixelAnchorRegistration(galleryId: galleryId, index: initialIndex)
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
        let resolvedImageLoader = recognizer.imageLoader ?? LevixelImageLoaderFactory.makeDefault()
        let viewerController = LevixelViewerController(
            sourceView: sourceView,
            dataSource: recognizer.dataSource,
            imageLoader: resolvedImageLoader,
            configuration: recognizer.configuration,
            initialIndex: recognizer.initialIndex,
            galleryId: recognizer.galleryId
        )

        let rootViewController = recognizer.fromViewController ?? topMostHostViewController
        let presenter = rootViewController.flatMap(topMostPresentedController(from:))
        presenter?.present(viewerController, animated: false)
    }

    private func topMostPresentedController(from rootViewController: UIViewController) -> UIViewController {
        var controller = rootViewController
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }

    private func updateLevixelAnchorRegistration(galleryId: String?, index: Int) {
        if let existing = levixelAnchorRegistration {
            LevixelSourceViewRegistry.shared.unregister(
                self,
                galleryId: existing.galleryId,
                index: existing.index
            )
            levixelAnchorRegistration = nil
        }

        guard let galleryId = galleryId, galleryId.isEmpty == false else { return }
        LevixelSourceViewRegistry.shared.register(self, galleryId: galleryId, index: index)
        levixelAnchorRegistration = LevixelAnchorRegistration(galleryId: galleryId, index: index)
    }
}
