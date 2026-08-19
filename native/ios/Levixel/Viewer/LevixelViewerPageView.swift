import UIKit

protocol LevixelViewerPageViewDelegate: AnyObject {
    func levixelViewerPageViewDidRequestDismiss(_ pageView: LevixelViewerPageView)
    func levixelViewerPageViewDidToggleVideoChrome(_ pageView: LevixelViewerPageView)
    func levixelViewerPageView(_ pageView: LevixelViewerPageView, setHorizontalPagingEnabled enabled: Bool)
    func levixelViewerPageViewDidBeginMultiTouch(_ pageView: LevixelViewerPageView)
    func levixelViewerPageViewDidEndMultiTouch(_ pageView: LevixelViewerPageView)
}

final class LevixelViewerPageView: UIView {
    weak var delegate: LevixelViewerPageViewDelegate?

    private(set) var index: Int = 0
    private(set) var item: LevixelMediaItem?

    private let mediaContainer = UIView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    private let imageScrollView = UIScrollView()
    private let imageView = UIImageView()
    private let sourcePreviewImageView = UIImageView()

    private let videoContainer = UIView()
    private let posterImageView = UIImageView()
    private let videoPlayerView = LevixelVideoPlayerView(frame: .zero)

    private var imageLoader: LevixelImageLoading?
    private var mediaContentMode: UIView.ContentMode = .scaleAspectFit
    private var loadGeneration = 0

    private var active = false
    private var videoRevealAllowed = false
    private var videoFirstFrameReady = false
    private var pinchInProgress = false
    private var videoControlsVisible = false
    private var videoControlsVisibleBeforeDismissDrag = false

