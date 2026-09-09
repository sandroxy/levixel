import UIKit

public enum LevixelActionLayout: String {
    case list
    case grid
}

public struct LevixelMediaContext {
    public let sessionId: String
    public let galleryId: String
    public let index: Int
    public let itemId: String
    public let mediaType: String

    public var dictionary: [String: Any] {
        ["sessionId": sessionId, "galleryId": galleryId, "index": index,
         "itemId": itemId, "mediaType": mediaType]
    }
}

public struct LevixelViewerEvent {
    public let type: String
    public let context: LevixelMediaContext
    public let actionId: String?
    public let time: Double

    public var dictionary: [String: Any] {
        var payload = context.dictionary
        if let actionId { payload["actionId"] = actionId }
        if type == "indexChange" { payload["currentIndex"] = context.index }
        if type == "mediaError" {
            payload["code"] = "LOAD_FAILED"
            payload["message"] = "Media could not be loaded"
        }
        return ["type": type, "payload": payload, "time": time]
    }
}

public struct LevixelAction {
    public let id: String
    public let label: String
    public let icon: URL?
    public let group: String?
    public let disabled: Bool
    public let destructive: Bool
    public let onPress: ((LevixelViewerEvent) -> Void)?

    public init(id: String, label: String, icon: URL? = nil, group: String? = nil,
                disabled: Bool = false, destructive: Bool = false,
                onPress: ((LevixelViewerEvent) -> Void)? = nil) {
        precondition(!id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Levixel action id must be non-blank.")
        precondition(!label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Levixel action label must be non-blank.")
        precondition(group == nil || !group!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "Levixel action group must be non-blank.")
        self.id = id
        self.label = label
        self.icon = icon
        self.group = group
        self.disabled = disabled
        self.destructive = destructive
        self.onPress = onPress
    }
}

private enum LevixelActionSheetPalette {
    static let surface = UIColor(white: 222.0 / 255.0, alpha: 1)
    static let tile = UIColor.white
    static let icon = UIColor(red: 0.184, green: 0.204, blue: 0.231, alpha: 1)
    static let label = UIColor(red: 0.294, green: 0.314, blue: 0.341, alpha: 1)
    static let cancel = UIColor(red: 0.267, green: 0.373, blue: 0.514, alpha: 1)
    static let destructive = UIColor(red: 0.780, green: 0.224, blue: 0.204, alpha: 1)
    static let separator = UIColor.black.withAlphaComponent(0.07)
}

private enum LevixelActionSheetTypography {
    static func labelFont(layout: LevixelActionLayout, compatibleWith traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: layout == .grid ? .caption1 : .body)
            .scaledFont(for: .systemFont(ofSize: layout == .grid ? 12 : 16), compatibleWith: traits)
    }
}

final class LevixelActionSheetView: UIView {
    private let layout: LevixelActionLayout
    private var topSpacing: CGFloat { layout == .grid ? 32 : 8 }
    private var groupCount = 0
    private static let bottomSpacing: CGFloat = 16
    let scrollView = UIScrollView()
    let topInsetView = UIView()
    private let column = UIStackView()
    private let cancelButton = UIButton(type: .system)
    private var buttons: [LevixelActionButton] = []
    private var rowHeightConstraints: [NSLayoutConstraint] = []
    private var listHeightConstraints: [NSLayoutConstraint] = []
    private var cancelHeightConstraint: NSLayoutConstraint!
    private let cancel: () -> Void
    private(set) var preferredHeight: CGFloat = 0
    var preferredHeightDidChange: (() -> Void)?

