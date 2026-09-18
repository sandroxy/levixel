import UIKit

/// A stable source container whose image may be replaced by an asynchronous loader.
/// Use on the main thread. The provider receives the weakly held container; it must not retain it.
public final class LevixelSourceRegistration {
    public let sourceIdentifier: String
    private let entry: LevixelSourceViewRegistry.Entry

    public init(view: UIView, sourceIdentifier: String, imageViewProvider: @escaping (UIView) -> UIImageView?) {
        precondition(!sourceIdentifier.isEmpty)
        self.sourceIdentifier = sourceIdentifier
        entry = LevixelSourceViewRegistry.Entry(view: view, identifier: sourceIdentifier, imageViewProvider: imageViewProvider)
    }

    public func register(galleryId: String, itemIdentifier: String, cornerRadius: CGFloat) {
        precondition(Thread.isMainThread)
        precondition(!galleryId.isEmpty && !itemIdentifier.isEmpty)
        precondition(cornerRadius.isFinite && cornerRadius >= 0)
        entry.cornerRadius = cornerRadius
        LevixelSourceViewRegistry.shared.register(entry, galleryId: galleryId, key: .itemIdentifier(itemIdentifier))
    }

    public func unregister() {
        precondition(Thread.isMainThread)
        LevixelSourceViewRegistry.shared.unregister(entry)
    }

    deinit { LevixelSourceViewRegistry.shared.unregister(entry) }
}

final class LevixelSourceViewRegistry {
    static let shared = LevixelSourceViewRegistry()

    enum AnchorKey: Hashable {
        case index(Int)
        case itemIdentifier(String)
    }

    final class Entry {
        weak var view: UIView?
        let identifier: String
        var cornerRadius: CGFloat?
        private let imageViewProvider: (UIView) -> UIImageView?

        init(view: UIView, identifier: String, imageViewProvider: @escaping (UIView) -> UIImageView?) {
            self.view = view
            self.identifier = identifier
            self.imageViewProvider = imageViewProvider
        }

        var imageView: UIImageView? {
            guard let view, let image = imageViewProvider(view), image === view || image.isDescendant(of: view),
                  image.levixelHasVisibleSourceHierarchy(), image.levixelClippingFrameInWindow() != nil else { return nil }
            return image
        }

        func isEligible(in window: UIWindow?) -> Bool {
            guard let view, view.window != nil,
                  window == nil || view.window === window,
                  view.levixelHasVisibleSourceHierarchy(), view.levixelClippingFrameInWindow() != nil else { return false }
            // Native/UniApp synthetic UIImageView anchors may intentionally be transparent.
            if !(view is UIImageView) && view.alpha <= 0.01 && !LevixelSourceViewRegistry.shared.isHiddenByViewer(view) { return false }
            return true
        }
    }

    final class Selection {
        private let galleryId: String?
        private let key: AnchorKey?
        private weak var window: UIWindow?
        private var selected: Entry?
        private let initialSourceIdentifier: String?
        private var allowsFallback: Bool
        private let legacyFallback: Entry?

        init(galleryId: String?, key: AnchorKey?, window: UIWindow?, sourceIdentifier: String?, fallbackView: UIImageView? = nil) {
            self.galleryId = galleryId
            self.key = key
            self.window = window
            initialSourceIdentifier = sourceIdentifier
            allowsFallback = sourceIdentifier == nil
            legacyFallback = fallbackView.map { Entry(view: $0, identifier: Self.nativeIdentifier($0), imageViewProvider: { $0 as? UIImageView }) }
        }

        static func nativeIdentifier(_ view: UIImageView) -> String {
            LevixelSourceViewRegistry.shared.nativeIdentifier(for: view)
        }

        var imageView: UIImageView? {
            LevixelSourceViewRegistry.shared.cleanup()
            let entry = resolve()
            LevixelSourceViewRegistry.shared.updateHiddenSources()
            return entry?.imageView
        }

        var cornerRadius: CGFloat? { selected?.cornerRadius ?? selected?.imageView?.levixelConfiguredSourceCornerRadius }

        func allowFallback() {
            allowsFallback = true
            LevixelSourceViewRegistry.shared.updateHiddenSources()
        }

        fileprivate func resolve() -> Entry? {
            let entries: [Entry]
            if let galleryId, let key { entries = LevixelSourceViewRegistry.shared.anchors[galleryId]?[key] ?? [] }
            else { entries = [] }
            if let selected, (entries.contains(where: { $0 === selected }) || selected === legacyFallback), selected.isEligible(in: window) {
                return selected
            }
            selected = nil
            if allowsFallback {
                selected = entries.first { $0.isEligible(in: window) }
            } else {
                selected = entries.first { $0.identifier == initialSourceIdentifier && $0.isEligible(in: window) }
            }
            if selected == nil, let legacyFallback, legacyFallback.isEligible(in: window) { selected = legacyFallback }
            return selected
        }
    }

    final class HiddenSource {
        fileprivate let selection: Selection
        fileprivate weak var view: UIView?
        private var active = true

        fileprivate init(_ selection: Selection) { self.selection = selection }

        func close() {
            guard active else { return }
            active = false
            LevixelSourceViewRegistry.shared.hiddenSources.remove(self)
            LevixelSourceViewRegistry.shared.releaseHiddenView(self)
        }

        deinit { close() }
    }

    private final class HiddenView {
        weak var view: UIView?
        let previousAlpha: CGFloat
        var owners = 0
        init(_ view: UIView) { self.view = view; previousAlpha = view.alpha }
    }

