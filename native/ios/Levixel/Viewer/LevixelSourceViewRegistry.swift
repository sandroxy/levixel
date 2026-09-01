import UIKit

final class LevixelSourceViewRegistry {
    static let shared = LevixelSourceViewRegistry()

    private enum AnchorKey: Hashable {
        case index(Int)
        case itemIdentifier(String)
    }

    private final class WeakImageView {
        weak var value: UIImageView?

        init(_ value: UIImageView) {
            self.value = value
        }
    }

    private var anchors: [String: [AnchorKey: WeakImageView]] = [:]

    private init() {}

    func register(_ imageView: UIImageView, galleryId: String, index: Int) {
        register(imageView, galleryId: galleryId, key: .index(index))
    }

    func register(_ imageView: UIImageView, galleryId: String, itemIdentifier: String) {
        register(imageView, galleryId: galleryId, key: .itemIdentifier(itemIdentifier))
    }

    private func register(_ imageView: UIImageView, galleryId: String, key: AnchorKey) {
        cleanup()
        var galleryAnchors = anchors[galleryId] ?? [:]
        galleryAnchors[key] = WeakImageView(imageView)
        anchors[galleryId] = galleryAnchors
    }

    func unregister(_ imageView: UIImageView, galleryId: String?, index: Int?) {
        cleanup()
        if let galleryId = galleryId {
            remove(imageView, from: galleryId, key: index.map(AnchorKey.index))
        } else {
            for galleryId in Array(anchors.keys) {
                remove(imageView, from: galleryId, key: nil)
            }
        }
        cleanup()
    }

    func unregister(_ imageView: UIImageView, galleryId: String?, itemIdentifier: String?) {
        cleanup()
        if let galleryId = galleryId {
            remove(
                imageView,
                from: galleryId,
                key: itemIdentifier.map(AnchorKey.itemIdentifier)
            )
        } else {
            for galleryId in Array(anchors.keys) {
                remove(imageView, from: galleryId, key: nil)
            }
        }
        cleanup()
    }

    func sourceView(for galleryId: String, index: Int) -> UIImageView? {
        sourceView(for: galleryId, key: .index(index))
    }

    func sourceView(for galleryId: String, itemIdentifier: String) -> UIImageView? {
        sourceView(for: galleryId, key: .itemIdentifier(itemIdentifier))
    }

    private func sourceView(for galleryId: String, key: AnchorKey) -> UIImageView? {
        cleanup()
        guard
            let imageView = anchors[galleryId]?[key]?.value,
            imageView.levixelHasVisibleSourceHierarchy(),
            imageView.levixelClippingFrameInWindow() != nil
        else {
            return nil
        }

        return imageView
    }

    private func remove(_ imageView: UIImageView, from galleryId: String, key: AnchorKey?) {
        guard var galleryAnchors = anchors[galleryId] else { return }

        if let key = key {
            if let registeredView = galleryAnchors[key]?.value, registeredView === imageView {
                galleryAnchors.removeValue(forKey: key)
            }
        } else {
            galleryAnchors = galleryAnchors.filter { _, weakImageView in
                guard let registeredView = weakImageView.value else { return false }
                return registeredView !== imageView
            }
        }

        anchors[galleryId] = galleryAnchors.isEmpty ? nil : galleryAnchors
    }

    private func cleanup() {
        anchors = anchors.compactMapValues { galleryAnchors in
            let activeAnchors = galleryAnchors.filter { _, weakImageView in
                weakImageView.value != nil
            }
            return activeAnchors.isEmpty ? nil : activeAnchors
        }
    }
}