    init(actions: [LevixelAction], imageLoader: LevixelImageLoading,
         layout: LevixelActionLayout = .list, listIcons: Bool = false,
         select: @escaping (LevixelAction) -> Void, cancel: @escaping () -> Void) {
        self.cancel = cancel
        self.layout = layout
        super.init(frame: .zero)
        // The action surface has its own appearance, independent of the media canvas.
        overrideUserInterfaceStyle = .light
        accessibilityViewIsModal = true
        // Keep the content palette stable over every image. UIKit owns the
        // surrounding sheet shape and transition; no extra blur layer is needed.
        backgroundColor = LevixelActionSheetPalette.surface
        addSubview(topInsetView)
        topInsetView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        scrollView.addSubview(column)
        column.translatesAutoresizingMaskIntoConstraints = false
        var groups: [(String, [LevixelAction])] = []
        for action in actions {
            let key = action.group ?? ""
            if let index = groups.firstIndex(where: { $0.0 == key }) { groups[index].1.append(action) }
            else { groups.append((key, [action])) }
        }
        groupCount = groups.count
        for (groupIndex, group) in groups.enumerated() {
            let actions = group.1
            if layout == .list {
                if groupIndex > 0 {
                    let gap = UIView()
                    gap.heightAnchor.constraint(equalToConstant: 8).isActive = true
                    column.addArrangedSubview(gap)
                }
                for (index, action) in actions.enumerated() {
                    if index > 0 {
                        let separator = UIView()
                        separator.backgroundColor = LevixelActionSheetPalette.separator
                        separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
                        column.addArrangedSubview(separator)
                    }
                    let button = LevixelActionButton(action: action, imageLoader: imageLoader,
                        layout: layout, listIcons: listIcons) { select(action) }
                    let height = button.heightAnchor.constraint(equalToConstant: 64)
                    height.isActive = true
                    listHeightConstraints.append(height)
                    buttons.append(button)
                    column.addArrangedSubview(button)
                }
            } else {
                let scroll = UIScrollView()
                scroll.showsHorizontalScrollIndicator = false
                scroll.contentInsetAdjustmentBehavior = .never
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 10
                row.alignment = .top
                scroll.addSubview(row)
                row.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
                    row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
                    row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
                    row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
                    row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor, constant: -24)
                ])
                for action in actions {
                    let button = LevixelActionButton(action: action, imageLoader: imageLoader,
                        layout: layout, listIcons: listIcons) { select(action) }
                    button.widthAnchor.constraint(equalToConstant: 72).isActive = true
                    row.addArrangedSubview(button)
                    buttons.append(button)
                }
                let rowHeight = scroll.heightAnchor.constraint(equalToConstant: 124)
                rowHeight.isActive = true
                rowHeightConstraints.append(rowHeight)
                column.addArrangedSubview(scroll)
            }
        }
        cancelButton.accessibilityIdentifier = "levixel-actions-cancel"
        cancelButton.setTitle(Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "取消" : "Cancel", for: .normal)
        cancelButton.setTitleColor(LevixelActionSheetPalette.cancel, for: .normal)
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        cancelButton.addTarget(self, action: #selector(dismissActions), for: .touchUpInside)
        addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        let separator = UIView()
        separator.backgroundColor = LevixelActionSheetPalette.separator
        addSubview(separator)
        separator.translatesAutoresizingMaskIntoConstraints = false
        cancelHeightConstraint = cancelButton.heightAnchor.constraint(equalToConstant: 56)
        NSLayoutConstraint.activate([
            topInsetView.topAnchor.constraint(equalTo: topAnchor),
            topInsetView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topInsetView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topInsetView.heightAnchor.constraint(equalToConstant: topSpacing),
            scrollView.topAnchor.constraint(equalTo: topInsetView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -8),
            column.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            column.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            separator.bottomAnchor.constraint(equalTo: cancelButton.topAnchor),
            cancelButton.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            cancelHeightConstraint,
            cancelButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -Self.bottomSpacing)
        ])
        updateTypography()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateTypography()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            updateTypography()
        }
    }

    private func updateTypography() {
        guard cancelHeightConstraint != nil else { return }
        let labelFont = LevixelActionSheetTypography.labelFont(layout: layout, compatibleWith: traitCollection)
        buttons.forEach { $0.updateFonts(compatibleWith: traitCollection) }
        let cancelFont = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 16), compatibleWith: traitCollection)
        cancelButton.titleLabel?.font = cancelFont
        // Keep the default spacing, growing rows for two lines of larger text.
        let rowHeight = max(124, 60 + 8 + ceil(labelFont.lineHeight * 2) + 24)
        rowHeightConstraints.forEach { $0.constant = rowHeight }
        let listRowHeight = max(64, ceil(labelFont.lineHeight * 2) + 24)
        listHeightConstraints.forEach { $0.constant = listRowHeight }
        let cancelHeight = max(56, ceil(cancelFont.lineHeight) + 24)
        cancelHeightConstraint.constant = cancelHeight
        let listHeight = CGFloat(buttons.count) * listRowHeight
            + CGFloat(max(0, groupCount - 1)) * 8
            + CGFloat(max(0, buttons.count - groupCount)) / UIScreen.main.scale
        let bodyHeight = layout == .grid ? CGFloat(rowHeightConstraints.count) * rowHeight : listHeight
        let height = topSpacing + bodyHeight + 8 + 1 / UIScreen.main.scale + cancelHeight + Self.bottomSpacing
        if preferredHeight != height {
            preferredHeight = height
            preferredHeightDidChange?()
        }
    }

    @objc private func dismissActions() { cancel() }
    override func accessibilityPerformEscape() -> Bool { cancel(); return true }
}

