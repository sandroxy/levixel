import UIKit

public enum LevixelMediaItem {
    case image(UIImage?)
    case imageURL(URL, thumbnailURL: URL? = nil, placeholder: UIImage?)
    case video(url: URL, poster: URL?)
}

public protocol LevixelDataSource: AnyObject {
    func numberOfItems() -> Int
    func item(at index: Int) -> LevixelMediaItem
}

public final class LevixelArrayDataSource: LevixelDataSource {
    private let items: [LevixelMediaItem]

    public init(items: [LevixelMediaItem]) {
        self.items = items
    }

    public func numberOfItems() -> Int {
        items.count
    }

    public func item(at index: Int) -> LevixelMediaItem {
        items[index]
    }
}
