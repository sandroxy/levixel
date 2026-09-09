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
    public var sourceCornerRadius: CGFloat? {
        didSet {
            Self.validateSourceCornerRadius(sourceCornerRadius)
        }
    }
    public var closeIcon: UIImage?
    public var rightBarButton: LevixelViewerBarButton?
    public var onIndexChange: ((Int) -> Void)?
    public var onDismiss: (() -> Void)?
    public var actions: [LevixelAction] {
        didSet { Self.validateActions(actions) }
    }
    public var actionLayout: LevixelActionLayout
    public var actionListIcons: Bool
    public var onEvent: ((LevixelViewerEvent) -> Void)?
    public var onSession: ((LevixelViewerSession) -> Void)?

    public init(
        theme: LevixelViewerTheme = .light,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        closeIcon: UIImage? = nil,
        rightBarButton: LevixelViewerBarButton? = nil,
        onIndexChange: ((Int) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        sourceCornerRadius: CGFloat? = nil,
        actions: [LevixelAction] = [],
        actionLayout: LevixelActionLayout = .list,
        actionListIcons: Bool = false,
        onEvent: ((LevixelViewerEvent) -> Void)? = nil,
        onSession: ((LevixelViewerSession) -> Void)? = nil
    ) {
        Self.validateSourceCornerRadius(sourceCornerRadius)
        self.theme = theme
        self.contentMode = contentMode
        self.sourceCornerRadius = sourceCornerRadius
        self.closeIcon = closeIcon
        self.rightBarButton = rightBarButton
        self.onIndexChange = onIndexChange
        self.onDismiss = onDismiss
        Self.validateActions(actions)
        self.actions = actions
        self.actionLayout = actionLayout
        self.actionListIcons = actionListIcons
        self.onEvent = onEvent
        self.onSession = onSession
        validateActionPresentation()
    }

    // Validate the complete snapshot, allowing callers to configure mutable fields in either order.
    func validateActionPresentation() {
        Self.validateActions(actions)
        if actionLayout == .grid {
            for (index, action) in actions.enumerated() {
                precondition(action.icon != nil, "Levixel actions[\(index)].icon is required for grid actionLayout.")
            }
        }
    }

    private static func validateActions(_ actions: [LevixelAction]) {
        precondition(Set(actions.map(\.id)).count == actions.count, "Levixel action IDs must be unique.")
    }

    private static func validateSourceCornerRadius(_ value: CGFloat?) {
        guard let value else { return }
        precondition(
            value.isFinite && value >= 0,
            "Levixel sourceCornerRadius must be a non-negative finite number."
        )
    }
}