/// The viewer presents this controller, so UIKit owns the sheet's movement,
/// dimming, interactive dismissal and accessibility focus as one transition.
final class LevixelActionSheetController: UIViewController, UIAdaptivePresentationControllerDelegate {
    private let onClosed: (LevixelAction?) -> Void
    private var selectedAction: LevixelAction?
    private var presentationFinished = false
    private var closing = false
    private var closed = false
    private var animateClose = true
    private var completions: [() -> Void] = []
    private let legacyTransition = LevixelActionSheetTransition()
    let content: LevixelActionSheetView

    init(actions: [LevixelAction], imageLoader: LevixelImageLoading,
         layout: LevixelActionLayout = .list, listIcons: Bool = false,
         onClosed: @escaping (LevixelAction?) -> Void) {
        self.onClosed = onClosed
        // Closures are connected after super.init, when self can be captured.
        var select: ((LevixelAction) -> Void)?
        var cancel: (() -> Void)?
        content = LevixelActionSheetView(actions: actions, imageLoader: imageLoader,
            layout: layout, listIcons: listIcons, select: { select?($0) }, cancel: { cancel?() })
        super.init(nibName: nil, bundle: nil)
        select = { [weak self] action in
            guard let self, !self.closing, !action.disabled else { return }
            self.selectedAction = action
            self.close()
        }
        cancel = { [weak self] in self?.close() }
        overrideUserInterfaceStyle = .light
        modalPresentationCapturesStatusBarAppearance = true
        preferredContentSize = CGSize(width: 540, height: content.preferredHeight)
        if #available(iOS 15.0, *) {
            modalPresentationStyle = .pageSheet
            if let sheet = sheetPresentationController {
                sheet.prefersGrabberVisible = false
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                sheet.prefersEdgeAttachedInCompactHeight = true
                sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
                if #available(iOS 16.0, *) {
                    let content = self.content
                    sheet.detents = [.custom(identifier: .init("levixel-actions")) { context in
                        min(content.preferredHeight, context.maximumDetentValue * 0.8)
                    }]
                } else {
                    sheet.detents = [.medium(), .large()]
                }
            }
        } else {
            modalPresentationStyle = .custom
            transitioningDelegate = legacyTransition
            legacyTransition.install(on: self)
        }
        presentationController?.delegate = self
        content.preferredHeightDidChange = { [weak self] in
            guard let self else { return }
            self.preferredContentSize.height = self.content.preferredHeight
            if #available(iOS 16.0, *) { self.sheetPresentationController?.invalidateDetents() }
            self.presentationController?.containerView?.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() { view = content }
    override var prefersStatusBarHidden: Bool { true }
    override func accessibilityPerformEscape() -> Bool { close(); return true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelFromKeyboard))]
    }
    @objc private func cancelFromKeyboard() { close() }

    func presentationDidComplete() {
        presentationFinished = true
        if closing { performClose() }
    }

    func close(animated: Bool = true, completion: (() -> Void)? = nil) {
        if closed { completion?(); return }
        if let completion { completions.append(completion) }
        guard !closing else { return }
        closing = true
        animateClose = animated
        content.isUserInteractionEnabled = false
        // Dismissing during present() is ignored by UIKit. Finish presenting first.
        if presentationFinished { performClose() }
    }

    private func performClose() {
        dismiss(animated: animateClose) { [weak self] in self?.finishClose() }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finishClose()
    }

    fileprivate func interactiveDismissalDidComplete() {
        // UIKit also ends the transition when an interactive drag is cancelled.
        if presentingViewController == nil { finishClose() }
    }

    private func finishClose() {
        guard !closed else { return }
        closed = true
        onClosed(selectedAction)
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0() }
    }
}

