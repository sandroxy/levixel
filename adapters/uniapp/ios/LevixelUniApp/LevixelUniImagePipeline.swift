import Foundation
import Levixel
import UIKit

final class LevixelUniImagePipeline: LevixelImageLoading {
    private let cache = NSCache<NSURL, UIImage>()
    private var pending: [URL: [(UIImage?) -> Void]] = [:]

    func immediateImage(for url: URL?) -> UIImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let image: UIImage?
        if url.isFileURL {
            image = UIImage(contentsOfFile: url.path)
                ?? (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
        } else if url.scheme?.lowercased() == "data" {
            image = imageFromDataURL(url)
        } else {
            image = URLCache.shared
                .cachedResponse(for: URLRequest(url: url))
                .flatMap { UIImage(data: $0.data) }
        }

        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        return image
    }

    func fetch(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        precondition(Thread.isMainThread)
        if let image = immediateImage(for: url) {
            completion(image)
            return
        }

        if pending[url] != nil {
            pending[url]?.append(completion)
            return
        }
        pending[url] = [completion]

        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            finish(url: url, image: nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            DispatchQueue.main.async {
                self?.finish(url: url, image: image)
            }
        }.resume()
    }

    func loadImage(
        _ url: URL,
        placeholder: UIImage?,
        imageView: UIImageView,
        completion: @escaping (UIImage?) -> Void
    ) {
        if let placeholder {
            imageView.image = placeholder
        }
        let load: () -> Void = { [weak self] in
            self?.fetch(url) { image in
                if let image {
                    imageView.image = image
                }
                completion(image)
            }
        }
        if Thread.isMainThread {
            load()
        } else {
            DispatchQueue.main.async(execute: load)
        }
    }

    private func finish(url: URL, image: UIImage?) {
        precondition(Thread.isMainThread)
        if let image {
            cache.setObject(image, forKey: url as NSURL)
        }
        let completions = pending.removeValue(forKey: url) ?? []
        completions.forEach { $0(image) }
    }

    private func imageFromDataURL(_ url: URL) -> UIImage? {
        let value = url.absoluteString
        guard let commaIndex = value.firstIndex(of: ",") else { return nil }
        let metadata = value[..<commaIndex]
        let payload = String(value[value.index(after: commaIndex)...])
        let data: Data?
        if metadata.lowercased().contains(";base64") {
            data = Data(base64Encoded: payload)
        } else {
            data = payload.removingPercentEncoding?.data(using: .utf8)
        }
        return data.flatMap(UIImage.init(data:))
    }
}
