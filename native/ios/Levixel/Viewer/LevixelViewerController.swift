import UIKit

final class LevixelViewerController: UIViewController {
    private weak var dataSource: LevixelDataSource?
    private weak var initialSourceView: UIImageView?
    private let imageLoader: LevixelImageLoading
    private let galleryId: String?
    private let initialIndex: Int
    private let configuration: LevixelViewerConfiguration

    private let backgroundView = UIView()
    private let contentView = UIView()
    private let collectionView: UICollectionView
    private let navigationBar = UINavigationBar(frame: .zero)
    private let navigationItemRef = UINavigationItem()

    private var transitionCoordinatorRef: LevixelViewerTransitionCoordinator?
    private var presentationSession: LevixelViewerSession?
    private var hasPerformedOpenTransition = false
    private var pendingDismissal = false
    private var hasNotifiedDismissal = false
    private var pendingInitialScroll = false

    private var currentIndex = 0
    private var pageCount = 0
    private var horizontalPagingEnabled = true {
        didSet {
            collectionView.isScrollEnabled = horizontalPagingEnabled
        }
    }

    private var verticalDismissLocked = false
    private var verticalDismissNeedsReanchor = false
    private var videoControlsInteractionActive = false
    private var isRestoringDismissDrag = false
    private var isDraggingToDismiss = false
    private var dragStartPoint = CGPoint.zero
    private var dragTargetView: UIView?
    private weak var dragPageView: LevixelViewerPageView?
    private weak var hiddenActiveSourceView: UIImageView?
    private var hiddenActiveSourcePreviousAlpha: CGFloat = 1

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private struct RightBarButtonConfiguration {
        let image: UIImage?
        let title: String?
        let onTap: ((Int) -> Void)?
    }

    private lazy var theme = configuration.theme
    private lazy var mediaContentMode = configuration.contentMode
    private lazy var closeIcon = configuration.closeIcon ?? UIImage(systemName: "xmark")
    private lazy var rightBarButtonConfiguration: RightBarButtonConfiguration? = {
        switch configuration.rightBarButton {
        case .title(let title, let onTap):
            return RightBarButtonConfiguration(image: nil, title: title, onTap: onTap)
        case .icon(let image, let onTap):
            return RightBarButtonConfiguration(image: image, title: nil, onTap: onTap)
        case .none:
            return nil
        }
    }()

    private var prefersDefaultVideoCloseButton: Bool {
        configuration.closeIcon == nil
    }