/// iOS 13–14 do not expose configurable system sheets. Keep the same content
/// and a UIKit presentation transition, with an interactive top-edge dismissal.
private final class LevixelActionSheetTransition: NSObject, UIViewControllerTransitioningDelegate {
    private weak var controller: LevixelActionSheetController?
    private var interaction: UIPercentDrivenInteractiveTransition?

    func install(on controller: LevixelActionSheetController) {
        self.controller = controller
        controller.content.topInsetView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag(_:))))
    }

    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let controller else { return }
        let fraction = max(0, gesture.translation(in: controller.view).y) / max(1, controller.view.bounds.height)
        switch gesture.state {
        case .began:
            interaction = UIPercentDrivenInteractiveTransition()
            interaction?.completionCurve = .easeOut
            controller.dismiss(animated: true) { [weak controller] in
                controller?.interactiveDismissalDidComplete()
            }
        case .changed: interaction?.update(fraction)
        case .ended, .cancelled:
            if gesture.state == .ended && (fraction > 0.25 || gesture.velocity(in: controller.view).y > 700) {
                interaction?.finish()
            } else { interaction?.cancel() }
            interaction = nil
        default: break
        }
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        LevixelActionSheetPresentation(presentedViewController: presented, presenting: presenting)
    }
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        LevixelActionSheetAnimation(presenting: true)
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        LevixelActionSheetAnimation(presenting: false)
    }
    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? { interaction }
}

private final class LevixelActionSheetPresentation: UIPresentationController {
    private let shade = UIButton(type: .custom)
    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }
        let width = min(containerView.bounds.width, 540)
        let height = min(presentedViewController.preferredContentSize.height + containerView.safeAreaInsets.bottom,
                         containerView.bounds.height * 0.8)
        return CGRect(x: (containerView.bounds.width - width) / 2,
                      y: containerView.bounds.height - height, width: width, height: height)
    }
    override func presentationTransitionWillBegin() {
        guard let containerView else { return }
        shade.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        shade.alpha = 0
        shade.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        containerView.insertSubview(shade, at: 0)
        presentedView?.layer.cornerRadius = 28
        presentedView?.layer.cornerCurve = .continuous
        presentedView?.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView?.clipsToBounds = true
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.shade.alpha = 1 })
    }
    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in self.shade.alpha = 0 })
    }
    override func containerViewWillLayoutSubviews() {
        shade.frame = containerView?.bounds ?? .zero
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
    @objc private func cancel() { (presentedViewController as? LevixelActionSheetController)?.close() }
}

private final class LevixelActionSheetAnimation: NSObject, UIViewControllerAnimatedTransitioning {
    private let presenting: Bool
    init(presenting: Bool) { self.presenting = presenting }
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        UIAccessibility.isReduceMotionEnabled ? 0.15 : (presenting ? 0.36 : 0.28)
    }
    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let key: UITransitionContextViewControllerKey = presenting ? .to : .from
        guard let controller = context.viewController(forKey: key) else { context.completeTransition(false); return }
        let view = controller.view!
        if presenting {
            context.containerView.addSubview(view)
            view.frame = context.finalFrame(for: controller)
            view.layoutIfNeeded()
        }
        let offscreen = CGAffineTransform(translationX: 0, y: context.containerView.bounds.maxY - view.frame.minY)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if presenting { view.transform = reduceMotion ? .identity : offscreen; view.alpha = reduceMotion ? 0 : 1 }
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            view.transform = self.presenting || reduceMotion ? .identity : offscreen
            view.alpha = !self.presenting && reduceMotion ? 0 : 1
        } completion: { _ in
            let completed = !context.transitionWasCancelled
            if !completed { view.transform = .identity; view.alpha = 1 }
            context.completeTransition(completed)
        }
    }
}

