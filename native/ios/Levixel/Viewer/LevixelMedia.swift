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
    private let itemIdentifiers: [String?]?

    public init(items: [LevixelMediaItem]) {
        self.items = items
        itemIdentifiers = nil
    }

    public init(items: [LevixelMediaItem], itemIdentifiers: [String]) {
        precondition(
            items.count == itemIdentifiers.count,
            "Levixel itemIdentifiers must contain one identifier for each media item."
        )
        Self.validateIdentifiers(itemIdentifiers)
        self.items = items
        self.itemIdentifiers = itemIdentifiers
    }

    init(snapshotting dataSource: LevixelDataSource) {
        let count = dataSource.numberOfItems()
        items = (0..<count).map { dataSource.item(at: $0) }
        if let identified = dataSource as? LevixelIdentifiedDataSource {
            let identifiers = (0..<count).map { identified.itemIdentifier(at: $0) }
            Self.validateIdentifiers(identifiers.compactMap { $0 })
            itemIdentifiers = identifiers
        } else {
            itemIdentifiers = nil
        }
    }

    private static func validateIdentifiers(_ identifiers: [String]) {
        precondition(
            identifiers.allSatisfy { $0.isEmpty == false },
            "Levixel itemIdentifiers must be non-empty."
        )
        precondition(
            Set(identifiers).count == identifiers.count,
            "Levixel itemIdentifiers must be unique."
        )
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