    init(
        sourceView: UIImageView,
        dataSource: LevixelDataSource?,
        imageLoader: LevixelImageLoading,
        configuration: LevixelViewerConfiguration = LevixelViewerConfiguration(),
        initialIndex: Int = 0,
        galleryId: String? = nil
    ) {
        self.initialSourceView = sourceView
        self.dataSource = dataSource
        self.imageLoader = imageLoader
        self.configuration = configuration
        self.initialIndex = initialIndex
        self.galleryId = galleryId

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        definesPresentationContext = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = theme == .dark ? .dark : .light
        setupUI()
        currentIndex = clampedIndex(initialIndex)
        pageCount = dataSource?.numberOfItems() ?? 0
        collectionView.reloadData()
        refreshNavigationItems()
        setNavigationBarHidden(shouldHideNavigationBarForCurrentPage, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let itemSize = collectionView.bounds.size
        guard itemSize.width > 0, itemSize.height > 0 else { return }
        if layout.itemSize != itemSize {
            layout.itemSize = itemSize
            layout.invalidateLayout()
            scrollToIndex(currentIndex, animated: false)
        } else if pendingInitialScroll {
            scrollToIndex(currentIndex, animated: false)
            pendingInitialScroll = false
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if hasPerformedOpenTransition == false {
            hasPerformedOpenTransition = true
            scrollToIndex(currentIndex, animated: false)
            transitionCoordinatorRef = LevixelViewerTransitionCoordinator(containerView: view)
            performOpenTransition()
        }
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        theme == .dark ? .lightContent : .darkContent
    }

    deinit {
        restoreHiddenActiveSourceView()
        notifyDismissed()
    }

    func attachPresentationSession(_ session: LevixelViewerSession) {
        presentationSession = session
    }

    func requestDismissal(animated: Bool = true) {
        guard pendingDismissal == false else { return }
        guard animated, hasPerformedOpenTransition, transitionCoordinatorRef != nil else {
            pendingDismissal = true
            restoreHiddenActiveSourceView()
            dismiss(animated: false) { [weak self] in
                self?.notifyDismissed()
            }
            return
        }
        performDismissTransition()
    }

    private var currentPageView: LevixelViewerPageView? {
        pageView(at: currentIndex)
    }

    private var shouldHideNavigationBarForCurrentPage: Bool {
        guard let currentPageView = currentPageView else { return true }
        guard currentPageView.isVideoPage else { return true }
        return !currentPageView.areVideoControlsVisible
    }

    private func setupUI() {
        view.backgroundColor = .clear
        view.overrideUserInterfaceStyle = theme == .dark ? .dark : .light

        backgroundView.backgroundColor = theme.backgroundColor
        backgroundView.alpha = 0
        view.addSubview(backgroundView)
        backgroundView.pinToSuperviewEdges()

        contentView.backgroundColor = .clear
        contentView.alpha = 0
        contentView.overrideUserInterfaceStyle = theme == .dark ? .dark : .light
        view.addSubview(contentView)
        contentView.pinToSuperviewEdges()

        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.isPagingEnabled = true
        collectionView.decelerationRate = .fast
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(LevixelViewerPageCell.self, forCellWithReuseIdentifier: LevixelViewerPageCell.reuseIdentifier)
        contentView.addSubview(collectionView)
        collectionView.pinToSuperviewEdges()
        collectionView.addGestureRecognizer(panGestureRecognizer)

        navigationBar.isTranslucent = true
        navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationBar.shadowImage = UIImage()
        navigationBar.tintColor = theme.tintColor
        navigationBar.overrideUserInterfaceStyle = theme == .dark ? .dark : .light
        navigationBar.items = [navigationItemRef]
        navigationBar.alpha = 0
        navigationBar.isHidden = true
        navigationBar.isUserInteractionEnabled = false
        contentView.addSubview(navigationBar)
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            navigationBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            navigationBar.topAnchor.constraint(equalTo: contentView.safeAreaLayoutGuide.topAnchor),
        ])

        refreshNavigationItems()

        if let rightBarButtonConfiguration = rightBarButtonConfiguration {
            if let image = rightBarButtonConfiguration.image {
                navigationItemRef.rightBarButtonItem = UIBarButtonItem(
                    image: image,
                    style: .plain,
                    target: self,
                    action: #selector(handleRightBarButton)
                )
            } else if let title = rightBarButtonConfiguration.title {
                navigationItemRef.rightBarButtonItem = UIBarButtonItem(
                    title: title,
                    style: .plain,
                    target: self,
                    action: #selector(handleRightBarButton)
                )
            }
            navigationItemRef.rightBarButtonItem?.tintColor = theme.tintColor
        }
    }

    private func performOpenTransition() {
        collectionView.layoutIfNeeded()
        let pageView = currentPageView
        refreshNavigationItems()
        setNavigationBarHidden(shouldHideNavigationBarForCurrentPage, animated: false)
        transitionCoordinatorRef?.performOpenTransition(
            from: initialSourceView,
            to: pageView,
            backgroundView: backgroundView,
            contentView: contentView
        ) { [weak self] in
            guard let self = self else { return }
            self.setVideoRevealAllowedForVisiblePages(true)
            self.pageView(at: self.currentIndex)?.setActive(true)
            self.refreshNavigationItems()
            self.setNavigationBarHidden(self.shouldHideNavigationBarForCurrentPage, animated: false)
            self.hideActiveSourceViewForCurrentIndex()
            self.configuration.onIndexChange?(self.currentIndex)
        }
    }