private final class LevixelActionButton: UIButton {
    private let perform: () -> Void
    private let label = UILabel()
    private let layout: LevixelActionLayout

    init(action: LevixelAction, imageLoader: LevixelImageLoading,
         layout: LevixelActionLayout, listIcons: Bool, perform: @escaping () -> Void) {
        self.perform = perform
        self.layout = layout
        super.init(frame: .zero)
        isEnabled = !action.disabled
        alpha = action.disabled ? 0.4 : 1
        accessibilityLabel = action.label
        accessibilityIdentifier = "levixel-action-\(action.id)"
        label.text = action.label
        label.adjustsFontForContentSizeCategory = true
        label.textColor = action.destructive ? LevixelActionSheetPalette.destructive : LevixelActionSheetPalette.label
        label.numberOfLines = 2
        label.textAlignment = layout == .list && listIcons ? .left : .center
        label.isUserInteractionEnabled = false
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        if layout == .grid {
            let tile = UIView()
            tile.isUserInteractionEnabled = false
            tile.backgroundColor = LevixelActionSheetPalette.tile
            tile.layer.cornerRadius = 16
            tile.layer.cornerCurve = .continuous
            addSubview(tile)
            tile.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                tile.topAnchor.constraint(equalTo: topAnchor), tile.centerXAnchor.constraint(equalTo: centerXAnchor),
                tile.widthAnchor.constraint(equalToConstant: 60), tile.heightAnchor.constraint(equalToConstant: 60),
                label.topAnchor.constraint(equalTo: tile.bottomAnchor, constant: 8),
                label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            if let url = action.icon { addIcon(url, size: 30, to: tile, imageLoader: imageLoader) }
        } else {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: listIcons ? 60 : 24),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 12),
                label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -12)
            ])
            // The icon column stays aligned even when individual list items omit an icon.
            if listIcons, let url = action.icon {
                let slot = UIView()
                slot.isUserInteractionEnabled = false
                addSubview(slot)
                slot.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    slot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
                    slot.centerYAnchor.constraint(equalTo: centerYAnchor),
                    slot.widthAnchor.constraint(equalToConstant: 24), slot.heightAnchor.constraint(equalToConstant: 24)
                ])
                addIcon(url, size: 24, to: slot, imageLoader: imageLoader)
            }
        }
        updateFonts(compatibleWith: traitCollection)
        addTarget(self, action: #selector(selected), for: .touchUpInside)
    }

    private func addIcon(_ url: URL, size: CGFloat, to container: UIView, imageLoader: LevixelImageLoading) {
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.tintColor = LevixelActionSheetPalette.icon
        let placeholder = UIImage(systemName: "ellipsis")
        icon.image = placeholder
        container.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor), icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: size), icon.heightAnchor.constraint(equalToConstant: size)
        ])
        if url.isFileURL || url.scheme == "data" {
            DispatchQueue.global(qos: .userInitiated).async {
                let image = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
                DispatchQueue.main.async { [weak icon] in icon?.image = image ?? placeholder }
            }
        } else {
            imageLoader.loadImage(url, placeholder: placeholder, imageView: icon) { [weak icon] image in
                if image == nil { icon?.image = placeholder }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet {
            if layout == .list { backgroundColor = isHighlighted ? UIColor.black.withAlphaComponent(0.04) : .clear }
        }
    }

    func updateFonts(compatibleWith traits: UITraitCollection) {
        label.font = LevixelActionSheetTypography.labelFont(layout: layout, compatibleWith: traits)
    }

    @objc private func selected() { perform() }
}
