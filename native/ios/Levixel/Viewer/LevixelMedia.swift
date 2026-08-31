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

/// An optional data-source capability for keeping transition anchors stable when items move.
/// Identifiers must be non-empty and unique for the lifetime of a viewer session.
public protocol LevixelIdentifiedDataSource: LevixelDataSource {
    func itemIdentifier(at index: Int) -> String?
}

public final class LevixelArrayDataSource: LevixelIdentifiedDataSource {
    private let items: [LevixelMediaItem]
    private let itemIdentifiers: [String]?

    public init(items: [LevixelMediaItem]) {
        self.items = items
        itemIdentifiers = nil
    }

    public init(items: [LevixelMediaItem], itemIdentifiers: [String]) {
        precondition(
            items.count == itemIdentifiers.count,
            "Levixel itemIdentifiers must contain one identifier for each media item."
        )
        precondition(
            itemIdentifiers.allSatisfy { $0.isEmpty == false },
            "Levixel itemIdentifiers must be non-empty."
        )
        precondition(
            Set(itemIdentifiers).count == itemIdentifiers.count,
            "Levixel itemIdentifiers must be unique."
        )
        self.items = items
        self.itemIdentifiers = itemIdentifiers
    }

    public func numberOfItems() -> Int {
        items.count
    }

    public func item(at index: Int) -> LevixelMediaItem {
        items[index]
    }

    public func itemIdentifier(at index: Int) -> String? {
        itemIdentifiers?[index]
    }
}
