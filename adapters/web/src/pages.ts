import {
  aspectFitRect,
  captureZoomedViewport,
  clamp,
  clampPan,
  doubleTapRelativeZoom,
  imageLayout,
  intersectRect,
  restoreZoomedViewport,
  type ImageLayout,
  type SharedElementGeometry,
  type ZoomedViewportState,
} from './geometry.js';
import { loadImage, transitionURL } from './media-cache.js';
import type { ImageInfo, LevixelMediaItem, LevixelSize } from './types.js';

export interface ViewerPageDelegate {
  requestClose(): void;
  videoChromeChanged(visible: boolean): void;
  controlsInteractionChanged(active: boolean): void;
}

export interface ViewerPage {
  readonly element: HTMLElement;
  readonly item: LevixelMediaItem;
  readonly index: number;
  setActive(active: boolean): void;
  ensureLoaded(priority?: boolean): void;
  updateViewport(size: LevixelSize): void;
  setMediaHidden(hidden: boolean): void;
  transitionGeometry(): SharedElementGeometry | null;
  transitionSource(): string | undefined;
  isZoomed(): boolean;
  beginPan(): { x: number; y: number };
  updatePan(start: { x: number; y: number }, delta: { x: number; y: number }): void;
  beginPinch(center: { x: number; y: number }): PinchState | null;
  updatePinch(state: PinchState, scale: number, center: { x: number; y: number }): void;
  zoomAt(point: { x: number; y: number }, requestedZoom: number): void;
  togglePrimaryAction(point: { x: number; y: number }): void;
  isControlTarget(target: EventTarget | null): boolean;
  prepareForDismissDrag(): void;
  restoreAfterDismissCancelled(): void;
  prepareForReturnAnimation(): void;
  pauseForBackground(): boolean;
  resumeFromBackground(wasPlaying: boolean): void;
  destroy(): void;
}

export interface PinchState {
  zoom: number;
  normalizedPoint: { x: number; y: number };
}

abstract class BasePage implements ViewerPage {
  readonly element: HTMLElement;
  readonly item: LevixelMediaItem;
  readonly index: number;
  protected readonly delegate: ViewerPageDelegate;
  protected readonly mediaShell: HTMLElement;
  protected readonly spinner: HTMLElement;
  protected viewport: LevixelSize = { width: 1, height: 1 };
  protected active = false;
  protected loadGeneration = 0;

  constructor(index: number, item: LevixelMediaItem, delegate: ViewerPageDelegate) {
    this.index = index;
    this.item = item;
    this.delegate = delegate;
    this.element = document.createElement('section');
    this.element.className = 'page';
    this.element.setAttribute('aria-label', item.alt || `${item.type} ${index + 1}`);
    this.element.setAttribute('aria-roledescription', item.type === 'video' ? 'video' : 'image');
    this.mediaShell = document.createElement('div');
    this.mediaShell.className = item.type === 'video' ? 'video-shell' : 'media-shell';
    this.spinner = document.createElement('div');
    this.spinner.className = 'spinner';
    this.spinner.setAttribute('role', 'status');
    this.spinner.setAttribute('aria-label', 'Loading media');
    this.spinner.setAttribute('aria-hidden', 'true');
    this.spinner.dataset.visible = 'false';
    this.element.append(this.mediaShell, this.spinner);
  }

  abstract setActive(active: boolean): void;
  abstract ensureLoaded(priority?: boolean): void;
  abstract updateViewport(size: LevixelSize): void;
  abstract transitionGeometry(): SharedElementGeometry | null;
  abstract transitionSource(): string | undefined;
  abstract togglePrimaryAction(point: { x: number; y: number }): void;

  setMediaHidden(hidden: boolean): void {
    this.mediaShell.style.opacity = hidden ? '0' : '1';
  }

  isZoomed(): boolean {
    return false;
  }

  beginPan(): { x: number; y: number } {
    return { x: 0, y: 0 };
  }

  updatePan(_start: { x: number; y: number }, _delta: { x: number; y: number }): void {}

  beginPinch(_center: { x: number; y: number }): PinchState | null {
    return null;
  }

  updatePinch(_state: PinchState, _scale: number, _center: { x: number; y: number }): void {}

  zoomAt(_point: { x: number; y: number }, _requestedZoom: number): void {}

  isControlTarget(target: EventTarget | null): boolean {
    return target instanceof Element && target.closest('[data-levixel-control]') !== null;
  }

  prepareForDismissDrag(): void {}
  restoreAfterDismissCancelled(): void {}
  prepareForReturnAnimation(): void {}

  pauseForBackground(): boolean {
    return false;
  }

