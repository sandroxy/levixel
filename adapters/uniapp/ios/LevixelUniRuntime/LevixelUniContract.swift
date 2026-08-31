import CoreFoundation
import Foundation
import Levixel
import UIKit

enum LevixelUniObjectFit: String {
    case contain
    case cover
    case fill

    var contentMode: UIView.ContentMode {
        switch self {
        case .contain:
            return .scaleAspectFit
        case .cover:
            return .scaleAspectFill
        case .fill:
            return .scaleToFill
        }
    }
}

enum LevixelUniCoordinateSpace: String {
    case screen
    case viewport
}

struct LevixelUniSourceHint {
    let rect: CGRect
    let imageSize: CGSize?
    let objectFit: LevixelUniObjectFit
    let coordinateSpace: LevixelUniCoordinateSpace
    let rectScale: CGFloat
    let cornerRadius: CGFloat
}

struct LevixelUniItem {
    enum MediaType: String {
        case image
        case video
    }

    let id: String
    let type: MediaType
    let url: URL
    let thumbnailURL: URL?
    let posterURL: URL?
    let width: CGFloat?
    let height: CGFloat?
    let alt: String?

    var transitionURL: URL? {
        switch type {
        case .image:
            return thumbnailURL ?? url
        case .video:
            return posterURL ?? thumbnailURL
        }
    }

    func nativeItem(placeholder: UIImage?) -> LevixelMediaItem {
        switch type {
        case .image:
            return .imageURL(url, thumbnailURL: thumbnailURL, placeholder: placeholder)
        case .video:
            return .video(url: url, poster: posterURL ?? thumbnailURL)
        }
    }
}

struct LevixelUniOpenRequest {
    let items: [LevixelUniItem]
    let sourceHints: [LevixelUniSourceHint?]
    let initialIndex: Int
    let theme: LevixelViewerTheme
    let hidesHTMLSource: Bool
}

struct LevixelUniContractError: Error {
    let code: String
    let path: String
    let detail: String

    var message: String {
        "\(path) \(detail)"
    }
}

enum LevixelUniContract {
    private static let openKeys: Set<String> = [
        "items",
        "index",
        "theme",
        "sourceHints",
        "sourceVisibility",
        "counter",
        "closeButton",
    ]
    private static let itemKeys: Set<String> = [
        "id",
        "type",
        "url",
        "thumbnailUrl",
        "posterUrl",
        "width",
        "height",
        "alt",
    ]
    private static let sourceHintKeys: Set<String> = [
        "rect",
        "imageSize",
        "objectFit",
        "coordinateSpace",
        "rectScale",
        "cornerRadius",
    ]
    private static let rectKeys: Set<String> = ["left", "top", "width", "height"]
    private static let sizeKeys: Set<String> = ["width", "height"]

    static func parseOpenRequest(_ rawOptions: Any?) throws -> LevixelUniOpenRequest {
        let options = try requireObject(rawOptions, path: "$")
        try rejectUnknownKeys(options, allowed: openKeys, path: "$")

        guard let rawItems = options["items"] as? [Any] else {
            throw failure("INVALID_TYPE", "$.items", "must be an array")
        }
        guard rawItems.isEmpty == false else {
            throw failure("INVALID_VALUE", "$.items", "must contain at least one item")
        }

        let items = try rawItems.enumerated().map { index, rawItem in
            try parseItem(rawItem, path: "$.items[\(index)]")
        }
        var itemIds = Set<String>()
        for (index, item) in items.enumerated() where itemIds.insert(item.id).inserted == false {
            throw failure(
                "INVALID_VALUE",
                "$.items[\(index)].id",
                "must be unique within $.items"
            )
        }
        let initialIndex = try optionalInteger(options["index"], fallback: 0, path: "$.index")
        guard items.indices.contains(initialIndex) else {
            throw failure("OUT_OF_RANGE", "$.index", "must reference an item in $.items")
        }

        let themeValue = try optionalEnum(
            options["theme"],
            fallback: "dark",
            path: "$.theme",
            values: ["dark", "light"]
        )
        let sourceVisibility = try optionalEnum(
            options["sourceVisibility"],
            fallback: "visible",
            path: "$.sourceVisibility",
            values: ["hidden", "visible"]
        )
        let counter = try optionalBoolean(options["counter"], fallback: false, path: "$.counter")
        let closeButton = try optionalBoolean(
            options["closeButton"],
            fallback: false,
            path: "$.closeButton"
        )
        guard counter == false else {
            throw failure(
                "UNSUPPORTED_VALUE",
                "$.counter",
                "Levixel does not render a counter overlay"
            )
        }
        guard closeButton == false else {
            throw failure(
                "UNSUPPORTED_VALUE",
                "$.closeButton",
                "Levixel closes by gesture or tap"
            )
        }

        return LevixelUniOpenRequest(
            items: items,
            sourceHints: try parseSourceHints(options["sourceHints"], itemCount: items.count),
            initialIndex: initialIndex,
            theme: themeValue == "light" ? .light : .dark,
            hidesHTMLSource: sourceVisibility == "hidden"
        )
    }

