import AVFoundation
import UIKit

final class LevixelVideoPlayerView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var readyForDisplayObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var likelyToKeepUpObservation: NSKeyValueObservation?
    private var bufferFullObservation: NSKeyValueObservation?
    private var playbackGeneration = 0
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    private var hasReportedFirstFrame = false
    private var isPrimingFirstFrame = false
    private var controlsVisible = false
    private var controlsContainerConstraints: [NSLayoutConstraint] = []

    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let controlsContainer = UIView()

    var onControlsInteractStart: (() -> Void)?
    var onControlsInteractEnd: (() -> Void)?
    var onFirstFrameReady: (() -> Void)?

    var url: URL? {
        didSet {
            setupPlayer()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit {
        tearDownPlayer()
    }

    func toggleControls() {
        setControlsVisible(!controlsVisible, animated: true)
    }

    func resetToStart() {
        player?.pause()
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        slider.value = 0
        updateTimeLabel(current: 0, duration: CMTimeGetSeconds(player?.currentItem?.duration ?? .zero))
        updatePlayButton(isPlaying: false)
    }

    func play() {
        if hasReportedFirstFrame == false {
            primeFirstFrameIfNeeded()
        }
        player?.isMuted = false
        player?.play()
        updatePlayButton(isPlaying: true)
    }

    func pause() {
        player?.pause()
        if hasReportedFirstFrame == false {
            isPrimingFirstFrame = false
        }
        updatePlayButton(isPlaying: false)
    }

    func setPlayerVisible(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        playerLayer?.isHidden = !visible
        playerLayer?.opacity = visible ? 1 : 0
        CATransaction.commit()
        if visible {
            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    func attachControls(to hostView: UIView) {
        if controlsContainer.superview === hostView {
            hostView.bringSubviewToFront(controlsContainer)
            return
        }

        NSLayoutConstraint.deactivate(controlsContainerConstraints)
        controlsContainer.removeFromSuperview()
        hostView.addSubview(controlsContainer)
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainerConstraints = [
            controlsContainer.bottomAnchor.constraint(equalTo: hostView.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            controlsContainer.leadingAnchor.constraint(equalTo: hostView.leadingAnchor, constant: 12),
            controlsContainer.trailingAnchor.constraint(equalTo: hostView.trailingAnchor, constant: -12),
            controlsContainer.heightAnchor.constraint(equalToConstant: 56),
        ]
        NSLayoutConstraint.activate(controlsContainerConstraints)
        hostView.bringSubviewToFront(controlsContainer)
    }

    func setControlsVisible(_ visible: Bool, animated: Bool) {
        controlsVisible = visible
        let animations = {
            self.controlsContainer.alpha = visible ? 1 : 0
        }
        let completion: (Bool) -> Void = { _ in
            self.controlsContainer.isUserInteractionEnabled = visible
        }

        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

    func isTouchOnInteractiveControls(atWindowPoint point: CGPoint) -> Bool {
        return expandedFrameForInteraction(of: controlsContainer, padding: 20)?.contains(point) == true
    }

    func isPointInsideInteractiveControls(_ point: CGPoint) -> Bool {
        guard controlsVisible else { return false }
        guard let hostView = controlsContainer.superview else { return false }
        let pointInHost = hostView.convert(point, from: self)
        if controlsContainer.frame.insetBy(dx: -20, dy: -20).contains(pointInHost) {
            return true
        }
        return false
    }

    func primeFirstFrameIfNeeded() {
        guard let player = player else { return }
        guard hasReportedFirstFrame == false, isPrimingFirstFrame == false else { return }
        isPrimingFirstFrame = true
        player.isMuted = true
        player.play()
    }

    func resetForReuse() {
        setControlsVisible(false, animated: false)
        url = nil
    }

    private func setupUI() {
        backgroundColor = .clear

        controlsContainer.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        controlsContainer.layer.cornerRadius = 12
        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.alpha = 0

        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.setPreferredSymbolConfiguration(
            UIImage.SymbolConfiguration(pointSize: 20, weight: .bold),
            forImageIn: .normal
        )
        playButton.tintColor = .white
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.addTarget(self, action: #selector(handlePlayButtonTouchDown), for: .touchDown)
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        playButton.addTarget(
            self,
            action: #selector(handleControlInteractionEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        controlsContainer.addSubview(playButton)

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = 0
        slider.tintColor = .white
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(handleSliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(handleSliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        controlsContainer.addSubview(slider)

        timeLabel.textColor = .white
        timeLabel.font = .systemFont(ofSize: 13, weight: .regular)
        timeLabel.text = "00:00 / 00:00"
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.addSubview(timeLabel)

        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
            playButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 44),
            playButton.heightAnchor.constraint(equalToConstant: 44),

            slider.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -10),
            slider.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
        ])

        attachControls(to: self)
    }

    private func setupPlayer() {
        playbackGeneration += 1
        let generation = playbackGeneration
        tearDownPlayer()
        guard let url = url else { return }

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.videoGravity = .resizeAspect
        if let playerLayer = playerLayer {
            layer.insertSublayer(playerLayer, at: 0)
        }
        playerLayer?.isHidden = true
        player?.pause()
        player?.isMuted = true
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        hasReportedFirstFrame = false
        isPrimingFirstFrame = false
        slider.value = 0
        updateTimeLabel(current: 0, duration: 0)
        updatePlayButton(isPlaying: false)

        let notifyFirstFrameReadyIfPossible: () -> Void = { [weak self] in
            guard let self = self, self.playbackGeneration == generation, self.hasReportedFirstFrame == false else { return }
            guard let currentItem = self.player?.currentItem else { return }
            let isReadyToPlay = currentItem.status == .readyToPlay
            let isLikelyToKeepUp = currentItem.isPlaybackLikelyToKeepUp || currentItem.isPlaybackBufferFull
            let isReadyForDisplay = self.playerLayer?.isReadyForDisplay == true
            guard isReadyToPlay, isLikelyToKeepUp, isReadyForDisplay else { return }
            self.hasReportedFirstFrame = true
            self.isPrimingFirstFrame = false
            self.player?.pause()
            self.player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            self.player?.isMuted = false
            DispatchQueue.main.async {
                guard self.playbackGeneration == generation else { return }
                DispatchQueue.main.async {
                    guard self.playbackGeneration == generation else { return }
                    self.onFirstFrameReady?()
                }
            }
        }

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { _, _ in
            notifyFirstFrameReadyIfPossible()
        }
        likelyToKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new, .initial]) { _, _ in
            notifyFirstFrameReadyIfPossible()
        }
        bufferFullObservation = item.observe(\.isPlaybackBufferFull, options: [.new, .initial]) { _, _ in
            notifyFirstFrameReadyIfPossible()
        }

        readyForDisplayObservation = playerLayer?.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self] _, change in
            guard let self = self, self.playbackGeneration == generation, change.newValue == true else {
                return
            }
            notifyFirstFrameReadyIfPossible()
        }

        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self, self.playbackGeneration == generation, let item = self.player?.currentItem else { return }
            let duration = CMTimeGetSeconds(item.duration)
            let current = CMTimeGetSeconds(time)
            if duration.isFinite && duration > 0, !self.isScrubbing {
                self.slider.value = Float(current / duration)
            }
            self.updateTimeLabel(current: current, duration: duration)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.playbackGeneration == generation else { return }
            self.resetToStart()
        }
    }

    @objc
    private func togglePlay() {
        if hasReportedFirstFrame == false {
            primeFirstFrameIfNeeded()
        }
        guard let player = player else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            updatePlayButton(isPlaying: false)
        } else {
            player.isMuted = false
            player.play()
            updatePlayButton(isPlaying: true)
        }
    }

    @objc
    private func sliderValueChanged() {
        guard let player = player, let item = player.currentItem else { return }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite && duration > 0 else { return }
        let targetTime = Double(slider.value) * duration
        isScrubbing = true
        player.seek(
            to: CMTime(seconds: targetTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        updateTimeLabel(current: targetTime, duration: duration)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func updateTimeLabel(current: Double, duration: Double) {
        timeLabel.text = "\(formatTime(current)) / \(formatTime(duration))"
    }

    private func updatePlayButton(isPlaying: Bool) {
        playButton.setImage(UIImage(systemName: isPlaying ? "pause.fill" : "play.fill"), for: .normal)
    }

    private func expandedFrameForInteraction(of view: UIView, padding: CGFloat) -> CGRect? {
        guard controlsVisible else { return nil }
        guard view.alpha > 0.01, !view.bounds.isEmpty else { return nil }
        return view.convert(view.bounds.insetBy(dx: -padding, dy: -padding), to: nil)
    }

    @objc
    private func handleSliderTouchDown() {
        guard let player = player else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = player.timeControlStatus == .playing
        player.pause()
        onControlsInteractStart?()
    }

    @objc
    private func handleSliderTouchUp() {
        guard let player = player, let item = player.currentItem else {
            isScrubbing = false
            onControlsInteractEnd?()
            return
        }
        let duration = CMTimeGetSeconds(item.duration)
        guard duration.isFinite && duration > 0 else {
            isScrubbing = false
            onControlsInteractEnd?()
            return
        }
        let targetTime = Double(slider.value) * duration
        player.seek(
            to: CMTime(seconds: targetTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isScrubbing = false
                if self.wasPlayingBeforeScrub {
                    self.play()
                } else {
                    self.pause()
                }
                self.onControlsInteractEnd?()
            }
        }
    }

    @objc
    private func handlePlayButtonTouchDown() {
        onControlsInteractStart?()
    }

    @objc
    private func handleControlInteractionEnded() {
        onControlsInteractEnd?()
    }

    private func tearDownPlayer() {
        if let timeObserver = timeObserver, let player = player {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        readyForDisplayObservation?.invalidate()
        itemStatusObservation?.invalidate()
        likelyToKeepUpObservation?.invalidate()
        bufferFullObservation?.invalidate()
        readyForDisplayObservation = nil
        itemStatusObservation = nil
        likelyToKeepUpObservation = nil
        bufferFullObservation = nil
        timeObserver = nil
        endObserver = nil

        player?.pause()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        isScrubbing = false
        wasPlayingBeforeScrub = false
        hasReportedFirstFrame = false
        isPrimingFirstFrame = false
    }
}