    private func performDismissTransition(anchorOverride: UIImageView? = nil) {
        guard pendingDismissal == false else { return }
        pendingDismissal = true
        videoControlsInteractionActive = false

        let pageView = currentPageView
        pageView?.prepareForReturnAnimation()

        let anchorView = anchorOverride ?? anchorView(for: currentIndex)
        transitionCoordinatorRef?.performCloseTransition(
            from: pageView,
            to: anchorView,
            backgroundView: backgroundView,
            contentView: contentView
        ) { [weak self] in
            guard let self else { return }
            self.restoreHiddenActiveSourceView()
            self.dismiss(animated: false) { [weak self] in
                self?.notifyDismissed()
            }
        }
    }

    private func notifyDismissed() {
        guard hasNotifiedDismissal == false else { return }
        hasNotifiedDismissal = true
        configuration.onDismiss?()
        presentationSession?.invalidate()
        presentationSession = nil
    }

    private func anchorView(for index: Int) -> UIImageView? {
        if let galleryId = galleryId,
           let sourceView = LevixelSourceViewRegistry.shared.sourceView(for: galleryId, index: index) {
            return sourceView
        }
        if index == initialIndex {
            return initialSourceView
        }
        return nil
    }

    private func clampedIndex(_ index: Int) -> Int {
        let count = dataSource?.numberOfItems() ?? 0
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    private func pageView(at index: Int) -> LevixelViewerPageView? {
        let indexPath = IndexPath(item: index, section: 0)
        return collectionView.cellForItem(at: indexPath).flatMap { $0 as? LevixelViewerPageCell }?.pageView
    }

    private func hideActiveSourceViewForCurrentIndex() {
        guard hasPerformedOpenTransition, pendingDismissal == false else { return }
        let sourceView = anchorView(for: currentIndex)
        if hiddenActiveSourceView !== sourceView {
            restoreHiddenActiveSourceView()
            hiddenActiveSourcePreviousAlpha = sourceView?.alpha ?? 1
            hiddenActiveSourceView = sourceView
        }
        sourceView?.alpha = 0
    }

    private func restoreHiddenActiveSourceView() {
        hiddenActiveSourceView?.alpha = hiddenActiveSourcePreviousAlpha
        hiddenActiveSourceView = nil
        hiddenActiveSourcePreviousAlpha = 1
    }

    private func scrollToIndex(_ index: Int, animated: Bool) {
        guard pageCount > 0 else { return }
        guard collectionView.bounds.width > 0 else {
            pendingInitialScroll = true
            return
        }
        let indexPath = IndexPath(item: clampedIndex(index), section: 0)
        collectionView.scrollToItem(at: indexPath, at: .centeredHorizontally, animated: animated)
    }

    private func updateCurrentIndexFromVisiblePage() {
        let center = CGPoint(
            x: collectionView.contentOffset.x + collectionView.bounds.width * 0.5,
            y: collectionView.bounds.midY
        )
        if let indexPath = collectionView.indexPathForItem(at: center) {
            setCurrentIndex(indexPath.item, notify: true)
        }
    }

    private func setCurrentIndex(_ newIndex: Int, notify: Bool) {
        let safeIndex = clampedIndex(newIndex)
        guard safeIndex != currentIndex || notify == false else {
            updateVisiblePageStates()
            return
        }

        videoControlsInteractionActive = false
        currentIndex = safeIndex
        updateVisiblePageStates()
        hideActiveSourceViewForCurrentIndex()
        if notify {
            configuration.onIndexChange?(currentIndex)
        }
    }

    private func updateVisiblePageStates() {
        for cell in collectionView.visibleCells {
            guard let pageCell = cell as? LevixelViewerPageCell else { continue }
            let index = collectionView.indexPath(for: pageCell)?.item ?? -1
            pageCell.pageView.setActive(index == currentIndex)
            pageCell.pageView.setVideoRevealAllowed(index == currentIndex && hasPerformedOpenTransition)
            if index != currentIndex {
                pageCell.pageView.setVideoControlsVisible(false, animated: false)
            }
        }
        refreshNavigationItems()
        setNavigationBarHidden(shouldHideNavigationBarForCurrentPage, animated: true)
        recalculateHorizontalPagingEnabled()
    }

    private func setVideoRevealAllowedForVisiblePages(_ allowed: Bool) {
        for cell in collectionView.visibleCells {
            guard let pageCell = cell as? LevixelViewerPageCell else { continue }
            let index = collectionView.indexPath(for: pageCell)?.item ?? -1
            pageCell.pageView.setVideoRevealAllowed(allowed && index == currentIndex)
        }
    }

    private func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        let shouldHide = hidden
        let updates = {
            self.navigationBar.alpha = shouldHide ? 0 : 1
        }

        guard animated else {
            navigationBar.layer.removeAllAnimations()
            updates()
            navigationBar.isHidden = shouldHide
            navigationBar.isUserInteractionEnabled = !shouldHide
            return
        }

        navigationBar.layer.removeAllAnimations()
        if shouldHide {
            navigationBar.isUserInteractionEnabled = false
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: updates
            ) { _ in
                self.navigationBar.isHidden = true
            }
            return
        }