    static func validateCloseRequest(_ rawOptions: Any?) throws {
        let options = try requireObject(rawOptions, path: "$")
        try rejectUnknownKeys(options, allowed: [], path: "$")
    }

    private static func parseItem(_ rawItem: Any, path: String) throws -> LevixelUniItem {
        let item = try requireObject(rawItem, path: path)
        try rejectUnknownKeys(item, allowed: itemKeys, path: path)

        let id = try requireString(item["id"], path: "\(path).id")
        let typeValue = try requireEnum(
            item["type"],
            path: "\(path).type",
            values: ["image", "video"]
        )
        let url = try requireURL(item["url"], path: "\(path).url")
        let thumbnailURL = try optionalURL(item["thumbnailUrl"], path: "\(path).thumbnailUrl")
        let posterURL = try optionalURL(item["posterUrl"], path: "\(path).posterUrl")
        let width = try optionalPositiveNumber(item["width"], path: "\(path).width")
        let height = try optionalPositiveNumber(item["height"], path: "\(path).height")
        let alt = try optionalString(item["alt"], path: "\(path).alt")

        return LevixelUniItem(
            id: id,
            type: typeValue == "video" ? .video : .image,
            url: url,
            thumbnailURL: thumbnailURL,
            posterURL: posterURL,
            width: width,
            height: height,
            alt: alt
        )
    }

    private static func parseSourceHints(
        _ rawHints: Any?,
        itemCount: Int
    ) throws -> [LevixelUniSourceHint?] {
        guard let rawHints else {
            return Array(repeating: nil, count: itemCount)
        }
        guard let values = rawHints as? [Any] else {
            throw failure("INVALID_TYPE", "$.sourceHints", "must be an array")
        }
        guard values.count == itemCount else {
            throw failure(
                "INVALID_VALUE",
                "$.sourceHints",
                "must contain one entry for each media item"
            )
        }

        return try values.enumerated().map { index, value in
            if value is NSNull {
                return nil
            }
            return try parseSourceHint(value, path: "$.sourceHints[\(index)]")
        }
    }

    private static func parseSourceHint(_ rawHint: Any, path: String) throws -> LevixelUniSourceHint {
        let hint = try requireObject(rawHint, path: path)
        try rejectUnknownKeys(hint, allowed: sourceHintKeys, path: path)

        let rectValue = try requireObject(hint["rect"], path: "\(path).rect")
        try rejectUnknownKeys(rectValue, allowed: rectKeys, path: "\(path).rect")
        let left = try requireFiniteNumber(rectValue["left"], path: "\(path).rect.left")
        let top = try requireFiniteNumber(rectValue["top"], path: "\(path).rect.top")
        let width = try requirePositiveNumber(rectValue["width"], path: "\(path).rect.width")
        let height = try requirePositiveNumber(rectValue["height"], path: "\(path).rect.height")

        let imageSize: CGSize?
        if let rawImageSize = hint["imageSize"] {
            let sizeValue = try requireObject(rawImageSize, path: "\(path).imageSize")
            try rejectUnknownKeys(sizeValue, allowed: sizeKeys, path: "\(path).imageSize")
            imageSize = CGSize(
                width: try requirePositiveNumber(
                    sizeValue["width"],
                    path: "\(path).imageSize.width"
                ),
                height: try requirePositiveNumber(
                    sizeValue["height"],
                    path: "\(path).imageSize.height"
                )
            )
        } else {
            imageSize = nil
        }

        let objectFitValue = try requireEnum(
            hint["objectFit"],
            path: "\(path).objectFit",
            values: ["contain", "cover", "fill"]
        )
        let coordinateSpaceValue = try requireEnum(
            hint["coordinateSpace"],
            path: "\(path).coordinateSpace",
            values: ["screen", "viewport"]
        )
        let rectScale = try optionalPositiveNumber(
            hint["rectScale"],
            path: "\(path).rectScale"
        ) ?? 1
        let cornerRadius = try optionalNonNegativeNumber(
            hint["cornerRadius"],
            fallback: 0,
            path: "\(path).cornerRadius"
        )

        return LevixelUniSourceHint(
            rect: CGRect(x: left, y: top, width: width, height: height),
            imageSize: imageSize,
            objectFit: LevixelUniObjectFit(rawValue: objectFitValue)!,
            coordinateSpace: LevixelUniCoordinateSpace(rawValue: coordinateSpaceValue)!,
            rectScale: rectScale,
            cornerRadius: cornerRadius
        )
    }