  resumeFromBackground(_wasPlaying: boolean): void {}

  destroy(): void {
    this.loadGeneration += 1;
  }

  protected showLoading(visible: boolean): void {
    this.spinner.dataset.visible = String(visible);
    this.spinner.setAttribute('aria-hidden', String(!visible));
  }

  protected geometryForElement(element: HTMLElement): SharedElementGeometry | null {
    const rect = element.getBoundingClientRect();
    const viewport = { left: 0, top: 0, width: this.viewport.width, height: this.viewport.height };
    const content = { left: rect.left, top: rect.top, width: rect.width, height: rect.height };
    const visible = intersectRect(content, viewport);
    if (!visible)
      return null;
    return {
      visible,
      content: {
        left: content.left - visible.left,
        top: content.top - visible.top,
        width: content.width,
        height: content.height,
      },
      cornerRadius: 0,
    };
  }
}

export class ImagePage extends BasePage {
  private readonly image: HTMLImageElement;
  private imageInfo?: ImageInfo;
  private layout?: ImageLayout;
  private zoom = 1;
  private pan = { x: 0, y: 0 };
  private loadStarted = false;
  private fullImageReady = false;
  private loadingTimer: number | undefined;

  constructor(
    index: number,
    item: LevixelMediaItem,
    delegate: ViewerPageDelegate,
    initialPreview?: ImageInfo,
  ) {
    super(index, item, delegate);
    this.image = document.createElement('img');
    this.image.className = 'image';
    this.image.alt = item.alt ?? '';
    this.image.draggable = false;
    this.image.decoding = 'async';
    this.mediaShell.append(this.image);
    if (initialPreview)
      this.applyImage(initialPreview, false);
  }

  override setActive(active: boolean): void {
    this.active = active;
    if (active)
      this.element.removeAttribute('aria-hidden');
    else
      this.element.setAttribute('aria-hidden', 'true');
    if (active)
      this.ensureLoaded(true);
  }

  override ensureLoaded(priority = false): void {
    if (this.fullImageReady || this.loadStarted)
      return;
    this.loadStarted = true;
    const generation = ++this.loadGeneration;
    this.loadingTimer = window.setTimeout(() => {
      if (this.loadGeneration === generation && !this.fullImageReady)
        this.showLoading(true);
    }, 120);
    void loadImage(this.item.url, priority).then((info) => {
      if (this.loadGeneration !== generation)
        return;
      this.fullImageReady = true;
      this.clearLoading();
      this.applyImage(info, true);
    }, () => {
      if (this.loadGeneration !== generation)
        return;
      this.clearLoading();
    });
  }

  override updateViewport(size: LevixelSize): void {
    const state = this.captureViewportState();
    this.viewport = size;
    this.element.style.width = `${size.width}px`;
    this.element.style.height = `${size.height}px`;
    this.relayout(state);
  }

  override transitionGeometry(): SharedElementGeometry | null {
    if (!this.imageInfo || !this.image.src)
      return null;
    return this.geometryForElement(this.image);
  }

  override transitionSource(): string | undefined {
    return this.image.currentSrc || this.image.src || this.imageInfo?.src;
  }

  override isZoomed(): boolean {
    return this.zoom > 1.01;
  }

  override beginPan(): { x: number; y: number } {
    return { ...this.pan };
  }

  override updatePan(start: { x: number; y: number }, delta: { x: number; y: number }): void {
    if (!this.layout)
      return;
    this.pan = clampPan(
      { x: start.x + delta.x, y: start.y + delta.y },
      this.zoom,
      this.layout,
      this.viewport,
    );
    this.applyTransform(false);
  }

  override beginPinch(center: { x: number; y: number }): PinchState | null {
    if (!this.layout)
      return null;
    return {
      zoom: this.zoom,
      normalizedPoint: {
        x: 0.5 + (center.x - this.viewport.width / 2 - this.pan.x)
          / (this.layout.width * this.zoom),
        y: 0.5 + (center.y - this.viewport.height / 2 - this.pan.y)
          / (this.layout.height * this.zoom),
      },
    };
  }

  override updatePinch(
    state: PinchState,
    scale: number,
    center: { x: number; y: number },
  ): void {
    if (!this.layout)
      return;
    const zoom = clamp(state.zoom * scale, 1, this.layout.maximumRelativeZoom);
    const requestedPan = {
      x: center.x - this.viewport.width / 2
        - (state.normalizedPoint.x - 0.5) * this.layout.width * zoom,
      y: center.y - this.viewport.height / 2
        - (state.normalizedPoint.y - 0.5) * this.layout.height * zoom,
    };
    this.zoom = zoom;
    this.pan = clampPan(requestedPan, zoom, this.layout, this.viewport);
    this.applyTransform(false);
  }

