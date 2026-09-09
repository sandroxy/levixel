import ExpoModulesCore
import Levixel
import UIKit

final class LevixelView: ExpoView {
    var items: [[String: Any]] = []
    var initialIndex = 0
    var galleryId = ""
    var sourceCornerRadius: CGFloat = 0 {
        didSet {
            precondition(
                sourceCornerRadius.isFinite && sourceCornerRadius >= 0,
                "Levixel sourceCornerRadius must be a non-negative finite number."
            )
        }
    }
    let onSourcePress = EventDispatcher()
    let onViewerEvent = EventDispatcher()
    private static let sources = NSHashTable<LevixelView>.weakObjects()
    private var sourceTap: UITapGestureRecognizer?
    private var viewerSession: LevixelViewerSession?
    private var pendingOpen: Promise?
    private var openSequence = 0
    private let fallbackImageView = UIImageView()

    private weak var configuredImageView: UIImageView?

    deinit {
        pendingOpen?.reject("OPEN_CANCELLED", "Levixel was unmounted.")
        viewerSession?.close(animated: false)
        clearConfiguredImageView()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            closeImmediately()
            Self.sources.remove(self)
            clearConfiguredImageView()
        } else {
            Self.sources.add(self)
            configureSourceView()
        }
    }

    #if !RCT_NEW_ARCH_ENABLED
    override func insertReactSubview(_ subview: UIView!, at atIndex: Int) {
        super.insertReactSubview(subview, at: atIndex)
        configureSourceView()
    }

    override func removeReactSubview(_ subview: UIView!) {
        clearConfiguredImageView()
        super.removeReactSubview(subview)
    }
    #endif

    #if RCT_NEW_ARCH_ENABLED
    override func mountChildComponentView(_ childComponentView: UIView, index: Int) {
        super.mountChildComponentView(childComponentView, index: index)
        configureSourceView()
    }

    override func unmountChildComponentView(_ childComponentView: UIView, index: Int) {
        clearConfiguredImageView()
        super.unmountChildComponentView(childComponentView, index: index)
    }

    override func prepareForRecycle() {
        closeImmediately()
        clearConfiguredImageView()
        super.prepareForRecycle()
    }
    #endif

    func configureSourceView() {
        guard window != nil, let imageView = findImageView() else {
            clearConfiguredImageView()
            return
        }
        let media = buildMediaItems()
        guard media.items.isEmpty == false else {
            clearConfiguredImageView()
            return
        }

        if configuredImageView !== imageView {
            clearConfiguredImageView()
            configuredImageView = imageView
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(sourcePressed))
            imageView.addGestureRecognizer(recognizer)
            imageView.isUserInteractionEnabled = true
            sourceTap = recognizer
        }
        let safeIndex = min(max(0, initialIndex), media.items.count - 1)
        imageView.registerLevixelSource(galleryId: galleryId,
            itemIdentifier: media.itemIdentifiers[safeIndex], cornerRadius: sourceCornerRadius)
    }

    @objc private func sourcePressed() {
        let media = buildMediaItems()
        guard media.itemIdentifiers.indices.contains(initialIndex) else { return }
        onSourcePress(["itemId": media.itemIdentifiers[initialIndex]])
    }

    func open(options: [String: Any], promise: Promise) {
        guard window != nil,
              let values = options["items"] as? [[String: Any]],
              let requestId = options["requestId"] as? String,
              let targetGalleryId = options["galleryId"] as? String,
              let index = options["index"] as? Int else {
            promise.reject("INVALID_ARGUMENT", "Levixel needs a mounted view and valid open options.")
            return
        }
        let media = buildMediaItems(values: values)
        guard media.items.indices.contains(index) else {
            promise.reject("INVALID_ARGUMENT", "Levixel items or index are invalid.")
            return
        }
        let valuesActions = options["actions"] as? [[String: Any]] ?? []
        guard let actionLayout = LevixelActionLayout(rawValue: (options["actionLayout"] ?? "list") as? String ?? ""),
              options["actionListIcons"] == nil || options["actionListIcons"] is Bool else {
            promise.reject("INVALID_ARGUMENT", "Levixel actionLayout must be list or grid and actionListIcons must be boolean."); return
        }
        let actionListIcons = options["actionListIcons"] as? Bool ?? false
        var actions: [LevixelAction] = []
        var ids = Set<String>()
        for (actionIndex, value) in valuesActions.enumerated() {
            guard let id = value["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(id).inserted, let label = value["label"] as? String,
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                promise.reject("INVALID_ARGUMENT", "Levixel actions need unique IDs and non-empty labels."); return
            }
            let icon = (value["icon"] as? String).flatMap(makeURL)
            if actionLayout == .grid && icon == nil {
                promise.reject("INVALID_ARGUMENT", "Levixel actions[\(actionIndex)].icon is required for grid actionLayout."); return
            }
            actions.append(LevixelAction(id: id, label: label,
                icon: icon, group: value["group"] as? String,
                disabled: value["disabled"] as? Bool ?? false, destructive: value["destructive"] as? Bool ?? false))
        }
        pendingOpen?.reject("OPEN_CANCELLED", "A newer Levixel open replaced this request.")
        openSequence += 1
        let sequence = openSequence
        pendingOpen = promise
        var configuration = LevixelViewerConfiguration(theme: options["theme"] as? String == "light" ? .light : .dark)
        configuration.actions = actions
        configuration.actionLayout = actionLayout
        configuration.actionListIcons = actionListIcons
        configuration.onEvent = { [weak self] event in
            var dictionary = event.dictionary
            dictionary["requestId"] = requestId
            if event.type == "dismiss", self?.viewerSession?.sessionId == event.context.sessionId {
                self?.viewerSession = nil
            }
            self?.onViewerEvent(dictionary)
        }
        let present: () -> Void = { [weak self] in
            guard let self, sequence == self.openSequence, self.window != nil else { return }
            let source = Self.sources.allObjects.first {
                $0.galleryId == targetGalleryId && $0.items.indices.contains($0.initialIndex)
                    && $0.items[$0.initialIndex]["id"] as? String == media.itemIdentifiers[index]
                    && $0.configuredImageView?.window != nil
            }
            var resolvedConfiguration = configuration
            resolvedConfiguration.sourceCornerRadius = source?.sourceCornerRadius
            let imageView = source?.configuredImageView ?? self.fallbackImageView
            self.viewerSession = imageView.presentLevixelViewer(
                dataSource: LevixelArrayDataSource(items: media.items, itemIdentifiers: media.itemIdentifiers),
                initialIndex: index, configuration: resolvedConfiguration,
                from: self.window?.rootViewController, galleryId: targetGalleryId)
            self.pendingOpen = nil
            if self.viewerSession == nil { promise.reject("OPEN_FAILED", "No presenter is available.") }
            else { promise.resolve() }
        }
        if let viewerSession { viewerSession.close(animated: false, completion: present) }
        else { present() }
    }

    func close(promise: Promise) {
        openSequence += 1
        pendingOpen?.reject("OPEN_CANCELLED", "Levixel was closed before opening.")
        pendingOpen = nil
        guard let viewerSession else { promise.resolve(); return }
        viewerSession.close { promise.resolve() }
    }

    private func closeImmediately() {
        openSequence += 1
        pendingOpen?.reject("OPEN_CANCELLED", "Levixel was unmounted.")
        pendingOpen = nil
        viewerSession?.close(animated: false)
        viewerSession = nil
    }

    func retry() -> Bool { viewerSession?.retry() ?? false }

    private func buildMediaItems(values: [[String: Any]]? = nil) -> (
        items: [LevixelMediaItem],
        itemIdentifiers: [String]
    ) {
        var mediaItems: [LevixelMediaItem] = []
        var itemIdentifiers: [String] = []
        var seenItemIdentifiers = Set<String>()

        for value in values ?? items {
            guard
                let itemIdentifier = value["id"] as? String,
                itemIdentifier.isEmpty == false,
                seenItemIdentifiers.insert(itemIdentifier).inserted,
                let type = value["type"] as? String,
                let sourceValue = value["url"] as? String,
                let sourceURL = makeURL(sourceValue)
            else {
                return ([], [])
            }

            let mediaItem: LevixelMediaItem
            switch type {
            case "video":
                let posterValue = value["posterUrl"] as? String ?? value["thumbnailUrl"] as? String
                mediaItem = .video(url: sourceURL, poster: posterValue.flatMap(makeURL))
            case "image":
                let thumbnailURL = (value["thumbnailUrl"] as? String).flatMap(makeURL)
                mediaItem = .imageURL(
                    sourceURL,
                    thumbnailURL: thumbnailURL,
                    placeholder: nil
                )
            default:
                return ([], [])
            }

            mediaItems.append(mediaItem)
            itemIdentifiers.append(itemIdentifier)
        }
        return (mediaItems, itemIdentifiers)
    }

    private func clearConfiguredImageView() {
        if let sourceTap { configuredImageView?.removeGestureRecognizer(sourceTap) }
        sourceTap = nil
        configuredImageView?.unregisterLevixelSource()
        configuredImageView = nil
    }

    private func makeURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return value.isEmpty ? nil : URL(fileURLWithPath: value)
    }

    private func findImageView() -> UIImageView? {
        var bestImageView: UIImageView?
        var bestScore = Int.min

        func visit(_ view: UIView) {
            if let imageView = view as? UIImageView {
                let score = imageViewScore(imageView)
                if score > bestScore {
                    bestImageView = imageView
                    bestScore = score
                }
            }
            view.subviews.forEach(visit)
        }

        subviews.forEach(visit)
        return bestImageView
    }

    private func imageViewScore(_ imageView: UIImageView) -> Int {
        var score = 0
        if imageView.window != nil { score += 16 }
        if imageView.bounds.width > 0, imageView.bounds.height > 0 { score += 16 }
        if !imageView.isHidden, imageView.alpha > 0.001 { score += 16 }
        if imageView.image != nil { score += 8 }
        if imageView === configuredImageView { score += 1 }
        return score
    }
}
