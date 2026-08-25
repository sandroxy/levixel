import Levixel
import UIKit

private final class LevixelUniSession {
    let id = UUID()
    let galleryId: String
    let request: LevixelUniOpenRequest
    let dataSource: LevixelArrayDataSource
    let anchorHost: UIView
    let anchors: [UIImageView?]

    var viewerSession: LevixelViewerSession?
    var currentIndex: Int
    var emitDismissEvent = true
    var afterDismiss: (() -> Void)?

    init(
        galleryId: String,
        request: LevixelUniOpenRequest,
        dataSource: LevixelArrayDataSource,
        anchorHost: UIView,
        anchors: [UIImageView?]
    ) {
        self.galleryId = galleryId
        self.request = request
        self.dataSource = dataSource
        self.anchorHost = anchorHost
        self.anchors = anchors
        currentIndex = request.initialIndex
    }

    func cleanup() {
        anchors.forEach { anchor in
            anchor?.unregisterLevixelSource()
        }
        anchorHost.removeFromSuperview()
        viewerSession = nil
    }
}

@objcMembers
public final class LevixelUniPresenter: NSObject {
    public static let shared = LevixelUniPresenter()

    public var eventHandler: ((NSDictionary) -> Void)?
    private let jsonEventRelay = LevixelUniJSONEventRelay()

    private static let initialPreviewTimeout: TimeInterval = 0.12

    private let imagePipeline = LevixelUniImagePipeline()
    private var activeSession: LevixelUniSession?
    private var pendingOpenID: UUID?

    private override init() {
        super.init()
    }

