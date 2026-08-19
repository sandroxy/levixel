import UIKit

final class LevixelSourceViewRegistry {
    static let shared = LevixelSourceViewRegistry()

    private final class WeakImageView {
        weak var value: UIImageView?

        init(_ value: UIImageView) {
            self.value = value
        }
    }

    private var anchors: [String: [Int: WeakImageView]] = [:]

    private init() {}

    func register(_ imageView: UIImageView, galleryId: String, index: Int) {
        cleanup()
        var galleryAnchors = anchors[galleryId] ?? [:]
        galleryAnchors[index] = WeakImageView(imageView)
        anchors[galleryId] = galleryAnchors
    }

    func unregister(_ imageView: UIImageView, galleryId: String?, index: Int?) {
        cleanup()
        if let galleryId = galleryId {
            remove(imageView, from: galleryId, index: index)
        } else {
            for galleryId in Array(anchors.keys) {
                remove(imageView, from: galleryId, index: nil)
            }
        }
        cleanup()
    }

    func sourceView(for galleryId: String, index: Int) -> UIImageView? {
        cleanup()
        guard
            let imageView = anchors[galleryId]?[index]?.value,
            let window = imageView.window,
            !imageView.isHidden
        else {
            return nil
        }

        let frameInWindow = imageView.frameInWindow()
        guard !frameInWindow.isEmpty, frameInWindow.intersects(window.bounds) else {
            return nil
        }

        return imageView
    }

    private func remove(_ imageView: UIImageView, from galleryId: String, index: Int?) {
        guard var galleryAnchors = anchors[galleryId] else { return }

        if let index = index {
            if let registeredView = galleryAnchors[index]?.value, registeredView === imageView {
                galleryAnchors.removeValue(forKey: index)
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