  override zoomAt(point: { x: number; y: number }, requestedZoom: number): void {
    if (!this.layout)
      return;
    const normalizedPoint = {
      x: 0.5 + (point.x - this.viewport.width / 2 - this.pan.x)
        / (this.layout.width * this.zoom),
      y: 0.5 + (point.y - this.viewport.height / 2 - this.pan.y)
        / (this.layout.height * this.zoom),
    };
    const zoom = clamp(requestedZoom, 1, this.layout.maximumRelativeZoom);
    this.zoom = zoom;
    this.pan = clampPan(
      {
        x: point.x - this.viewport.width / 2
          - (normalizedPoint.x - 0.5) * this.layout.width * zoom,
        y: point.y - this.viewport.height / 2
          - (normalizedPoint.y - 0.5) * this.layout.height * zoom,
      },
      zoom,
      this.layout,
      this.viewport,
    );
    this.applyTransform(true);
  }

  override togglePrimaryAction(point: { x: number; y: number }): void {
    if (!this.layout)
      return;
    const targetZoom = this.isZoomed() ? 1 : doubleTapRelativeZoom(this.layout);
    this.zoomAt(point, targetZoom);
  }

  override destroy(): void {
    super.destroy();
    this.clearLoading();
  }

  private applyImage(info: ImageInfo, preserveViewport: boolean): void {
    const state = preserveViewport ? this.captureViewportState() : null;
    this.imageInfo = info;
    this.image.src = info.src;
    this.relayout(state);
  }

  private relayout(state: ZoomedViewportState | null): void {
    if (!this.imageInfo || this.viewport.width <= 0 || this.viewport.height <= 0)
      return;
    this.layout = imageLayout(this.imageInfo, this.viewport);
    this.image.style.left = `${(this.viewport.width - this.layout.width) / 2}px`;
    this.image.style.top = `${(this.viewport.height - this.layout.height) / 2}px`;
    this.image.style.width = `${this.layout.width}px`;
    this.image.style.height = `${this.layout.height}px`;
    if (state) {
      const restored = restoreZoomedViewport(state, this.layout, this.viewport);
      this.zoom = restored.zoom;
      this.pan = restored.pan;
    }
    else {
      this.zoom = 1;
      this.pan = { x: 0, y: 0 };
    }
    this.applyTransform(false);
  }

  private captureViewportState(): ZoomedViewportState | null {
    if (!this.layout)
      return null;
    return captureZoomedViewport(this.zoom, this.pan, this.layout);
  }

  private applyTransform(animated: boolean): void {
    this.image.style.transition = animated
      ? 'transform 220ms cubic-bezier(0.22, 1, 0.36, 1)'
      : 'none';
    this.image.style.transform = `translate3d(${this.pan.x}px, ${this.pan.y}px, 0) scale(${this.zoom})`;
  }

  private clearLoading(): void {
    if (this.loadingTimer !== undefined) {
      window.clearTimeout(this.loadingTimer);
      this.loadingTimer = undefined;
    }
    this.showLoading(false);
  }
}

export class VideoPage extends BasePage {
  private readonly video: HTMLVideoElement;
  private readonly poster: HTMLImageElement;
  private readonly controls: HTMLElement;
  private readonly playButton: HTMLButtonElement;
  private readonly timeline: HTMLInputElement;
  private readonly timeLabel: HTMLElement;
  private posterInfo?: ImageInfo;
  private loadStarted = false;
  private firstFrameReady = false;
  private controlsVisible = false;
  private controlsVisibleBeforeDismiss = false;
  private wasPlayingBeforeDismiss = false;