        navigationBar.isHidden = false
        navigationBar.isUserInteractionEnabled = true
        UIView.animate(
            withDuration: 0.18,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: updates
        )
    }

    private func recalculateHorizontalPagingEnabled() {
        let canPageHorizontally = currentPageView?.canPageHorizontally ?? true
        horizontalPagingEnabled = canPageHorizontally
            && !isDraggingToDismiss
            && !isRestoringDismissDrag
            && !verticalDismissLocked
            && !verticalDismissNeedsReanchor
            && !videoControlsInteractionActive
    }

    private func refreshNavigationItems() {
        let currentIsVideoPage = currentPageView?.isVideoPage == true
        guard currentIsVideoPage else {
            navigationItemRef.leftBarButtonItem = nil
            return
        }
        let closeButtonItem: UIBarButtonItem
        if currentIsVideoPage && prefersDefaultVideoCloseButton {
            closeButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(handleCloseButton)
            )
        } else {
            closeButtonItem = UIBarButtonItem(
                image: closeIcon,
                style: .plain,
                target: self,
                action: #selector(handleCloseButton)
            )
        }
        closeButtonItem.tintColor = theme.tintColor
        navigationItemRef.leftBarButtonItem = closeButtonItem
    }

    private func beginVerticalDismissDrag() {
        guard let pageView = currentPageView else { return }
        isDraggingToDismiss = true
        dragTargetView = pageView.dragTargetView
        dragStartPoint = dragTargetView?.center ?? pageView.dragTargetView.center
        dragPageView = pageView
        setNavigationBarHidden(true, animated: true)
        pageView.prepareForDismissDrag()
        recalculateHorizontalPagingEnabled()
    }

    private func updateVerticalDismissDrag(_ recognizer: UIPanGestureRecognizer) {
        guard let dragTargetView = dragTargetView else { return }
        let translation = recognizer.translation(in: view)
        let height = max(view.bounds.height, 1)
        let progress = min(abs(translation.y) / height, 1)
        let scale = max(0.84, 1 - progress * 0.16)

        dragTargetView.center = CGPoint(
            x: dragStartPoint.x + translation.x,
            y: dragStartPoint.y + translation.y
        )
        dragTargetView.transform = CGAffineTransform(scaleX: scale, y: scale)
        backgroundView.alpha = max(0, 1 - min(0.9, progress * 1.25))
    }

    private func finishVerticalDismissDrag(_ recognizer: UIPanGestureRecognizer) {
        guard let dragTargetView = dragTargetView else {
            isDraggingToDismiss = false
            resetDragState()
            recalculateHorizontalPagingEnabled()
            return
        }

        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)
        let dismissDistance = view.bounds.height * 0.16
        let quickFlingDistance = view.bounds.height * 0.06
        let shouldDismissByDistance = abs(translation.y) > dismissDistance
        let shouldDismissByFling = abs(translation.y) > quickFlingDistance && abs(velocity.y) > 1300

        isDraggingToDismiss = false
        recalculateHorizontalPagingEnabled()

        if shouldDismissByDistance || shouldDismissByFling {
            dragPageView?.prepareForReturnAnimation()
            performDismissTransition()
            resetDragState()
            return
        }

        isRestoringDismissDrag = true
        recalculateHorizontalPagingEnabled()
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            dragTargetView.center = self.dragStartPoint
            dragTargetView.transform = .identity
            self.backgroundView.alpha = 1
        } completion: { _ in
            self.isRestoringDismissDrag = false
            self.dragPageView?.restoreAfterDismissCancelled()
            self.setNavigationBarHidden(self.shouldHideNavigationBarForCurrentPage, animated: false)
            self.resetDragState()
            self.recalculateHorizontalPagingEnabled()
        }
    }

    private func cancelVerticalDismissDrag() {
        guard let dragTargetView = dragTargetView else {
            isDraggingToDismiss = false
            resetDragState()
            recalculateHorizontalPagingEnabled()
            return
        }

        isDraggingToDismiss = false
        isRestoringDismissDrag = true
        recalculateHorizontalPagingEnabled()
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            dragTargetView.center = self.dragStartPoint
            dragTargetView.transform = .identity
            self.backgroundView.alpha = 1
        } completion: { _ in
            self.isRestoringDismissDrag = false
            self.dragPageView?.restoreAfterDismissCancelled()
            self.setNavigationBarHidden(self.shouldHideNavigationBarForCurrentPage, animated: false)
            self.resetDragState()
            self.recalculateHorizontalPagingEnabled()
        }
    }

    private func resetDragState() {
        dragTargetView = nil
        dragPageView = nil
    }

    @objc
    private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if pendingDismissal {
            return
        }

        let location = recognizer.location(in: view.window)
        switch recognizer.state {
        case .began:
            if verticalDismissNeedsReanchor {
                verticalDismissNeedsReanchor = false
                recalculateHorizontalPagingEnabled()
            }
        case .changed:
            guard isRestoringDismissDrag == false else { return }
            guard verticalDismissLocked == false else { return }
            guard videoControlsInteractionActive == false else { return }
            guard let pageView = currentPageView else { return }

            if isDraggingToDismiss == false {
                let translation = recognizer.translation(in: view)
                let velocity = recognizer.velocity(in: view)
                let isVerticalCandidate = abs(translation.y) > 8 && abs(translation.y) > abs(translation.x) * 1.02
                if isVerticalCandidate && pageView.canBeginVerticalDismiss(at: location, velocity: velocity) {
                    beginVerticalDismissDrag()
                }
            }

            if isDraggingToDismiss {
                updateVerticalDismissDrag(recognizer)
            }
        case .ended:
            if verticalDismissNeedsReanchor {
                recalculateHorizontalPagingEnabled()
                return
            }
            if isDraggingToDismiss {
                finishVerticalDismissDrag(recognizer)
            }
        case .cancelled, .failed:
            if isDraggingToDismiss {
                cancelVerticalDismissDrag()
            }
            if verticalDismissNeedsReanchor {
                recalculateHorizontalPagingEnabled()
            }
        default:
            break
        }
    }

    @objc
    private func handleCloseButton() {
        requestDismissal()
    }

    @objc
    private func handleRightBarButton() {
        rightBarButtonConfiguration?.onTap?(currentIndex)
    }
}