    private static func requireObject(_ value: Any?, path: String) throws -> [String: Any] {
        guard let value, value is NSNull == false else {
            throw failure("INVALID_TYPE", path, "must be an object")
        }
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let dictionary = value as? NSDictionary else {
            throw failure("INVALID_TYPE", path, "must be an object")
        }

        var result: [String: Any] = [:]
        for (rawKey, rawValue) in dictionary {
            guard let key = rawKey as? String else {
                throw failure("INVALID_TYPE", path, "must use string property names")
            }
            result[key] = rawValue
        }
        return result
    }

    private static func rejectUnknownKeys(
        _ object: [String: Any],
        allowed: Set<String>,
        path: String
    ) throws {
        for key in object.keys where allowed.contains(key) == false {
            throw failure("UNKNOWN_FIELD", "\(path).\(key)", "is not part of the Levixel contract")
        }
    }

    private static func requireString(_ value: Any?, path: String) throws -> String {
        guard let string = value as? String, string.isEmpty == false else {
            throw failure("INVALID_TYPE", path, "must be a non-empty string")
        }
        return string
    }

    private static func optionalString(_ value: Any?, path: String) throws -> String? {
        guard let value else { return nil }
        return try requireString(value, path: path)
    }

    private static func requireURL(_ value: Any?, path: String) throws -> URL {
        let string = try requireString(value, path: path)
        if string.hasPrefix("//"), let url = URL(string: "https:\(string)") {
            return url
        }
        if let url = URL(string: string), url.scheme?.isEmpty == false {
            return url
        }
        return URL(fileURLWithPath: string)
    }

    private static func optionalURL(_ value: Any?, path: String) throws -> URL? {
        guard let value else { return nil }
        return try requireURL(value, path: path)
    }

    private static func requireEnum(
        _ value: Any?,
        path: String,
        values: Set<String>
    ) throws -> String {
        let string = try requireString(value, path: path)
        guard values.contains(string) else {
            throw failure("UNKNOWN_ENUM", path, "contains an unsupported value")
        }
        return string
    }

    private static func optionalEnum(
        _ value: Any?,
        fallback: String,
        path: String,
        values: Set<String>
    ) throws -> String {
        guard let value else { return fallback }
        return try requireEnum(value, path: path, values: values)
    }

    private static func optionalInteger(_ value: Any?, fallback: Int, path: String) throws -> Int {
        guard let value else { return fallback }
        let number = try requireFiniteDouble(value, path: path)
        guard number.rounded() == number, number >= Double(Int.min), number <= Double(Int.max) else {
            throw failure("INVALID_TYPE", path, "must be an integer")
        }
        return Int(number)
    }

    private static func optionalBoolean(_ value: Any?, fallback: Bool, path: String) throws -> Bool {
        guard let value else { return fallback }
        guard let number = value as? NSNumber, isBoolean(number) else {
            throw failure("INVALID_TYPE", path, "must be a boolean")
        }
        return number.boolValue
    }

    private static func requireFiniteDouble(_ value: Any?, path: String) throws -> Double {
        guard let number = value as? NSNumber, isBoolean(number) == false else {
            throw failure("INVALID_TYPE", path, "must be a number")
        }
        let result = number.doubleValue
        guard result.isFinite else {
            throw failure("INVALID_VALUE", path, "must be finite")
        }
        return result
    }

    private static func requireFiniteNumber(_ value: Any?, path: String) throws -> CGFloat {
        CGFloat(try requireFiniteDouble(value, path: path))
    }

    private static func requirePositiveNumber(_ value: Any?, path: String) throws -> CGFloat {
        let number = try requireFiniteNumber(value, path: path)
        guard number > 0 else {
            throw failure("OUT_OF_RANGE", path, "must be greater than zero")
        }
        return number
    }

    private static func optionalPositiveNumber(_ value: Any?, path: String) throws -> CGFloat? {
        guard let value else { return nil }
        return try requirePositiveNumber(value, path: path)
    }

    private static func optionalNonNegativeNumber(
        _ value: Any?,
        fallback: CGFloat,
        path: String
    ) throws -> CGFloat {
        guard let value else { return fallback }
        let number = try requireFiniteNumber(value, path: path)
        guard number >= 0 else {
            throw failure("OUT_OF_RANGE", path, "must be zero or greater")
        }
        return number
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func failure(_ code: String, _ path: String, _ detail: String) -> LevixelUniContractError {
        LevixelUniContractError(code: code, path: path, detail: detail)
    }
}