    @objc(openWithJSON:rootView:viewController:completion:)
    public func openJSON(
        _ optionsJSON: String,
        rootView: UIView?,
        viewController: UIViewController?,
        completion: @escaping (String) -> Void
    ) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard
                let data = optionsJSON.data(using: .utf8),
                let options = try? JSONSerialization.jsonObject(with: data)
            else {
                completion(self.jsonString(self.error(
                    code: "INVALID_JSON",
                    path: "$",
                    message: "Request must be a valid JSON object"
                )))
                return
            }
            self.open(
                options: options,
                rootView: rootView,
                viewController: viewController
            ) { [weak self] result in
                guard let self else { return }
                completion(self.jsonString(result))
            }
        }
    }

    @objc(closeWithJSON:completion:)
    public func closeJSON(
        _ optionsJSON: String,
        completion: @escaping (String) -> Void
    ) {
        performOnMain { [weak self] in
            guard let self else { return }
            guard
                let data = optionsJSON.data(using: .utf8),
                let options = try? JSONSerialization.jsonObject(with: data)
            else {
                completion(self.jsonString(self.error(
                    code: "INVALID_JSON",
                    path: "$",
                    message: "Request must be a valid JSON object"
                )))
                return
            }
            self.close(options: options) { [weak self] result in
                guard let self else { return }
                completion(self.jsonString(result))
            }
        }
    }

    @objc(setJSONEventHandler:)
    public func setJSONEventHandler(_ handler: @escaping (String) -> Void) {
        performOnMain { [weak self] in
            guard let self else { return }
            self.jsonEventRelay.replaceHandler(handler)
            let readyEvent: NSDictionary = [
                "type": "ready",
                "payload": ["message": "levixel event channel ready"],
                "time": Int64(Date().timeIntervalSince1970 * 1000),
            ]
            self.jsonEventRelay.emit(self.jsonString(readyEvent))
        }
    }

    @objc(openWithOptions:rootView:viewController:completion:)
    public func open(
        options: Any?,
        rootView: UIView?,
        viewController: UIViewController?,
        completion: @escaping (NSDictionary) -> Void
    ) {
        precondition(Thread.isMainThread)

        let request: LevixelUniOpenRequest
        do {
            request = try LevixelUniContract.parseOpenRequest(options)
        } catch let contractError as LevixelUniContractError {
            completion(error(
                code: contractError.code,
                path: contractError.path,
                message: contractError.message
            ))
            return
        } catch {
            completion(self.error(
                code: "INVALID_REQUEST",
                path: "$",
                message: "Unable to parse the Levixel request"
            ))
            return
        }

        guard let presenter = topMostViewController(from: viewController) else {
            completion(error(
                code: "NO_VIEW_CONTROLLER",
                path: "$",
                message: "Unable to find the current view controller"
            ))
            return
        }
        presenter.loadViewIfNeeded()
        guard let viewportView = rootView ?? presenter.viewIfLoaded else {
            completion(error(
                code: "NO_VIEWPORT",
                path: "$",
                message: "Unable to find the UniApp viewport"
            ))
            return
        }

        let openID = UUID()
        pendingOpenID = openID
        closeExistingSessionIfNeeded { [weak self] in
            guard let self, self.pendingOpenID == openID else { return }
            self.resolveInitialPreview(
                for: request.items[request.initialIndex],
                timeout: Self.initialPreviewTimeout
            ) { [weak self] image in
                guard let self, self.pendingOpenID == openID else { return }
                guard let currentPresenter = self.topMostViewController(from: viewController) else {
                    self.pendingOpenID = nil
                    completion(self.error(
                        code: "NO_VIEW_CONTROLLER",
                        path: "$",
                        message: "Unable to find the current view controller after closing the previous viewer"
                    ))
                    return
                }
                self.present(
                    request: request,
                    initialPreview: image,
                    viewportView: viewportView,
                    from: currentPresenter,
                    completion: completion
                )
            }
        }
    }

    @objc(closeWithOptions:completion:)
    public func close(options: Any?, completion: @escaping (NSDictionary) -> Void) {
        precondition(Thread.isMainThread)
        do {
            try LevixelUniContract.validateCloseRequest(options)
        } catch let contractError as LevixelUniContractError {
            completion(error(
                code: contractError.code,
                path: contractError.path,
                message: contractError.message
            ))
            return
        } catch {
            completion(self.error(
                code: "INVALID_REQUEST",
                path: "$",
                message: "Unable to validate the close request"
            ))
            return
        }
        pendingOpenID = nil
        guard let session = activeSession else {
            completion(ok(data: ["closed": true]))
            return
        }
        session.emitDismissEvent = true
        session.viewerSession?.close(animated: true)
        completion(ok(data: ["closed": true]))
    }

    @objc
    public func closeImmediately() {
        let close = { [weak self] in
            guard let self else { return }
            self.pendingOpenID = nil
            guard let session = self.activeSession else { return }
            session.emitDismissEvent = false
            if let viewerSession = session.viewerSession {
                viewerSession.close(animated: false)
            } else {
                self.finishSession(session)
            }
        }
        if Thread.isMainThread {
            close()
        } else {
            DispatchQueue.main.async(execute: close)
        }
    }

    private func present(
        request: LevixelUniOpenRequest,
        initialPreview: UIImage?,
        viewportView: UIView,
        from presenter: UIViewController,
        completion: @escaping (NSDictionary) -> Void
    ) {
        guard let window = viewportView.window ?? presenter.viewIfLoaded?.window ?? activeWindow() else {
            pendingOpenID = nil
            completion(error(
                code: "NO_WINDOW",
                path: "$",
                message: "Unable to find the UniApp window"
            ))
            return
        }

        let galleryId = "uni-levixel-\(UUID().uuidString.lowercased())"
        let sourceViewport = LevixelUniSourceViewport.resolve(rootView: viewportView, window: window)
        let host = makeAnchorHost(in: window)
        var previews = request.items.map { imagePipeline.immediateImage(for: $0.transitionURL) }
        if previews[request.initialIndex] == nil {
            previews[request.initialIndex] = initialPreview
        }

        let anchors = request.items.enumerated().map { index, _ -> UIImageView? in
            guard let hint = request.sourceHints[index] else { return nil }
            guard let anchor = makeAnchor(
                hint: hint,
                image: previews[index],
                host: host,
                sourceViewport: sourceViewport,
                window: window
            ) else {
                return nil
            }
            anchor.registerLevixelSource(galleryId: galleryId, index: index)
            return anchor
        }

        let nativeItems = request.items.enumerated().map { index, item in
            item.nativeItem(placeholder: previews[index])
        }
        let dataSource = LevixelArrayDataSource(items: nativeItems)
        let session = LevixelUniSession(
            galleryId: galleryId,
            request: request,
            dataSource: dataSource,
            anchorHost: host,
            anchors: anchors
        )

        var configuration = LevixelViewerConfiguration(
            theme: request.theme,
            contentMode: .scaleAspectFit
        )
        configuration.onIndexChange = { [weak self, weak session] index in
            guard let self, let session, self.activeSession === session else { return }
            let previousIndex = session.currentIndex
            session.currentIndex = index
            if session.request.hidesHTMLSource, previousIndex != index {
                self.emitSourceVisibility(hidden: false, index: previousIndex, session: session)
                self.emitSourceVisibility(hidden: true, index: index, session: session)
            }
            self.emit(type: "indexChange", payload: ["currentIndex": index])
        }
        configuration.onDismiss = { [weak self, weak session] in
            guard let self, let session else { return }
            self.finishSession(session)
        }

        let fallbackAnchor = UIImageView(frame: .zero)
        fallbackAnchor.isUserInteractionEnabled = false
        host.addSubview(fallbackAnchor)
        let initialAnchor = anchors[request.initialIndex] ?? fallbackAnchor

        activeSession = session
        startDeferredPreviewLoads(request: request, anchors: anchors)
        guard let viewerSession = initialAnchor.presentLevixelViewer(
            dataSource: dataSource,
            initialIndex: request.initialIndex,
            configuration: configuration,
            from: presenter,
            imageLoader: imagePipeline,
            galleryId: galleryId,
            completion: { [weak self, weak session] in
                guard let self, let session, self.activeSession === session else { return }
                if session.request.hidesHTMLSource {
                    self.emitSourceVisibility(
                        hidden: true,
                        index: session.currentIndex,
                        session: session
                    )
                }
                self.pendingOpenID = nil
                completion(self.ok(data: [
                    "index": request.initialIndex,
                    "count": request.items.count,
                    "galleryId": galleryId,
                ]))
            }
        ) else {
            activeSession = nil
            pendingOpenID = nil
            session.cleanup()
            completion(error(
                code: "PRESENTATION_FAILED",
                path: "$",
                message: "Unable to present the Levixel viewer"
            ))
            return
        }
        session.viewerSession = viewerSession
    }

    private func closeExistingSessionIfNeeded(completion: @escaping () -> Void) {
        guard let session = activeSession else {
            completion()
            return
        }
        session.emitDismissEvent = false
        session.afterDismiss = completion
        if let viewerSession = session.viewerSession {
            viewerSession.close(animated: false)
        } else {
            finishSession(session)
        }
    }

    private func finishSession(_ session: LevixelUniSession) {
        guard activeSession === session else { return }
        activeSession = nil
        if session.request.hidesHTMLSource {
            emitSourceVisibility(hidden: false, index: session.currentIndex, session: session)
        }
        session.cleanup()
        if session.emitDismissEvent {
            emit(type: "dismiss", payload: [:])
        }
        let afterDismiss = session.afterDismiss
        session.afterDismiss = nil
        afterDismiss?()
    }

    private func resolveInitialPreview(
        for item: LevixelUniItem,
        timeout: TimeInterval,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard let transitionURL = item.transitionURL else {
            completion(nil)
            return
        }
        if let image = imagePipeline.immediateImage(for: transitionURL) {
            completion(image)
            return
        }

        var resolved = false
        let resolve: (UIImage?) -> Void = { image in
            guard resolved == false else { return }
            resolved = true
            completion(image)
        }
        imagePipeline.fetch(transitionURL, completion: resolve)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            resolve(nil)
        }
    }

    private func startDeferredPreviewLoads(
        request: LevixelUniOpenRequest,
        anchors: [UIImageView?]
    ) {
        for (index, item) in request.items.enumerated() {
            guard
                let transitionURL = item.transitionURL,
                let anchor = anchors[index],
                anchor.image == nil
            else {
                continue
            }
            imagePipeline.fetch(transitionURL) { image in
                if let image {
                    anchor.image = image
                }
            }
        }
    }

    private func makeAnchorHost(in window: UIWindow) -> UIView {
        let host = UIView(frame: window.bounds)
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.backgroundColor = .clear
        host.alpha = 0
        host.clipsToBounds = false
        host.isUserInteractionEnabled = false
        window.addSubview(host)
        return host
    }

    private func makeAnchor(
        hint: LevixelUniSourceHint,
        image: UIImage?,
        host: UIView,
        sourceViewport: LevixelUniSourceViewport,
        window: UIWindow
    ) -> UIImageView? {
        let frameInWindow = sourceViewport.frameInWindow(for: hint)
        guard frameInWindow.isLevixelUniUsable, frameInWindow.intersects(window.bounds) else {
            return nil
        }

        let anchor = UIImageView(frame: host.convert(frameInWindow, from: nil))
        anchor.image = image
        anchor.contentMode = hint.objectFit.contentMode
        anchor.clipsToBounds = true
        anchor.layer.cornerRadius = hint.cornerRadius * hint.rectScale
        anchor.isUserInteractionEnabled = false
        host.addSubview(anchor)
        return anchor
    }

    private func topMostViewController(from preferred: UIViewController?) -> UIViewController? {
        var controller = preferred ?? activeWindow()?.rootViewController
        while let current = controller {
            if let navigation = current as? UINavigationController {
                controller = navigation.visibleViewController
            } else if let tabs = current as? UITabBarController {
                controller = tabs.selectedViewController
            } else if let presented = current.presentedViewController {
                controller = presented
            } else {
                return current
            }
        }
        return nil
    }

    private func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
            ?? UIApplication.shared.windows.first { $0.isKeyWindow }
            ?? UIApplication.shared.windows.first
    }

    private func emitSourceVisibility(
        hidden: Bool,
        index: Int,
        session: LevixelUniSession
    ) {
        emit(type: "sourceVisibilityChange", payload: [
            "hidden": hidden,
            "index": index,
            "galleryId": session.galleryId,
        ])
    }

    private func emit(type: String, payload: [String: Any]) {
        let event: NSDictionary = [
            "type": type,
            "payload": payload,
            "time": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        eventHandler?(event)
        jsonEventRelay.emit(jsonString(event))
    }

    private func ok(data: [String: Any]) -> NSDictionary {
        ["ok": true, "data": data]
    }

    private func error(code: String, path: String, message: String) -> NSDictionary {
        ["ok": false, "code": code, "path": path, "message": message]
    }

    private func jsonString(_ value: NSDictionary) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{\"ok\":false,\"code\":\"ENCODING_FAILED\",\"path\":\"$\",\"message\":\"Unable to encode the Levixel response\"}"
        }
        return json
    }

    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.async(execute: action)
        }
    }
}
