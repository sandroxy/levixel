import Foundation
import UIKit
#if canImport(SDWebImage)
import SDWebImage
#endif

enum LevixelDecodedImageCache {
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 80
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
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
        cache.setObject(image, forKey: url as NSURL, cost: pixelCost)
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

        DispatchQueue.global(qos: .background).async {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                completion(nil)
                return
            }

            DispatchQueue.main.async {
                imageView.image = image
                completion(image)
            }
        }
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