extension LevixelViewerController: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pageCount = dataSource?.numberOfItems() ?? 0
        return pageCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LevixelViewerPageCell.reuseIdentifier,
            for: indexPath
        ) as? LevixelViewerPageCell else {
            return UICollectionViewCell()
        }

        if let item = dataSource?.item(at: indexPath.item) {
            cell.pageView.delegate = self
            cell.pageView.configure(
                index: indexPath.item,
                item: item,
                imageLoader: imageLoader,
                mediaContentMode: mediaContentMode,
                sourcePreviewImage: anchorView(for: indexPath.item)?.image
            )
            cell.pageView.setActive(indexPath.item == currentIndex)
            cell.pageView.setVideoRevealAllowed(hasPerformedOpenTransition && indexPath.item == currentIndex)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let pageCell = cell as? LevixelViewerPageCell else { return }
        pageCell.pageView.setActive(indexPath.item == currentIndex)
        pageCell.pageView.setVideoRevealAllowed(hasPerformedOpenTransition && indexPath.item == currentIndex)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let pageCell = cell as? LevixelViewerPageCell else { return }
        pageCell.pageView.setActive(false)
        pageCell.pageView.setVideoRevealAllowed(false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentIndexFromVisiblePage()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentIndexFromVisiblePage()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if decelerate == false {
            updateCurrentIndexFromVisiblePage()
        }
    }
}

