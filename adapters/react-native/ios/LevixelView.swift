import ExpoModulesCore
import Levixel
import UIKit

final class LevixelView: ExpoView {
    var items: [[String: Any]] = []
    var initialIndex = 0
    var galleryId = ""
    var sourceId = ""
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
    private var sourceTap: UITapGestureRecognizer?
    private var viewerSession: LevixelViewerSession?
    private var pendingOpen: Promise?
    private var openSequence = 0
    private var sourceBinding: LevixelSourceRegistration?
    private var boundItemId: String?
    private var boundGalleryId: String?

    deinit {
        pendingOpen?.reject("OPEN_CANCELLED", "Levixel was unmounted.")
        viewerSession?.close(animated: false)
        clearSourceBinding()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            closeImmediately()
            clearSourceBinding()
        } else {
            configureSourceView()
        }
    }

    #if !RCT_NEW_ARCH_ENABLED
    override func insertReactSubview(_ subview: UIView!, at atIndex: Int) {
        super.insertReactSubview(subview, at: atIndex)
        configureSourceView()
    }

    override func removeReactSubview(_ subview: UIView!) {
        super.removeReactSubview(subview)
        configureSourceView()
    }
    #endif

    #if RCT_NEW_ARCH_ENABLED
    override func mountChildComponentView(_ childComponentView: UIView, index: Int) {
        super.mountChildComponentView(childComponentView, index: index)
        configureSourceView()
    }

    override func unmountChildComponentView(_ childComponentView: UIView, index: Int) {
        super.unmountChildComponentView(childComponentView, index: index)
        // The Source container is still alive. Its provider resolves a remaining
        // or replacement image on demand, including a temporary empty child tree.
        configureSourceView()
    }

    override func prepareForRecycle() {
        closeImmediately()
        clearSourceBinding()
        super.prepareForRecycle()
    }
    #endif

    func configureSourceView() {
        let media = buildMediaItems()
        guard window != nil, !sourceId.isEmpty, !galleryId.isEmpty,
              media.itemIdentifiers.indices.contains(initialIndex) else {
            clearSourceBinding()
            return
        }
        let itemId = media.itemIdentifiers[initialIndex]
        if sourceBinding?.sourceIdentifier != sourceId { clearSourceBinding() }
        if sourceBinding == nil {
            sourceBinding = LevixelSourceRegistration(view: self, sourceIdentifier: sourceId,
                imageViewProvider: { Self.findDisplayedImage(in: $0) })
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(sourcePressed))
            addGestureRecognizer(recognizer)
            sourceTap = recognizer
        }
        if boundItemId != itemId || boundGalleryId != galleryId {
            // Rebinding during a touch must not activate the replacement media.
            sourceTap?.isEnabled = false
            sourceTap?.isEnabled = true
        }
        boundItemId = itemId
        boundGalleryId = galleryId
        sourceBinding?.register(galleryId: galleryId, itemIdentifier: itemId, cornerRadius: sourceCornerRadius)
    }

    @objc private func sourcePressed() {
        let media = buildMediaItems()
        guard window != nil, media.itemIdentifiers.indices.contains(initialIndex),
              sourceBinding?.sourceIdentifier == sourceId, boundGalleryId == galleryId,
              boundItemId == media.itemIdentifiers[initialIndex] else { return }
        onSourcePress(["itemId": media.itemIdentifiers[initialIndex], "sourceId": sourceId])
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
            guard let presenter = self.window?.rootViewController else {
                self.pendingOpen = nil
                promise.reject("OPEN_FAILED", "No presenter is available.")
                return
            }
            self.viewerSession = LevixelViewerSession.present(
                dataSource: LevixelArrayDataSource(items: media.items, itemIdentifiers: media.itemIdentifiers),
                initialIndex: index, configuration: configuration,
                from: presenter, galleryId: targetGalleryId, sourceIdentifier: options["sourceId"] as? String)
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

    private func clearSourceBinding() {
        if let sourceTap { removeGestureRecognizer(sourceTap) }
        sourceTap = nil
        sourceBinding?.unregister()
        sourceBinding = nil
        boundItemId = nil
        boundGalleryId = nil
    }

    private func makeURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return value.isEmpty ? nil : URL(fileURLWithPath: value)
    }

    private static func findDisplayedImage(in source: UIView) -> UIImageView? {
        var best: UIImageView?
        var bestAlpha: CGFloat = -1
        var bestArea: CGFloat = -1
        func visit(_ view: UIView, parentAlpha: CGFloat) {
            let alpha = parentAlpha * view.alpha
            guard !view.isHidden, alpha > 0.001 else { return }
            if let image = view as? UIImageView, image.window != nil, image.image != nil,
               image.bounds.width > 0, image.bounds.height > 0 {
                let area = image.bounds.width * image.bounds.height
                if alpha > bestAlpha || (alpha == bestAlpha && area > bestArea) {
                    best = image
                    bestAlpha = alpha
                    bestArea = area
                }
            }
            view.subviews.reversed().forEach { visit($0, parentAlpha: alpha) }
        }
        // Ignore the viewer-owned container alpha, while respecting loader-layer visibility.
        source.subviews.reversed().forEach { visit($0, parentAlpha: 1) }
        return best
    }
}