    private var anchors: [String: [AnchorKey: [Entry]]] = [:]
    private let nativeIdentifiers = NSMapTable<UIImageView, NSString>.weakToStrongObjects()
    private let hiddenSources = NSHashTable<HiddenSource>.weakObjects()
    private var hiddenViews: [ObjectIdentifier: HiddenView] = [:]

    private init() {}

    private func nativeIdentifier(for view: UIImageView) -> String {
        if let identifier = nativeIdentifiers.object(forKey: view) { return identifier as String }
        let identifier = "native-\(UUID().uuidString)"
        nativeIdentifiers.setObject(identifier as NSString, forKey: view)
        return identifier
    }

    func register(_ imageView: UIImageView, galleryId: String, index: Int) {
        register(imageView, galleryId: galleryId, key: .index(index))
    }

    func register(_ imageView: UIImageView, galleryId: String, itemIdentifier: String) {
        register(imageView, galleryId: galleryId, key: .itemIdentifier(itemIdentifier))
    }

    private func register(_ imageView: UIImageView, galleryId: String, key: AnchorKey) {
        let existing = anchors[galleryId]?[key]?.first { $0.view === imageView }
        let entry = existing ?? Entry(view: imageView, identifier: Selection.nativeIdentifier(imageView), imageViewProvider: { $0 as? UIImageView })
        register(entry, galleryId: galleryId, key: key)
    }

    func register(_ entry: Entry, galleryId: String, key: AnchorKey) {
        cleanup()
        if anchors[galleryId]?[key]?.contains(where: { $0 === entry }) == true {
            updateHiddenSources()
            return
        }
        precondition(!(anchors[galleryId]?[key]?.contains { $0.identifier == entry.identifier && $0.view !== entry.view } ?? false),
                     "Levixel source identifier is already registered by another view.")
        removeEntries { $0 === entry }
        var gallery = anchors[galleryId] ?? [:]
        gallery[key, default: []].append(entry)
        anchors[galleryId] = gallery
        updateHiddenSources()
    }

    func unregister(_ entry: Entry) {
        removeEntries { $0 === entry }
        updateHiddenSources()
    }

    func unregister(_ imageView: UIImageView, galleryId: String?, index: Int?) {
        remove(imageView, galleryId: galleryId, key: index.map(AnchorKey.index))
    }

    func unregister(_ imageView: UIImageView, galleryId: String?, itemIdentifier: String?) {
        remove(imageView, galleryId: galleryId, key: itemIdentifier.map(AnchorKey.itemIdentifier))
    }

    func sourceView(for galleryId: String, index: Int) -> UIImageView? {
        selection(galleryId: galleryId, key: .index(index)).imageView
    }

    func sourceView(for galleryId: String, itemIdentifier: String) -> UIImageView? {
        selection(galleryId: galleryId, key: .itemIdentifier(itemIdentifier)).imageView
    }

    func selection(galleryId: String?, key: AnchorKey?, window: UIWindow? = nil,
                   sourceIdentifier: String? = nil, fallbackView: UIImageView? = nil) -> Selection {
        Selection(galleryId: galleryId, key: key, window: window, sourceIdentifier: sourceIdentifier, fallbackView: fallbackView)
    }

    func hide(_ selection: Selection) -> HiddenSource {
        let source = HiddenSource(selection)
        hiddenSources.add(source)
        updateHiddenSources()
        return source
    }

    func isHiddenByViewer(_ view: UIView) -> Bool { hiddenViews[ObjectIdentifier(view)]?.view === view }

    private func remove(_ imageView: UIImageView, galleryId: String?, key: AnchorKey?) {
        for id in Array(anchors.keys) where galleryId == nil || id == galleryId {
            guard var gallery = anchors[id] else { continue }
            for anchor in Array(gallery.keys) where key == nil || anchor == key {
                gallery[anchor]?.removeAll { $0.view == nil || $0.view === imageView }
                if gallery[anchor]?.isEmpty == true { gallery[anchor] = nil }
            }
            anchors[id] = gallery.isEmpty ? nil : gallery
        }
        updateHiddenSources()
    }

    private func removeEntries(where predicate: (Entry) -> Bool) {
        for id in Array(anchors.keys) {
            guard var gallery = anchors[id] else { continue }
            for key in Array(gallery.keys) {
                gallery[key]?.removeAll(where: predicate)
                if gallery[key]?.isEmpty == true { gallery[key] = nil }
            }
            anchors[id] = gallery.isEmpty ? nil : gallery
        }
    }

    private func cleanup() {
        removeEntries { $0.view == nil }
        hiddenViews = hiddenViews.filter { $0.value.view != nil }
        updateHiddenSources()
    }

    private func updateHiddenSources() {
        let targets = hiddenSources.allObjects.map { ($0, $0.selection.resolve()?.view) }
        // Release before acquiring, so a recycled container never saves another owner's zero alpha.
        for (source, target) in targets where source.view !== target { releaseHiddenView(source) }
        for (source, target) in targets {
            guard let target, source.view !== target else { continue }
            let id = ObjectIdentifier(target)
            let hidden = hiddenViews[id].flatMap { $0.view === target ? $0 : nil } ?? HiddenView(target)
            hidden.owners += 1
            hiddenViews[id] = hidden
            source.view = target
            target.alpha = 0
        }
    }

    private func releaseHiddenView(_ source: HiddenSource) {
        guard let view = source.view else { return }
        source.view = nil
        let id = ObjectIdentifier(view)
        guard let hidden = hiddenViews[id] else { return }
        hidden.owners -= 1
        if hidden.owners == 0 { hiddenViews[id] = nil; view.alpha = hidden.previousAlpha }
    }
}