extension LevixelViewerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            recalculateHorizontalPagingEnabled()
            if verticalDismissLocked
                || verticalDismissNeedsReanchor
                || videoControlsInteractionActive
                || isRestoringDismissDrag {
                return false
            }

            guard let pageView = currentPageView else { return false }
            let velocity = panGestureRecognizer.velocity(in: view)
            let location = panGestureRecognizer.location(in: view.window)
            return pageView.canBeginVerticalDismiss(at: location, velocity: velocity)
        }

        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === panGestureRecognizer
    }
}

extension LevixelViewerController: LevixelViewerPageViewDelegate {
    func levixelViewerPageViewDidRequestDismiss(_ pageView: LevixelViewerPageView) {
        guard pageView.index == currentIndex else { return }
        requestDismissal()
    }

    func levixelViewerPageViewDidToggleVideoChrome(_ pageView: LevixelViewerPageView) {
        guard pageView.index == currentIndex else { return }
        _ = pageView.toggleVideoControls()
        setNavigationBarHidden(shouldHideNavigationBarForCurrentPage, animated: true)
    }

    func levixelViewerPageView(_ pageView: LevixelViewerPageView, setHorizontalPagingEnabled enabled: Bool) {
        guard pageView.index == currentIndex else { return }
        if enabled == false {
            horizontalPagingEnabled = false
            return
        }
        recalculateHorizontalPagingEnabled()
    }

    func levixelViewerPageViewDidBeginVideoControlsInteraction(_ pageView: LevixelViewerPageView) {
        guard pageView.index == currentIndex else { return }
        videoControlsInteractionActive = true
        if isDraggingToDismiss {
            cancelVerticalDismissDrag()
        }
        recalculateHorizontalPagingEnabled()
    }

    func levixelViewerPageViewDidEndVideoControlsInteraction(_ pageView: LevixelViewerPageView) {
        guard pageView.index == currentIndex else { return }
        videoControlsInteractionActive = false
        recalculateHorizontalPagingEnabled()
    }

    func levixelViewerPageViewDidBeginMultiTouch(_ pageView: LevixelViewerPageView) {
        guard pageView.index == currentIndex else { return }
        verticalDismissLocked = true
        verticalDismissNeedsReanchor = false
        if isDraggingToDismiss {
            cancelVerticalDismissDrag()
        }
        recalculateHorizontalPagingEnabled()
    }

    func levixelViewerPageViewDidEndMultiTouch(_ pageView: LevixelViewerPageView) {
        guard pageView.index == currentIndex else { return }
        verticalDismissLocked = false
        verticalDismissNeedsReanchor = true
        recalculateHorizontalPagingEnabled()
    }
}

private final class LevixelViewerPageCell: UICollectionViewCell {
    static let reuseIdentifier = "LevixelViewerPageCell"

    let pageView = LevixelViewerPageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(pageView)
        pageView.pinToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layoutIfNeeded()
        pageView.refreshLayoutForCurrentBounds()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        layer.removeAllAnimations()
        contentView.layer.removeAllAnimations()
        transform = .identity
        contentView.transform = .identity
        alpha = 1
        contentView.alpha = 1
        contentView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        pageView.prepareForReuse()
    }
}