  constructor(
    index: number,
    item: LevixelMediaItem,
    delegate: ViewerPageDelegate,
    initialPreview?: ImageInfo,
  ) {
    super(index, item, delegate);
    this.video = document.createElement('video');
    this.video.className = 'video';
    this.video.playsInline = true;
    this.video.preload = 'auto';
    this.video.controls = false;
    this.video.setAttribute('aria-label', item.alt || 'Video');
    this.poster = document.createElement('img');
    this.poster.className = 'poster';
    this.poster.alt = '';
    this.poster.setAttribute('aria-hidden', 'true');
    this.poster.draggable = false;
    this.poster.decoding = 'async';
    this.controls = document.createElement('div');
    this.controls.className = 'video-controls';
    this.controls.dataset.visible = 'false';
    this.controls.dataset.levixelControl = '';
    this.controls.setAttribute('aria-hidden', 'true');
    this.playButton = document.createElement('button');
    this.playButton.type = 'button';
    this.playButton.className = 'control-button';
    this.playButton.dataset.levixelControl = '';
    this.playButton.tabIndex = -1;
    this.timeline = document.createElement('input');
    this.timeline.type = 'range';
    this.timeline.className = 'timeline';
    this.timeline.min = '0';
    this.timeline.max = '1';
    this.timeline.step = '0.01';
    this.timeline.value = '0';
    this.timeline.dataset.levixelControl = '';
    this.timeline.tabIndex = -1;
    this.timeline.setAttribute('aria-label', 'Video position');
    this.timeLabel = document.createElement('span');
    this.timeLabel.className = 'time-label';
    this.timeLabel.textContent = '00:00 / 00:00';
    this.updatePlayButton();
    this.controls.append(this.playButton, this.timeline, this.timeLabel);
    this.mediaShell.append(this.video, this.poster, this.controls);
    if (initialPreview)
      this.applyPoster(initialPreview);
    this.installVideoListeners();
  }

  override setActive(active: boolean): void {
    this.active = active;
    if (active)
      this.element.removeAttribute('aria-hidden');
    else
      this.element.setAttribute('aria-hidden', 'true');
    if (!active) {
      this.setControlsVisible(false, false);
      this.video.pause();
      this.showPoster(false);
      return;
    }
    this.ensureLoaded(true);
    if (this.firstFrameReady)
      this.revealVideo();
  }

  override ensureLoaded(priority = false): void {
    if (!this.loadStarted) {
      this.loadStarted = true;
      this.showLoading(true);
      const generation = ++this.loadGeneration;
      const posterURL = transitionURL(this.item);
      if (posterURL && !this.posterInfo) {
        void loadImage(posterURL, priority).then((info) => {
          if (this.loadGeneration === generation)
            this.applyPoster(info);
        }, () => undefined);
      }
      this.video.src = this.item.url;
      this.video.muted = true;
      this.video.load();
      void this.video.play().catch(() => undefined);
    }
  }

  override updateViewport(size: LevixelSize): void {
    this.viewport = size;
    this.element.style.width = `${size.width}px`;
    this.element.style.height = `${size.height}px`;
  }

  override transitionGeometry(): SharedElementGeometry | null {
    if (!this.posterInfo && !this.firstFrameReady)
      return null;
    const size = this.posterInfo ?? this.itemSize();
    if (!size)
      return this.geometryForElement(this.posterInfo ? this.poster : this.video);
    const fitted = aspectFitRect(size, {
      left: 0,
      top: 0,
      width: this.viewport.width,
      height: this.viewport.height,
    });
    const pageRect = this.element.getBoundingClientRect();
    const scaleX = pageRect.width / Math.max(this.viewport.width, 1);
    const scaleY = pageRect.height / Math.max(this.viewport.height, 1);
    const content = {
      left: pageRect.left + fitted.left * scaleX,
      top: pageRect.top + fitted.top * scaleY,
      width: fitted.width * scaleX,
      height: fitted.height * scaleY,
    };
    const visible = intersectRect(content, {
      left: 0,
      top: 0,
      width: this.viewport.width,
      height: this.viewport.height,
    });
    if (!visible)
      return null;
    return {
      visible,
      content: {
        left: content.left - visible.left,
        top: content.top - visible.top,
        width: content.width,
        height: content.height,
      },
      cornerRadius: 0,
    };
  }

  override transitionSource(): string | undefined {
    return this.poster.currentSrc || this.poster.src || this.posterInfo?.src;
  }

  override togglePrimaryAction(_point: { x: number; y: number }): void {
    this.setControlsVisible(!this.controlsVisible, true);
  }

  override prepareForDismissDrag(): void {
    this.controlsVisibleBeforeDismiss = this.controlsVisible;
    this.wasPlayingBeforeDismiss = !this.video.paused;
    this.setControlsVisible(false, false);
    this.video.pause();
    this.showPoster(false);
  }

  override restoreAfterDismissCancelled(): void {
    if (this.firstFrameReady)
      this.revealVideo(this.wasPlayingBeforeDismiss);
    this.setControlsVisible(this.controlsVisibleBeforeDismiss, false);
    this.controlsVisibleBeforeDismiss = false;
  }

  override prepareForReturnAnimation(): void {
    this.controlsVisibleBeforeDismiss = false;
    this.setControlsVisible(false, false);
    this.video.pause();
    this.showPoster(false);
  }

  override pauseForBackground(): boolean {
    const wasPlaying = !this.video.paused;
    this.video.pause();
    return wasPlaying;
  }

