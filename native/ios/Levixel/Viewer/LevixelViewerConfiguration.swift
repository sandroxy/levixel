import UIKit

public enum LevixelViewerTheme {
    case light
    case dark

    var backgroundColor: UIColor {
        switch self {
        case .light:
            return .white
        case .dark:
            return .black
        }
    }

    var tintColor: UIColor {
        switch self {
        case .light:
            return .black
        case .dark:
            return .white
        }
    }
}

public enum LevixelViewerBarButton {
    case title(String, onTap: ((Int) -> Void)?)
    case icon(UIImage, onTap: ((Int) -> Void)?)
}

public struct LevixelViewerConfiguration {
    public var theme: LevixelViewerTheme
    public var contentMode: UIView.ContentMode
    public var closeIcon: UIImage?
    public var rightBarButton: LevixelViewerBarButton?
    public var onIndexChange: ((Int) -> Void)?

    public init(
        theme: LevixelViewerTheme = .light,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        closeIcon: UIImage? = nil,
        rightBarButton: LevixelViewerBarButton? = nil,
        onIndexChange: ((Int) -> Void)? = nil
    ) {
        self.theme = theme
        self.contentMode = contentMode
        self.closeIcon = closeIcon
        self.rightBarButton = rightBarButton
        self.onIndexChange = onIndexChange
    }
}