    private lazy var imageSingleTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleImageSingleTap(_:))
    )
    private lazy var imageDoubleTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleImageDoubleTap(_:))
    )
    private lazy var videoSingleTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleVideoSingleTap(_:))
    )

    var isVideoPage: Bool {
        if case .video = item {
            return true
        }
        return false
    }

    var dragTargetView: UIView {
        mediaContainer
    }

    var canPageHorizontally: Bool {
        guard !isVideoPage else { return true }
        return imageScrollView.zoomScale <= imageScrollView.minimumZoomScale + 0.01
    }

    var areVideoControlsVisible: Bool {
        videoControlsVisible
    }

    var sharedElementView: UIImageView? {
        if isVideoPage {
            return posterImageView.image == nil ? nil : posterImageView
        }
        return imageView.image == nil ? nil : imageView
    }

    var isReadyForTransition: Bool {
        guard let sharedElementView = sharedElementView else { return false }
        guard sharedElementView.window != nil else { return false }
        guard sharedElementView.bounds.width > 0, sharedElementView.bounds.height > 0 else { return false }
        guard let image = sharedElementView.image else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        videoPlayerView.resetForReuse()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutImageIfNeeded(resetZoom: false)
    }

    func configure(
        index: Int,
        item: LevixelMediaItem,
        imageLoader: LevixelImageLoading,
        mediaContentMode: UIView.ContentMode,
        sourcePreviewImage: UIImage? = nil
    ) {
        self.index = index
        self.item = item
        self.imageLoader = imageLoader
        self.mediaContentMode = normalizedContentMode(from: mediaContentMode)
        loadGeneration += 1

        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true

        imageScrollView.zoomScale = 1
        imageScrollView.minimumZoomScale = 1
        imageScrollView.maximumZoomScale = 1
        imageScrollView.contentSize = .zero
        imageScrollView.contentOffset = .zero

        imageView.image = nil
        sourcePreviewImageView.image = nil
        sourcePreviewImageView.isHidden = true
        posterImageView.image = nil
        videoPlayerView.resetForReuse()
        videoFirstFrameReady = false
        videoControlsVisible = false
        videoControlsVisibleBeforeDismissDrag = false

        imageScrollView.isHidden = true
        videoContainer.isHidden = true
        mediaContainer.alpha = 1
        layer.removeAllAnimations()
        mediaContainer.layer.removeAllAnimations()
        imageScrollView.layer.removeAllAnimations()
        videoContainer.layer.removeAllAnimations()
        posterImageView.layer.removeAllAnimations()
        imageView.layer.removeAllAnimations()
        sourcePreviewImageView.layer.removeAllAnimations()
        transform = .identity
        alpha = 1
        center = CGPoint(x: bounds.midX, y: bounds.midY)
        mediaContainer.transform = .identity
        mediaContainer.alpha = 1

        switch item {
        case .image(let image):
            configureImagePage(image: image)
        case .imageURL(let url, let placeholder):
            configureImagePage(image: placeholder)
            if placeholder == nil {
                showSourcePreview(image: sourcePreviewImage)
            }
            loadImage(from: url, placeholder: placeholder, into: imageView)
        case .video(let url, let poster):
            configureVideoPage(url: url, poster: poster)
        }
    }

    func prepareForReuse() {
        loadGeneration += 1
        active = false
        videoRevealAllowed = false
        videoFirstFrameReady = false
        pinchInProgress = false
        videoControlsVisible = false
        videoControlsVisibleBeforeDismissDrag = false

        imageScrollView.zoomScale = 1
        imageScrollView.minimumZoomScale = 1
        imageScrollView.maximumZoomScale = 1
        imageScrollView.contentSize = .zero
        imageScrollView.contentOffset = .zero

        imageView.image = nil
        sourcePreviewImageView.image = nil
        sourcePreviewImageView.isHidden = true
        posterImageView.image = nil
        videoPlayerView.resetForReuse()
        videoPlayerView.setControlsVisible(false, animated: false)
        videoControlsVisible = false

        mediaContainer.alpha = 1
        imageScrollView.isHidden = true
        videoContainer.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        layer.removeAllAnimations()
        mediaContainer.layer.removeAllAnimations()
        imageScrollView.layer.removeAllAnimations()
        videoContainer.layer.removeAllAnimations()
        posterImageView.layer.removeAllAnimations()
        imageView.layer.removeAllAnimations()
        sourcePreviewImageView.layer.removeAllAnimations()
        transform = .identity
        alpha = 1
        center = CGPoint(x: bounds.midX, y: bounds.midY)
        mediaContainer.transform = .identity
        mediaContainer.alpha = 1
    }

    func setActive(_ active: Bool) {
        self.active = active
        updateVideoPlaybackIfNeeded()
    }

    func setVideoRevealAllowed(_ allowed: Bool) {
        videoRevealAllowed = allowed
        if !allowed {
            setVideoControlsVisible(false, animated: false)
        }
        updateVideoPlaybackIfNeeded()
    }

    func setMediaHidden(_ hidden: Bool) {
        mediaContainer.alpha = hidden ? 0 : 1
    }

    func sharedElementState() -> LevixelSharedElementState? {
        if isVideoPage {
            return posterImageView.levixelSharedElementState()
        }
        return imageView.levixelSharedElementState(clippingFrameInWindow: imageScrollView.frameInWindow())
    }

    func defaultTransitionGeometry(in windowBounds: CGRect) -> LevixelSharedElementGeometry {
        let imageSize = sharedElementView?.image?.size
            ?? imageView.image?.size
            ?? posterImageView.image?.size
            ?? CGSize(width: max(windowBounds.width * 0.72, 1), height: max(windowBounds.height * 0.42, 1))
        let visibleFrame = LevixelViewerTransitionCoordinator.aspectFitRect(for: imageSize, in: windowBounds)
        return LevixelSharedElementGeometry(
            visibleFrameInWindow: visibleFrame,
            contentFrameInVisibleBounds: CGRect(origin: .zero, size: visibleFrame.size),
            cornerRadius: 0
        )
    }

    func canBeginVerticalDismiss(at windowLocation: CGPoint, velocity: CGPoint) -> Bool {
        guard abs(velocity.y) > abs(velocity.x) * 1.02 else { return false }
        if isVideoPage {
            return !videoPlayerView.isTouchOnInteractiveControls(atWindowPoint: windowLocation)
        }
        return canPageHorizontally
    }

    func prepareForDismissDrag() {
        guard isVideoPage else { return }
        videoControlsVisibleBeforeDismissDrag = videoControlsVisible
        setVideoControlsVisible(false, animated: false)
        posterImageView.alpha = 1
        videoPlayerView.setPlayerVisible(false)
    }

    func restoreAfterDismissCancelled() {
        guard isVideoPage else { return }
        updateVideoPlaybackIfNeeded()
        setVideoControlsVisible(videoControlsVisibleBeforeDismissDrag, animated: false)
        videoControlsVisibleBeforeDismissDrag = false
    }

    func prepareForReturnAnimation() {
        guard isVideoPage else { return }
        videoControlsVisibleBeforeDismissDrag = false
        setVideoControlsVisible(false, animated: false)
        posterImageView.alpha = 1
        videoPlayerView.setPlayerVisible(false)
    }

    func setVideoControlsVisible(_ visible: Bool, animated: Bool) {
        guard isVideoPage else { return }
        videoControlsVisible = visible
        videoPlayerView.setControlsVisible(visible, animated: animated)
    }

    func toggleVideoControls() -> Bool {
        guard isVideoPage else { return false }
        let nextVisible = !videoControlsVisible
        setVideoControlsVisible(nextVisible, animated: true)
        return nextVisible
    }

    private func setupUI() {
        backgroundColor = .clear

        mediaContainer.backgroundColor = .clear
        addSubview(mediaContainer)
        mediaContainer.pinToSuperviewEdges()

        imageScrollView.backgroundColor = .clear
        imageScrollView.delegate = self
        imageScrollView.showsHorizontalScrollIndicator = false
        imageScrollView.showsVerticalScrollIndicator = false
        imageScrollView.decelerationRate = .fast
        imageScrollView.bouncesZoom = true
        mediaContainer.addSubview(imageScrollView)
        imageScrollView.pinToSuperviewEdges()

        imageView.backgroundColor = .clear
        imageView.isUserInteractionEnabled = true
        imageScrollView.addSubview(imageView)

        sourcePreviewImageView.backgroundColor = .clear
        sourcePreviewImageView.isHidden = true
        sourcePreviewImageView.isUserInteractionEnabled = false
        mediaContainer.addSubview(sourcePreviewImageView)
        sourcePreviewImageView.pinToSuperviewEdges()

        imageSingleTapGesture.numberOfTapsRequired = 1
        imageDoubleTapGesture.numberOfTapsRequired = 2
        imageSingleTapGesture.require(toFail: imageDoubleTapGesture)
        imageScrollView.addGestureRecognizer(imageSingleTapGesture)
        imageScrollView.addGestureRecognizer(imageDoubleTapGesture)

        if let pinchGestureRecognizer = imageScrollView.pinchGestureRecognizer {
            pinchGestureRecognizer.addTarget(self, action: #selector(handlePinchState(_:)))
        }

        videoContainer.backgroundColor = .clear
        videoContainer.isHidden = true
        mediaContainer.addSubview(videoContainer)
        videoContainer.pinToSuperviewEdges()

        videoPlayerView.backgroundColor = .clear
        videoContainer.addSubview(videoPlayerView)
        videoPlayerView.pinToSuperviewEdges()
        videoPlayerView.setPlayerVisible(false)
        videoPlayerView.setControlsVisible(false, animated: false)
        videoPlayerView.onFirstFrameReady = { [weak self] in
            self?.handleVideoFirstFrameReady()
        }
        videoPlayerView.onControlsInteractStart = { [weak self] in
            guard let self = self else { return }
            self.delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: false)
        }
        videoPlayerView.onControlsInteractEnd = { [weak self] in
            guard let self = self else { return }
            self.delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: self.canPageHorizontally)
        }

        posterImageView.backgroundColor = .clear
        posterImageView.contentMode = .scaleAspectFit
        videoContainer.addSubview(posterImageView)
        posterImageView.pinToSuperviewEdges()
        videoPlayerView.attachControls(to: videoContainer)

        videoSingleTapGesture.numberOfTapsRequired = 1
        videoSingleTapGesture.delegate = self
        videoContainer.addGestureRecognizer(videoSingleTapGesture)

        activityIndicator.isHidden = true
        activityIndicator.color = .white
        addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func configureImagePage(image: UIImage?) {
        imageScrollView.isHidden = false
        videoContainer.isHidden = true
        imageView.image = image
        if image != nil {
            layoutImageIfNeeded(resetZoom: true)
        } else {
            showLoading()
        }
        delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: canPageHorizontally)
    }

    private func configureVideoPage(url: URL, poster: URL?) {
        imageScrollView.isHidden = true
        videoContainer.isHidden = false

        posterImageView.layer.removeAllAnimations()
        posterImageView.alpha = 1
        videoPlayerView.setPlayerVisible(false)
        videoPlayerView.setControlsVisible(false, animated: false)
        videoControlsVisible = false
        videoControlsVisibleBeforeDismissDrag = false
        videoPlayerView.url = url

        if let poster = poster {
            showLoading()
            loadImage(from: poster, placeholder: nil, into: posterImageView)
        } else {
            posterImageView.image = nil
        }

        delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: true)
        updateVideoPlaybackIfNeeded()
    }

    private func loadImage(from url: URL, placeholder: UIImage?, into imageView: UIImageView) {
        let generation = loadGeneration
        showLoading()
        imageLoader?.loadImage(url, placeholder: placeholder, imageView: imageView) { [weak self] loadedImage in
            guard let self = self else { return }
            guard self.loadGeneration == generation else { return }
            DispatchQueue.main.async {
                guard self.loadGeneration == generation else { return }
                self.hideLoading()
                if imageView === self.imageView {
                    if loadedImage != nil {
                        self.hideSourcePreview()
                    }
                    self.layoutImageIfNeeded(resetZoom: true)
                    self.delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: self.canPageHorizontally)
                }
            }
        }
    }

    private func showSourcePreview(image: UIImage?) {
        guard let image = image else { return }
        sourcePreviewImageView.contentMode = mediaContentMode
        sourcePreviewImageView.image = image
        sourcePreviewImageView.isHidden = false
    }

    private func hideSourcePreview() {
        sourcePreviewImageView.isHidden = true
        sourcePreviewImageView.image = nil
    }

    private func showLoading() {
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
    }

    private func hideLoading() {
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    private func updateVideoPlaybackIfNeeded() {
        guard isVideoPage else { return }
        guard active else {
            videoPlayerView.pause()
            restoreVideoPoster()
            return
        }

        if videoFirstFrameReady == false {
            videoPlayerView.primeFirstFrameIfNeeded()
        }

        if videoRevealAllowed && videoFirstFrameReady {
            revealVideoFromPoster()
            return
        }

        if videoFirstFrameReady {
            videoPlayerView.pause()
        }
        restoreVideoPoster()
    }

    private func restoreVideoPoster() {
        posterImageView.layer.removeAllAnimations()
        posterImageView.alpha = 1
        videoPlayerView.setPlayerVisible(false)
    }

    private func revealVideoFromPoster() {
        videoPlayerView.setPlayerVisible(true)
        videoPlayerView.play()
        posterImageView.layer.removeAllAnimations()
        guard posterImageView.alpha > 0.01 else { return }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.posterImageView.alpha = 0
        }
    }

    private func handleVideoFirstFrameReady() {
        videoFirstFrameReady = true
        hideLoading()
        updateVideoPlaybackIfNeeded()
    }

    private func normalizedContentMode(from contentMode: UIView.ContentMode) -> UIView.ContentMode {
        switch contentMode {
        case .scaleAspectFill:
            return .scaleAspectFill
        default:
            return .scaleAspectFit
        }
    }

    private func layoutImageIfNeeded(resetZoom: Bool) {
        guard !isVideoPage else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let image = imageView.image else { return }

        let scrollBounds = imageScrollView.bounds.size
        guard scrollBounds.width > 0, scrollBounds.height > 0 else { return }

        guard image.size.width > 0, image.size.height > 0 else { return }

        let widthRatio = scrollBounds.width / image.size.width
        let heightRatio = scrollBounds.height / image.size.height
        let minimumScale: CGFloat
        switch mediaContentMode {
        case .scaleAspectFill:
            minimumScale = max(widthRatio, heightRatio)
        default:
            minimumScale = min(widthRatio, heightRatio)
        }

        let maximumScale = max(minimumScale * 4.0, 3.0)

        imageScrollView.minimumZoomScale = minimumScale
        imageScrollView.maximumZoomScale = maximumScale
        if resetZoom || imageScrollView.zoomScale < minimumScale {
            imageScrollView.zoomScale = minimumScale
        }

        let scaledSize = CGSize(
            width: image.size.width * imageScrollView.zoomScale,
            height: image.size.height * imageScrollView.zoomScale
        )
        let contentSize = CGSize(
            width: max(scaledSize.width, scrollBounds.width),
            height: max(scaledSize.height, scrollBounds.height)
        )
        imageScrollView.contentSize = contentSize
        imageView.frame = CGRect(
            x: max((contentSize.width - scaledSize.width) * 0.5, 0),
            y: max((contentSize.height - scaledSize.height) * 0.5, 0),
            width: scaledSize.width,
            height: scaledSize.height
        )
        hideLoading()
    }

    private func zoomRect(for scale: CGFloat, centeredAt point: CGPoint) -> CGRect {
        let width = imageScrollView.bounds.width / scale
        let height = imageScrollView.bounds.height / scale
        return CGRect(
            x: point.x - (width * 0.5),
            y: point.y - (height * 0.5),
            width: width,
            height: height
        )
    }

    @objc
    private func handleImageSingleTap(_ recognizer: UITapGestureRecognizer) {
        delegate?.levixelViewerPageViewDidRequestDismiss(self)
    }

    @objc
    private func handleImageDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard !isVideoPage else { return }
        let minimumScale = imageScrollView.minimumZoomScale
        let maximumScale = imageScrollView.maximumZoomScale
        let newScale: CGFloat
        if imageScrollView.zoomScale <= minimumScale + 0.01 {
            newScale = min(maximumScale, max(minimumScale * 2.4, 2.0))
        } else {
            newScale = minimumScale
        }
        let point = recognizer.location(in: imageView)
        imageScrollView.zoom(to: zoomRect(for: newScale, centeredAt: point), animated: true)
    }

    @objc
    private func handleVideoSingleTap(_ recognizer: UITapGestureRecognizer) {
        delegate?.levixelViewerPageViewDidToggleVideoChrome(self)
    }

    @objc
    private func handlePinchState(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchInProgress = true
            delegate?.levixelViewerPageViewDidBeginMultiTouch(self)
        case .cancelled, .ended, .failed:
            if pinchInProgress {
                pinchInProgress = false
                delegate?.levixelViewerPageViewDidEndMultiTouch(self)
                delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: canPageHorizontally)
            }
        default:
            break
        }
    }
}

extension LevixelViewerPageView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        isVideoPage ? nil : imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        layoutImageIfNeeded(resetZoom: false)
        delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: canPageHorizontally)
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        delegate?.levixelViewerPageView(self, setHorizontalPagingEnabled: canPageHorizontally)
    }
}

extension LevixelViewerPageView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === videoSingleTapGesture else { return true }
        let location = touch.location(in: videoPlayerView)
        return !videoPlayerView.isPointInsideInteractiveControls(location)
    }
}
