import ExpoModulesCore
import Levixel
import UIKit

enum LevixelTheme: String, Enumerable {
    case dark
    case light

    var viewerTheme: LevixelViewerTheme {
        switch self {
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

final class LevixelView: ExpoView {
    var items: [[String: Any]] = []
    var initialIndex = 0
    var galleryId = ""
    var theme: LevixelTheme = .dark

    let onIndexChange = EventDispatcher()

    private weak var configuredImageView: UIImageView?

    deinit {
        configuredImageView?.removeLevixelViewerInteraction()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            configuredImageView?.removeLevixelViewerInteraction()
            configuredImageView = nil
        } else {
            configureSourceView()
        }
    }

    #if !RCT_NEW_ARCH_ENABLED
    override func insertReactSubview(_ subview: UIView!, at atIndex: Int) {
        super.insertReactSubview(subview, at: atIndex)
        configureSourceView()
    }
    #endif

    #if RCT_NEW_ARCH_ENABLED
    override func unmountChildComponentView(_ childComponentView: UIView, index: Int) {
        configuredImageView?.removeLevixelViewerInteraction()
        configuredImageView = nil
        super.unmountChildComponentView(childComponentView, index: index)
    }
    #endif

    func configureSourceView() {
        guard window != nil, let imageView = findImageView() else { return }
        let mediaItems = buildMediaItems()
        guard !mediaItems.isEmpty else { return }

        if let configuredImageView, configuredImageView !== imageView {
            configuredImageView.removeLevixelViewerInteraction()
        }
        self.configuredImageView = imageView

        let safeIndex = min(max(0, initialIndex), mediaItems.count - 1)
        var configuration = LevixelViewerConfiguration(theme: theme.viewerTheme)
        configuration.onIndexChange = { [weak self] index in
            self?.onIndexChange(["currentIndex": index])
        }
        imageView.setupLevixelViewer(
            dataSource: LevixelArrayDataSource(items: mediaItems),
            initialIndex: safeIndex,
            configuration: configuration,
            galleryId: galleryId.isEmpty ? nil : galleryId
        )
    }

    private func buildMediaItems() -> [LevixelMediaItem] {
        items.compactMap { value in
            guard
                let type = value["type"] as? String,
                let sourceValue = value["url"] as? String,
                let sourceURL = makeURL(sourceValue)
            else {
                return nil
            }

            if type == "video" {
                let posterValue = value["posterUrl"] as? String ?? value["thumbnailUrl"] as? String
                return .video(url: sourceURL, poster: posterValue.flatMap(makeURL))
            }

            let thumbnailURL = (value["thumbnailUrl"] as? String).flatMap(makeURL)
            return .imageURL(sourceURL, thumbnailURL: thumbnailURL, placeholder: nil)
        }
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