  override resumeFromBackground(wasPlaying: boolean): void {
    if (this.active && wasPlaying)
      void this.video.play().catch(() => undefined);
  }

  override destroy(): void {
    super.destroy();
    this.video.pause();
    this.video.removeAttribute('src');
    this.video.load();
  }

  private installVideoListeners(): void {
    this.video.addEventListener('loadeddata', () => this.handleFirstFrame());
    this.video.addEventListener('canplay', () => this.handleFirstFrame());
    this.video.addEventListener('error', () => this.showLoading(false));
    this.video.addEventListener('play', () => this.updatePlayButton());
    this.video.addEventListener('pause', () => this.updatePlayButton());
    this.video.addEventListener('timeupdate', () => this.updateTimeline());
    this.video.addEventListener('durationchange', () => this.updateTimeline());
    this.video.addEventListener('ended', () => this.updatePlayButton());
    this.playButton.addEventListener('click', (event) => {
      event.stopPropagation();
      if (this.video.paused)
        void this.video.play().catch(() => undefined);
      else
        this.video.pause();
    });
    const beginInteraction = (): void => this.delegate.controlsInteractionChanged(true);
    const endInteraction = (): void => this.delegate.controlsInteractionChanged(false);
    this.timeline.addEventListener('pointerdown', beginInteraction);
    this.timeline.addEventListener('pointerup', endInteraction);
    this.timeline.addEventListener('pointercancel', endInteraction);
    this.timeline.addEventListener('input', () => {
      const duration = Number.isFinite(this.video.duration) ? this.video.duration : 0;
      if (duration > 0)
        this.video.currentTime = Number(this.timeline.value) * duration;
    });
  }

  private handleFirstFrame(): void {
    if (this.firstFrameReady)
      return;
    this.firstFrameReady = true;
    this.showLoading(false);
    this.video.pause();
    try {
      this.video.currentTime = 0;
    }
    catch (_) {}
    this.video.muted = false;
    if (this.active)
      this.revealVideo();
  }

  private revealVideo(tryPlayback = true): void {
    this.video.style.transition = 'opacity 220ms ease-in-out';
    this.poster.style.transition = 'opacity 220ms ease-in-out';
    this.video.style.opacity = '1';
    this.poster.style.opacity = '0';
    if (tryPlayback)
      void this.video.play().catch(() => this.updatePlayButton());
  }

  private showPoster(animated: boolean): void {
    const transition = animated ? 'opacity 220ms ease-in-out' : 'none';
    this.video.style.transition = transition;
    this.poster.style.transition = transition;
    this.video.style.opacity = '0';
    this.poster.style.opacity = '1';
  }

  private setControlsVisible(visible: boolean, animated: boolean): void {
    this.controlsVisible = visible;
    this.controls.style.transitionDuration = animated ? '220ms' : '0ms';
    this.controls.dataset.visible = String(visible);
    this.controls.setAttribute('aria-hidden', String(!visible));
    this.playButton.tabIndex = visible ? 0 : -1;
    this.timeline.tabIndex = visible ? 0 : -1;
    if (this.active)
      this.delegate.videoChromeChanged(visible);
  }

  private applyPoster(info: ImageInfo): void {
    this.posterInfo = info;
    this.poster.src = info.src;
  }

  private itemSize(): LevixelSize | undefined {
    return this.item.width && this.item.height
      ? { width: this.item.width, height: this.item.height }
      : undefined;
  }

  private updatePlayButton(): void {
    const paused = this.video?.paused ?? true;
    this.playButton.setAttribute('aria-label', paused ? 'Play video' : 'Pause video');
    this.playButton.innerHTML = paused
      ? '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>'
      : '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 5h4v14H6zm8 0h4v14h-4z"/></svg>';
  }

  private updateTimeline(): void {
    const duration = Number.isFinite(this.video.duration) ? this.video.duration : 0;
    const current = Number.isFinite(this.video.currentTime) ? this.video.currentTime : 0;
    this.timeline.value = duration > 0 ? String(clamp(current / duration, 0, 1)) : '0';
    this.timeLabel.textContent = `${formatTime(current)} / ${formatTime(duration)}`;
  }
}

export function createPage(
  index: number,
  item: LevixelMediaItem,
  delegate: ViewerPageDelegate,
  initialPreview?: ImageInfo,
): ViewerPage {
  return item.type === 'video'
    ? new VideoPage(index, item, delegate, initialPreview)
    : new ImagePage(index, item, delegate, initialPreview);
}

function formatTime(value: number): string {
  const seconds = Math.max(0, Math.floor(Number.isFinite(value) ? value : 0));
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
}
