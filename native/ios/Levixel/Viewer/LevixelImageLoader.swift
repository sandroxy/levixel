import Foundation
import UIKit
#if canImport(SDWebImage)
import SDWebImage
#endif

enum LevixelDecodedImageCache {
    private struct Entry {
        let image: UIImage
        let cost: Int
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [URL: Entry] = [:]
        private var recency: [URL] = []
        private var totalCost = 0
        private let totalCostLimit = 96 * 1024 * 1024
        private let countLimit = 16

        func image(for url: URL) -> UIImage? {
            lock.lock()
            defer { lock.unlock() }

            guard let entry = entries[url] else { return nil }
            touch(url)
            return entry.image
        }

        func store(_ image: UIImage, for url: URL, cost: Int) {
            lock.lock()
            defer { lock.unlock() }

            if let existing = entries.removeValue(forKey: url) {
                totalCost -= existing.cost
            }
            recency.removeAll { $0 == url }

            entries[url] = Entry(image: image, cost: cost)
            recency.append(url)
            totalCost += cost

            while entries.count > countLimit || (totalCost > totalCostLimit && entries.count > 1) {
                guard let oldestURL = recency.first else { break }
                recency.removeFirst()
                if let removed = entries.removeValue(forKey: oldestURL) {
                    totalCost -= removed.cost
                }
            }
        }

        private func touch(_ url: URL) {
            recency.removeAll { $0 == url }
            recency.append(url)
        }
    }

    private static let store = Store()

    static func image(for url: URL) -> UIImage? {
        store.image(for: url)
    }

    static func store(_ image: UIImage, for url: URL) {
        let pixelCost: Int
        if let cgImage = image.cgImage {
            pixelCost = cgImage.bytesPerRow * cgImage.height
        } else {
            let pixelWidth = max(Int(image.size.width * image.scale), 1)
            let pixelHeight = max(Int(image.size.height * image.scale), 1)
            pixelCost = pixelWidth * pixelHeight * 4
        }
        store.store(image, for: url, cost: pixelCost)
    }
}

private final class LevixelURLSessionImageLoaderStorage: @unchecked Sendable {
    static let shared = LevixelURLSessionImageLoaderStorage()

    let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "com.sandrox.levixel.images"
        )
        configuration.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: configuration)
    }
}

public protocol LevixelImageLoading {
    func loadImage(
        _ url: URL,
        placeholder: UIImage?,
        imageView: UIImageView,
        completion: @escaping (_ image: UIImage?) -> Void
    )
}

public struct LevixelURLSessionImageLoader: LevixelImageLoading {
    public init() {}

    public func loadImage(
        _ url: URL,
        placeholder: UIImage?,
        imageView: UIImageView,
        completion: @escaping (UIImage?) -> Void
    ) {
        if let placeholder = placeholder {
            imageView.image = placeholder
        }

        LevixelURLSessionImageLoaderStorage.shared.session.dataTask(with: url) { data, _, _ in
            guard let data, let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            DispatchQueue.main.async {
                imageView.image = image
                completion(image)
            }
        }.resume()
    }
}

#if canImport(SDWebImage)
struct LevixelSDWebImageLoader: LevixelImageLoading {
    func loadImage(
        _ url: URL,
        placeholder: UIImage?,
        imageView: UIImageView,
        completion: @escaping (UIImage?) -> Void
    ) {
        imageView.sd_setImage(
            with: url,
            placeholderImage: placeholder,
            options: [],
            progress: nil
        ) { image, _, _, _ in
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
#endif

public enum LevixelImageLoaderFactory {
    public static func makeDefault() -> LevixelImageLoading {
        #if canImport(SDWebImage)
        return LevixelSDWebImageLoader()
        #else
        return LevixelURLSessionImageLoader()
        #endif
    }
}
