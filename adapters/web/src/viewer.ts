import {
  currentViewport,
  resolveSourceGeometry,
  type SharedElementGeometry,
  type ViewportMetrics,
} from './geometry.js';
import { createPage, type PinchState, type ViewerPage } from './pages.js';
import { imageInfoFromElement, peekImage, transitionURL } from './media-cache.js';
import { LEVIXEL_STYLES } from './styles.js';
import type {
  ImageInfo,
  LevixelEvent,
  LevixelMediaItem,
  LevixelOpenResult,
  LevixelSize,
  NormalizedOpenOptions,
  SourceBinding,
} from './types.js';

type GestureMode = 'pending' | 'horizontal' | 'vertical' | 'pan' | 'pinch' | 'reanchor';

interface PointerPoint {
  id: number;
  x: number;
  y: number;
  time: number;
}

interface GestureSample {
  x: number;
  y: number;
  time: number;
}

interface ActiveGesture {
  mode: GestureMode;
  start: PointerPoint;
  previousSample: GestureSample;
  lastSample: GestureSample;
  panStart?: { x: number; y: number };
  pinchStartDistance?: number;
  pinchState?: PinchState;
  horizontalDelta: number;
  verticalDelta: { x: number; y: number };
}

interface ViewerCallbacks {
  emit(event: LevixelEvent): void;
  requestClose(): void;
}

interface HiddenSource {
  element: HTMLElement;
  visibility: string;
  index: number;
}

const OPEN_DURATION = 320;
const CLOSE_DURATION = 240;
const SIMPLE_DURATION = 180;
const PAGE_DURATION = 260;
const CANCEL_DRAG_DURATION = 200;
const TAP_DELAY = 270;
const MOVE_THRESHOLD = 8;

export class LevixelWebViewer {
  readonly galleryId: string;

  private readonly options: NormalizedOpenOptions;
  private readonly bindings: SourceBinding[];
  private readonly initialPreviews: Array<ImageInfo | undefined>;
  private readonly callbacks: ViewerCallbacks;
  private readonly host: HTMLElement;
  private readonly shadow: ShadowRoot;
  private readonly root: HTMLElement;
  private readonly backdrop: HTMLElement;
  private readonly content: HTMLElement;
  private readonly track: HTMLElement;
  private readonly closeButton: HTMLButtonElement;
  private readonly liveRegion: HTMLElement;
  private readonly pages: ViewerPage[];
  private readonly documentGuard: DocumentGuard;
  private readonly pointers = new Map<number, PointerPoint>();
  private readonly activeAnimations = new Set<Animation>();
  private readonly backgroundPlayback = new Map<number, boolean>();
  private viewport: ViewportMetrics;
  private currentIndex: number;
  private gesture: ActiveGesture | undefined;
  private trackOffset = 0;
  private hiddenSource: HiddenSource | undefined;
  private sourceEventIndex: number | undefined;
  private tapTimer: number | undefined;
  private lastTap: { x: number; y: number; time: number } | undefined;
  private controlsInteractionActive = false;
  private navigating = false;
  private destroyed = false;
  private closing = false;
  private opened = false;
  private reducedMotion = false;

  constructor(
    options: NormalizedOpenOptions,
    bindings: SourceBinding[],
    previews: Array<ImageInfo | undefined>,
    callbacks: ViewerCallbacks,
  ) {
    this.options = options;
    this.bindings = bindings;
    this.initialPreviews = previews;
    this.callbacks = callbacks;
    this.galleryId = createGalleryId();
    this.currentIndex = options.index;
    this.viewport = currentViewport();
    this.reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    this.host = document.createElement('div');
    this.host.dataset.levixelWebRoot = '';
    this.host.dataset.theme = options.theme;
    this.host.dataset.reducedMotion = String(this.reducedMotion);
    this.shadow = this.host.attachShadow({ mode: 'open' });
    const style = document.createElement('style');
    style.textContent = LEVIXEL_STYLES;
    this.root = document.createElement('div');
    this.root.className = 'root';
    this.root.tabIndex = -1;
    this.root.setAttribute('role', 'dialog');
    this.root.setAttribute('aria-modal', 'true');
    this.root.setAttribute('aria-label', 'Media viewer');
    this.backdrop = document.createElement('div');
    this.backdrop.className = 'backdrop';
    this.content = document.createElement('div');
    this.content.className = 'content';
    this.track = document.createElement('div');
    this.track.className = 'track';
    this.closeButton = createCloseButton();
    this.liveRegion = document.createElement('div');
    this.liveRegion.className = 'sr-only';
    this.liveRegion.setAttribute('aria-live', 'polite');
    this.content.append(this.track, this.closeButton, this.liveRegion);
    this.root.append(this.backdrop, this.content);
    this.shadow.append(style, this.root);

    this.pages = options.items.map((item, index) => createPage(
      index,
      item,
      {
        requestClose: () => this.callbacks.requestClose(),
        videoChromeChanged: visible => this.updateVideoChrome(index, visible),
        controlsInteractionChanged: active => { this.controlsInteractionActive = active; },
      },
      previews[index],
    ));
    this.track.append(...this.pages.map(page => page.element));
    document.body.append(this.host);
    this.documentGuard = new DocumentGuard(this.host);
    this.installListeners();
    this.updateViewport(true);
    this.updateActivePages();
  }

  async open(): Promise<LevixelOpenResult> {
    await nextFrame();
    this.assertAlive();
    const sourceGeometry = this.resolveSourceGeometry(this.currentIndex);
    const page = this.currentPage();
    const targetGeometry = page.transitionGeometry();
    const source = this.transitionSource(this.currentIndex) ?? page.transitionSource();

    if (this.options.sourceVisibility === 'hidden')
      this.hideSourceElement(this.currentIndex);
    if (sourceGeometry && targetGeometry && source) {
      page.setMediaHidden(true);
      await this.animateSharedElement(source, sourceGeometry, targetGeometry, true, () => {
        page.setMediaHidden(false);
        this.backdrop.style.opacity = '1';
        this.content.style.opacity = '1';
      });
      this.assertAlive();
    }
    else {
      await this.animateSimpleOpen();
      this.assertAlive();
    }

    this.backdrop.style.opacity = '1';
    this.content.style.opacity = '1';
    this.opened = true;
    if (this.options.sourceVisibility === 'hidden') {
      this.sourceEventIndex = this.currentIndex;
      this.emitSourceVisibility(true, this.currentIndex);
    }
    this.root.focus({ preventScroll: true });
    this.announceIndex();
    return {
      index: this.currentIndex,
      count: this.pages.length,
      galleryId: this.galleryId,
    };
  }

  async close(animated: boolean, emitDismiss: boolean): Promise<void> {
    if (this.destroyed || this.closing)
      return;
    this.closing = true;
    this.cancelAnimations();
    this.clearTapTimer();
    this.cancelGesture(false);
    const page = this.currentPage();
    page.prepareForReturnAnimation();
    const fromGeometry = page.transitionGeometry();
    const toGeometry = this.resolveSourceGeometry(this.currentIndex);
    const source = page.transitionSource() ?? this.transitionSource(this.currentIndex);

    if (animated && this.opened && fromGeometry && toGeometry && source) {
      page.setMediaHidden(true);
      await this.animateSharedElement(source, fromGeometry, toGeometry, false);
    }
    else if (animated && this.opened) {
      await this.animateSimpleClose();
    }
    this.finish(emitDismiss);
  }

  replace(): void {
    if (this.destroyed)
      return;
    this.closing = true;
    this.cancelAnimations();
    this.finish(false);
  }

  isClosing(): boolean {
    return this.closing && !this.destroyed;
  }

  private finish(emitDismiss: boolean): void {
    if (this.destroyed)
      return;
    this.destroyed = true;
    this.cancelAnimations();
    this.clearTapTimer();
    this.removeListeners();
    this.pages.forEach(page => page.destroy());
    this.restoreSourceElement();
    if (this.sourceEventIndex !== undefined) {
      this.emitSourceVisibility(false, this.sourceEventIndex);
      this.sourceEventIndex = undefined;
    }
    this.documentGuard.restore();
    this.host.remove();
    if (emitDismiss)
      this.emit('dismiss', {});
  }

  private installListeners(): void {
    this.root.addEventListener('pointerdown', this.handlePointerDown);
    this.root.addEventListener('pointermove', this.handlePointerMove);
    this.root.addEventListener('pointerup', this.handlePointerEnd);
    this.root.addEventListener('pointercancel', this.handlePointerEnd);
    this.root.addEventListener('lostpointercapture', this.handleLostPointerCapture);
    this.root.addEventListener('wheel', this.handleWheel, { passive: false });
    this.closeButton.addEventListener('click', this.handleCloseButton);
    window.addEventListener('keydown', this.handleKeyDown);
    window.addEventListener('resize', this.handleResize);
    document.addEventListener('visibilitychange', this.handleVisibilityChange);
    window.visualViewport?.addEventListener('resize', this.handleResize);
    window.visualViewport?.addEventListener('scroll', this.handleResize);
  }

  private removeListeners(): void {
    this.root.removeEventListener('pointerdown', this.handlePointerDown);
    this.root.removeEventListener('pointermove', this.handlePointerMove);
    this.root.removeEventListener('pointerup', this.handlePointerEnd);
    this.root.removeEventListener('pointercancel', this.handlePointerEnd);
    this.root.removeEventListener('lostpointercapture', this.handleLostPointerCapture);
    this.root.removeEventListener('wheel', this.handleWheel);
    this.closeButton.removeEventListener('click', this.handleCloseButton);
    window.removeEventListener('keydown', this.handleKeyDown);
    window.removeEventListener('resize', this.handleResize);
    document.removeEventListener('visibilitychange', this.handleVisibilityChange);
    window.visualViewport?.removeEventListener('resize', this.handleResize);
    window.visualViewport?.removeEventListener('scroll', this.handleResize);
  }

  private readonly handlePointerDown = (event: PointerEvent): void => {
    if (
      this.destroyed
      || this.closing
      || !this.opened
      || this.navigating
      || this.currentPage().isControlTarget(event.target)
    )
      return;
    if (event.button !== 0 && event.pointerType === 'mouse')
      return;
    const point = pointerPoint(event);
    try {
      this.root.setPointerCapture(event.pointerId);
    }
    catch (_) {}
    this.pointers.set(event.pointerId, point);

    if (this.pointers.size === 1) {
      this.gesture = {
        mode: 'pending',
        start: point,
        previousSample: point,
        lastSample: point,
        horizontalDelta: 0,
        verticalDelta: { x: 0, y: 0 },
      };
      return;
    }
    if (this.pointers.size === 2) {
      this.clearTapTimer();
      const pair = this.pointerPair();
      if (!pair)
        return;
      const center = midpoint(pair[0], pair[1]);
      const pinchState = this.currentPage().beginPinch(center);
      if (!pinchState) {
        this.gesture = { ...this.gesture!, mode: 'reanchor' };
        return;
      }
      this.gesture = {
        ...this.gesture!,
        mode: 'pinch',
        pinchStartDistance: distance(pair[0], pair[1]),
        pinchState,
      };
      event.preventDefault();
    }
  };

  private readonly handlePointerMove = (event: PointerEvent): void => {
    if (!this.gesture || !this.pointers.has(event.pointerId) || this.destroyed || this.closing)
      return;
    const point = pointerPoint(event);
    this.pointers.set(event.pointerId, point);
    this.updateSamples(point);

    if (this.pointers.size >= 2) {
      if (this.gesture.mode !== 'pinch')
        return;
      const pair = this.pointerPair();
      const startDistance = this.gesture.pinchStartDistance;
      const state = this.gesture.pinchState;
      if (!pair || !startDistance || !state)
        return;
      this.currentPage().updatePinch(
        state,
        distance(pair[0], pair[1]) / startDistance,
        midpoint(pair[0], pair[1]),
      );
      event.preventDefault();
      return;
    }
    if (this.gesture.mode === 'pinch' || this.gesture.mode === 'reanchor')
      return;

    const delta = {
      x: point.x - this.gesture.start.x,
      y: point.y - this.gesture.start.y,
    };
    if (this.gesture.mode === 'pending') {
      if (Math.hypot(delta.x, delta.y) <= MOVE_THRESHOLD)
        return;
      if (this.currentPage().isZoomed()) {
        this.gesture.mode = 'pan';
        this.gesture.panStart = this.currentPage().beginPan();
      }
      else if (
        !this.controlsInteractionActive
        && Math.abs(delta.y) > MOVE_THRESHOLD
        && Math.abs(delta.y) > Math.abs(delta.x) * 1.02
      ) {
        this.gesture.mode = 'vertical';
        this.currentPage().prepareForDismissDrag();
        this.setVideoChrome(false);
      }
      else {
        this.gesture.mode = 'horizontal';
      }
      this.clearTapTimer();
    }

    if (this.gesture.mode === 'pan' && this.gesture.panStart) {
      this.currentPage().updatePan(this.gesture.panStart, delta);
    }
    else if (this.gesture.mode === 'horizontal') {
      const resisted = this.resistedHorizontalDelta(delta.x);
      this.gesture.horizontalDelta = resisted;
      this.applyTrackOffset(this.baseTrackOffset() + resisted);
    }
    else if (this.gesture.mode === 'vertical') {
      this.gesture.verticalDelta = delta;
      this.applyVerticalDrag(delta);
    }
    event.preventDefault();
  };

  private readonly handlePointerEnd = (event: PointerEvent): void => {
    if (!this.pointers.has(event.pointerId))
      return;
    const point = pointerPoint(event);
    this.updateSamples(point);
    this.pointers.delete(event.pointerId);
    try {
      if (this.root.hasPointerCapture(event.pointerId))
        this.root.releasePointerCapture(event.pointerId);
    }
    catch (_) {}
    if (!this.gesture)
      return;
    if (event.type === 'pointercancel') {
      this.cancelGesture(true);
      return;
    }
    if (this.gesture.mode === 'pinch' && this.pointers.size === 1) {
      this.gesture.mode = 'reanchor';
      return;
    }
    if (this.pointers.size > 0)
      return;

    const gesture = this.gesture;
    this.gesture = undefined;
    if (gesture.mode === 'horizontal')
      void this.finishHorizontalGesture(gesture);
    else if (gesture.mode === 'vertical')
      void this.finishVerticalGesture(gesture);
    else if (gesture.mode === 'pending')
      this.handleTap(point);
  };

  private readonly handleLostPointerCapture = (event: PointerEvent): void => {
    if (this.pointers.has(event.pointerId))
      this.handlePointerEnd(event);
  };

  private readonly handleWheel = (event: WheelEvent): void => {
    if (
      (!event.ctrlKey && !event.metaKey)
      || this.destroyed
      || this.closing
      || !this.opened
      || this.navigating
    )
      return;
    const page = this.currentPage();
    const state = page.beginPinch({ x: event.clientX, y: event.clientY });
    if (!state)
      return;
    event.preventDefault();
    const scale = Math.exp(-event.deltaY * 0.01);
    page.updatePinch(state, scale, { x: event.clientX, y: event.clientY });
  };

  private readonly handleKeyDown = (event: KeyboardEvent): void => {
    if (this.destroyed || this.closing)
      return;
    if (event.key === 'Tab') {
      this.trapFocus(event);
      return;
    }
    if (isEditableTarget(event.target))
      return;
    if (event.key === 'Escape') {
      event.preventDefault();
      this.callbacks.requestClose();
      return;
    }
    if (this.currentPage().isZoomed() || this.controlsInteractionActive || this.navigating)
      return;
    if (event.key === 'ArrowLeft') {
      event.preventDefault();
      void this.goToIndex(this.currentIndex - 1, true);
    }
    else if (event.key === 'ArrowRight') {
      event.preventDefault();
      void this.goToIndex(this.currentIndex + 1, true);
    }
  };

  private readonly handleResize = (): void => {
    if (this.destroyed)
      return;
    this.cancelGesture(false);
    this.updateViewport(false);
  };

  private readonly handleVisibilityChange = (): void => {
    if (this.destroyed)
      return;
    this.cancelGesture(false);
    if (document.visibilityState !== 'visible') {
      this.pages.forEach((page, index) => {
        this.backgroundPlayback.set(index, page.pauseForBackground());
      });
      return;
    }
    this.pages.forEach((page, index) => {
      page.resumeFromBackground(this.backgroundPlayback.get(index) === true);
    });
    this.backgroundPlayback.clear();
  };

  private readonly handleCloseButton = (event: Event): void => {
    event.stopPropagation();
    this.callbacks.requestClose();
  };

  private updateViewport(initial: boolean): void {
    this.viewport = currentViewport();
    Object.assign(this.host.style, {
      left: `${this.viewport.left}px`,
      top: `${this.viewport.top}px`,
      width: `${this.viewport.width}px`,
      height: `${this.viewport.height}px`,
    });
    const size = { width: this.viewport.width, height: this.viewport.height };
    this.pages.forEach(page => page.updateViewport(size));
    this.track.style.width = `${this.pages.length * size.width}px`;
    this.applyTrackOffset(-this.currentIndex * size.width);
    if (!initial)
      this.updateActivePages();
  }

  private updateActivePages(): void {
    this.pages.forEach((page, index) => {
      page.setActive(index === this.currentIndex);
      if (Math.abs(index - this.currentIndex) <= 1)
        page.ensureLoaded(index === this.currentIndex);
    });
    this.setVideoChrome(false);
  }

  private currentPage(): ViewerPage {
    const page = this.pages[this.currentIndex];
    if (!page)
      throw new Error('Levixel viewer index is outside the page collection');
    return page;
  }

  private handleTap(point: PointerPoint): void {
    const page = this.currentPage();
    if (page.item.type === 'video') {
      page.togglePrimaryAction(point);
      return;
    }
    const now = performance.now();
    const previous = this.lastTap;
    if (previous && now - previous.time <= TAP_DELAY && distance(previous, point) <= 28) {
      this.clearTapTimer();
      this.lastTap = undefined;
      page.togglePrimaryAction(point);
      return;
    }
    this.lastTap = { x: point.x, y: point.y, time: now };
    this.tapTimer = window.setTimeout(() => {
      this.tapTimer = undefined;
      this.lastTap = undefined;
      this.callbacks.requestClose();
    }, TAP_DELAY);
  }

  private async finishHorizontalGesture(gesture: ActiveGesture): Promise<void> {
    const { velocityX } = gestureVelocity(gesture);
    const delta = gesture.horizontalDelta;
    const distanceThreshold = this.viewport.width * 0.16;
    const flingThreshold = this.viewport.width * 0.06;
    let target = this.currentIndex;
    if (Math.abs(delta) > distanceThreshold || (Math.abs(delta) > flingThreshold && Math.abs(velocityX) > 700))
      target += delta < 0 ? 1 : -1;
    await this.goToIndex(target, true);
  }

  private async finishVerticalGesture(gesture: ActiveGesture): Promise<void> {
    const delta = gesture.verticalDelta;
    const { velocityY } = gestureVelocity(gesture);
    const dismissByDistance = Math.abs(delta.y) > this.viewport.height * 0.16;
    const dismissByFling = Math.abs(delta.y) > this.viewport.height * 0.06
      && Math.abs(velocityY) > 1300;
    if (dismissByDistance || dismissByFling) {
      this.callbacks.requestClose();
      return;
    }
    await Promise.all([
      this.animateElement(
        this.currentPage().element,
        [{ transform: this.currentPage().element.style.transform }, { transform: 'none' }],
        CANCEL_DRAG_DURATION,
        'ease-out',
      ),
      this.animateElement(
        this.backdrop,
        [{ opacity: this.backdrop.style.opacity }, { opacity: '1' }],
        CANCEL_DRAG_DURATION,
        'ease-out',
      ),
    ]);
    if (this.destroyed || this.closing)
      return;
    this.currentPage().element.style.transform = 'none';
    this.backdrop.style.opacity = '1';
    this.currentPage().restoreAfterDismissCancelled();
  }

  private async goToIndex(requestedIndex: number, animated: boolean): Promise<void> {
    if (this.destroyed || this.closing || this.navigating)
      return;
    this.navigating = true;
    const targetIndex = Math.min(Math.max(requestedIndex, 0), this.pages.length - 1);
    const fromOffset = this.trackOffset;
    const targetOffset = -targetIndex * this.viewport.width;
    try {
      if (animated && Math.abs(fromOffset - targetOffset) > 0.5) {
        await this.animateElement(
          this.track,
          [
            { transform: `translate3d(${fromOffset}px, 0, 0)` },
            { transform: `translate3d(${targetOffset}px, 0, 0)` },
          ],
          PAGE_DURATION,
          'cubic-bezier(0.22, 1, 0.36, 1)',
        );
      }
      if (this.destroyed || this.closing)
        return;
      this.applyTrackOffset(-targetIndex * this.viewport.width);
      if (targetIndex === this.currentIndex)
        return;
      const previousIndex = this.currentIndex;
      if (this.options.sourceVisibility === 'hidden') {
        this.restoreSourceElement();
        if (this.sourceEventIndex !== undefined)
          this.emitSourceVisibility(false, this.sourceEventIndex);
      }
      this.currentIndex = targetIndex;
      this.updateActivePages();
      if (this.options.sourceVisibility === 'hidden') {
        this.hideSourceElement(targetIndex);
        this.sourceEventIndex = targetIndex;
        this.emitSourceVisibility(true, targetIndex);
      }
      this.emit('indexChange', { currentIndex: targetIndex });
      this.announceIndex();
      if (previousIndex !== targetIndex)
        this.pages[previousIndex]?.setActive(false);
    }
    finally {
      this.navigating = false;
    }
  }

  private applyTrackOffset(offset: number): void {
    this.trackOffset = offset;
    this.track.style.transform = `translate3d(${offset}px, 0, 0)`;
  }

  private baseTrackOffset(): number {
    return -this.currentIndex * this.viewport.width;
  }

  private resistedHorizontalDelta(delta: number): number {
    if ((this.currentIndex === 0 && delta > 0) || (this.currentIndex === this.pages.length - 1 && delta < 0))
      return delta * 0.35;
    return delta;
  }

  private applyVerticalDrag(delta: { x: number; y: number }): void {
    const progress = Math.min(Math.abs(delta.y) / Math.max(this.viewport.height, 1), 1);
    const scale = Math.max(0.84, 1 - progress * 0.16);
    this.currentPage().element.style.transform = `translate3d(${delta.x}px, ${delta.y}px, 0) scale(${scale})`;
    this.backdrop.style.opacity = String(Math.max(0, 1 - Math.min(0.9, progress * 1.25)));
  }

  private cancelGesture(animate: boolean): void {
    if (!this.gesture && this.pointers.size === 0)
      return;
    const mode = this.gesture?.mode;
    this.pointers.clear();
    this.gesture = undefined;
    if (mode === 'horizontal') {
      const finish = (): void => this.applyTrackOffset(this.baseTrackOffset());
      if (animate) {
        void this.animateElement(
          this.track,
          [
            { transform: `translate3d(${this.trackOffset}px, 0, 0)` },
            { transform: `translate3d(${this.baseTrackOffset()}px, 0, 0)` },
          ],
          CANCEL_DRAG_DURATION,
          'ease-out',
        ).then(() => {
          if (!this.destroyed && !this.closing)
            finish();
        });
      }
      else
        finish();
    }
    if (mode === 'vertical') {
      this.currentPage().element.style.transform = 'none';
      this.backdrop.style.opacity = '1';
      this.currentPage().restoreAfterDismissCancelled();
    }
  }

  private pointerPair(): [PointerPoint, PointerPoint] | undefined {
    const points = [...this.pointers.values()];
    const first = points[0];
    const second = points[1];
    return first && second ? [first, second] : undefined;
  }

  private updateSamples(point: PointerPoint): void {
    if (!this.gesture)
      return;
    if (point.time - this.gesture.lastSample.time >= 16)
      this.gesture.previousSample = this.gesture.lastSample;
    this.gesture.lastSample = point;
  }

  private transitionSource(index: number): string | undefined {
    const binding = this.bindings[index];
    return imageInfoFromElement(binding?.element ?? null)?.src
      ?? binding?.preview?.src
      ?? peekImage(transitionURL(this.options.items[index]!))?.src;
  }

  private resolveSourceGeometry(index: number): SharedElementGeometry | null {
    const binding = this.bindings[index];
    const item = this.options.items[index];
    if (!binding || !item)
      return null;
    let hint = binding.hint;
    if (binding.element?.isConnected) {
      const rect = binding.element.getBoundingClientRect();
      if (rect.width > 1 && rect.height > 1 && hint) {
        const livePreview = imageInfoFromElement(binding.element) ?? binding.preview;
        hint = {
          ...hint,
          rect: { left: rect.left, top: rect.top, width: rect.width, height: rect.height },
          coordinateSpace: 'viewport',
          rectScale: 1,
          ...(livePreview ? { imageSize: { width: livePreview.width, height: livePreview.height } } : {}),
        };
      }
    }
    if (!hint)
      return null;
    const preview = binding.preview ?? peekImage(transitionURL(item));
    const fallback = preview
      ? { width: preview.width, height: preview.height }
      : itemSize(item);
    return resolveSourceGeometry(hint, fallback, this.viewport);
  }

  private hideSourceElement(index: number): void {
    this.restoreSourceElement();
    const element = this.bindings[index]?.element;
    if (!element?.isConnected)
      return;
    this.hiddenSource = { element, visibility: element.style.visibility, index };
    element.style.visibility = 'hidden';
  }

  private restoreSourceElement(): void {
    if (!this.hiddenSource)
      return;
    this.hiddenSource.element.style.visibility = this.hiddenSource.visibility;
    this.hiddenSource = undefined;
  }

  private async animateSharedElement(
    source: string,
    from: SharedElementGeometry,
    to: SharedElementGeometry,
    opening: boolean,
    beforeSnapshotRemoval?: () => void,
  ): Promise<void> {
    const snapshot = document.createElement('div');
    snapshot.className = 'snapshot';
    const image = document.createElement('img');
    image.className = 'snapshot-image';
    image.src = source;
    image.alt = '';
    image.draggable = false;
    snapshot.append(image);
    this.root.append(snapshot);
    applyGeometry(snapshot, image, from);
    const duration = this.reducedMotion ? 0 : (opening ? OPEN_DURATION : CLOSE_DURATION);
    const backgroundFrom = opening ? '0' : (this.backdrop.style.opacity || '1');
    const backgroundTo = opening ? '1' : '0';
    const contentFrom = opening ? '0' : (this.content.style.opacity || '1');
    const contentTo = opening ? '0' : '0';
    const outerAnimation = this.animateElement(
      snapshot,
      [geometryKeyframe(from), geometryKeyframe(to)],
      duration,
      'cubic-bezier(0.22, 1, 0.36, 1)',
    );
    const imageAnimation = this.animateElement(
      image,
      [contentKeyframe(from), contentKeyframe(to)],
      duration,
      'cubic-bezier(0.22, 1, 0.36, 1)',
    );
    const backgroundAnimation = this.animateElement(
      this.backdrop,
      [{ opacity: backgroundFrom }, { opacity: backgroundTo }],
      duration,
      opening ? 'ease-in-out' : 'ease-in-out',
    );
    const contentAnimation = this.animateElement(
      this.content,
      [{ opacity: contentFrom }, { opacity: contentTo }],
      duration,
      'ease-in-out',
    );
    await Promise.all([outerAnimation, imageAnimation, backgroundAnimation, contentAnimation]);
    applyGeometry(snapshot, image, to);
    this.backdrop.style.opacity = backgroundTo;
    this.content.style.opacity = contentTo;
    if (beforeSnapshotRemoval) {
      beforeSnapshotRemoval();
      // Keep the settled snapshot above the real media for one painted frame.
      // Two animation-frame boundaries prevent the follow-up removal microtask
      // from running before the browser has committed that overlap.
      await nextFrame();
    }
    snapshot.remove();
  }

  private async animateSimpleOpen(): Promise<void> {
    const duration = this.reducedMotion ? 0 : SIMPLE_DURATION;
    await Promise.all([
      this.animateElement(this.backdrop, [{ opacity: '0' }, { opacity: '1' }], duration, 'ease-out'),
      this.animateElement(this.content, [{ opacity: '0' }, { opacity: '1' }], duration, 'ease-out'),
    ]);
  }

  private async animateSimpleClose(): Promise<void> {
    const duration = this.reducedMotion ? 0 : SIMPLE_DURATION;
    await Promise.all([
      this.animateElement(
        this.backdrop,
        [{ opacity: this.backdrop.style.opacity || '1' }, { opacity: '0' }],
        duration,
        'ease-in',
      ),
      this.animateElement(
        this.content,
        [
          { opacity: this.content.style.opacity || '1', transform: 'scale(1)' },
          { opacity: '0', transform: 'scale(0.92)' },
        ],
        duration,
        'ease-in',
      ),
    ]);
  }

  private async animateElement(
    element: HTMLElement,
    keyframes: Keyframe[],
    duration: number,
    easing: string,
  ): Promise<void> {
    if (this.reducedMotion)
      duration = 0;
    if (duration === 0) {
      applyKeyframe(element, keyframes[keyframes.length - 1]);
      return;
    }
    const animation = element.animate(keyframes, { duration, easing, fill: 'both' });
    this.activeAnimations.add(animation);
    let completed = false;
    try {
      await animation.finished;
      completed = true;
    }
    catch (_) {}
    finally {
      this.activeAnimations.delete(animation);
    }
    if (completed && !this.destroyed)
      applyKeyframe(element, keyframes[keyframes.length - 1]);
    animation.cancel();
  }

  private cancelAnimations(): void {
    this.activeAnimations.forEach(animation => animation.cancel());
    this.activeAnimations.clear();
  }

  private updateVideoChrome(index: number, visible: boolean): void {
    if (index !== this.currentIndex)
      return;
    this.setVideoChrome(visible);
  }

  private setVideoChrome(visible: boolean): void {
    const isVideo = this.currentPage().item.type === 'video';
    const show = isVideo && visible;
    this.closeButton.dataset.visible = String(show);
    this.closeButton.setAttribute('aria-hidden', String(!show));
    this.closeButton.tabIndex = show ? 0 : -1;
  }

  private trapFocus(event: KeyboardEvent): void {
    const focusable = [...this.shadow.querySelectorAll<HTMLElement>(
      'button[data-visible="true"], .video-controls[data-visible="true"] button, '
      + '.video-controls[data-visible="true"] input',
    )].filter(element => !element.hasAttribute('disabled'));
    if (focusable.length === 0) {
      event.preventDefault();
      this.root.focus({ preventScroll: true });
      return;
    }
    const active = this.shadow.activeElement;
    let index = focusable.indexOf(active as HTMLElement);
    index += event.shiftKey ? -1 : 1;
    if (index < 0)
      index = focusable.length - 1;
    if (index >= focusable.length)
      index = 0;
    event.preventDefault();
    focusable[index]?.focus({ preventScroll: true });
  }

  private announceIndex(): void {
    const item = this.options.items[this.currentIndex];
    this.liveRegion.textContent = item?.alt || `${item?.type ?? 'media'} ${this.currentIndex + 1}`;
  }

  private emitSourceVisibility(hidden: boolean, index: number): void {
    this.emit('sourceVisibilityChange', { hidden, index, galleryId: this.galleryId });
  }

  private emit(type: LevixelEvent['type'], payload: Record<string, unknown>): void {
    this.callbacks.emit({ type, payload, time: Date.now() });
  }

  private assertAlive(): void {
    if (this.destroyed || this.closing) {
      const error = new Error('Viewer opening was cancelled');
      error.name = 'LevixelCancelledError';
      throw error;
    }
  }

  private clearTapTimer(): void {
    if (this.tapTimer !== undefined) {
      window.clearTimeout(this.tapTimer);
      this.tapTimer = undefined;
    }
    this.lastTap = undefined;
  }

}

class DocumentGuard {
  private readonly activeElement: HTMLElement | null;
  private readonly htmlOverflow: string;
  private readonly htmlOverscrollBehavior: string;
  private readonly bodyOverflow: string;
  private readonly bodyPaddingRight: string;
  private readonly bodyOverscrollBehavior: string;
  private readonly inertStates: Array<{ element: HTMLElement; inert: boolean }>;
  private restored = false;

  constructor(host: HTMLElement) {
    this.activeElement = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    this.htmlOverflow = document.documentElement.style.overflow;
    this.htmlOverscrollBehavior = document.documentElement.style.overscrollBehavior;
    this.bodyOverflow = document.body.style.overflow;
    this.bodyPaddingRight = document.body.style.paddingRight;
    this.bodyOverscrollBehavior = document.body.style.overscrollBehavior;
    const scrollbarWidth = Math.max(0, window.innerWidth - document.documentElement.clientWidth);
    document.documentElement.style.overflow = 'hidden';
    document.documentElement.style.overscrollBehavior = 'none';
    document.body.style.overflow = 'hidden';
    document.body.style.overscrollBehavior = 'none';
    if (scrollbarWidth > 0) {
      const currentPadding = Number.parseFloat(getComputedStyle(document.body).paddingRight) || 0;
      document.body.style.paddingRight = `${currentPadding + scrollbarWidth}px`;
    }
    this.inertStates = [...document.body.children]
      .filter((element): element is HTMLElement => element instanceof HTMLElement && element !== host)
      .map(element => ({ element, inert: element.inert }));
    this.inertStates.forEach(({ element }) => { element.inert = true; });
  }

  restore(): void {
    if (this.restored)
      return;
    this.restored = true;
    document.documentElement.style.overflow = this.htmlOverflow;
    document.documentElement.style.overscrollBehavior = this.htmlOverscrollBehavior;
    document.body.style.overflow = this.bodyOverflow;
    document.body.style.paddingRight = this.bodyPaddingRight;
    document.body.style.overscrollBehavior = this.bodyOverscrollBehavior;
    this.inertStates.forEach(({ element, inert }) => {
      if (element.isConnected)
        element.inert = inert;
    });
    if (this.activeElement?.isConnected)
      this.activeElement.focus({ preventScroll: true });
  }
}

function createCloseButton(): HTMLButtonElement {
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'close-button';
  button.dataset.visible = 'false';
  button.dataset.levixelControl = '';
  button.tabIndex = -1;
  button.setAttribute('aria-label', 'Close viewer');
  button.setAttribute('aria-hidden', 'true');
  button.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M18.3 5.71 12 12l6.3 6.29-1.41 1.42L10.59 13.4l-6.3 6.31-1.42-1.42L9.17 12l-6.3-6.29 1.42-1.42 6.3 6.31 6.3-6.31z"/></svg>';
  return button;
}

function createGalleryId(): string {
  if (typeof crypto.randomUUID === 'function')
    return `web-levixel-${crypto.randomUUID().toLowerCase()}`;
  return `web-levixel-${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`;
}

function pointerPoint(event: PointerEvent): PointerPoint {
  return { id: event.pointerId, x: event.clientX, y: event.clientY, time: event.timeStamp };
}

function distance(first: { x: number; y: number }, second: { x: number; y: number }): number {
  return Math.hypot(second.x - first.x, second.y - first.y);
}

function midpoint(first: PointerPoint, second: PointerPoint): { x: number; y: number } {
  return { x: (first.x + second.x) / 2, y: (first.y + second.y) / 2 };
}

function gestureVelocity(gesture: ActiveGesture): { velocityX: number; velocityY: number } {
  const elapsed = Math.max(gesture.lastSample.time - gesture.previousSample.time, 1);
  return {
    velocityX: (gesture.lastSample.x - gesture.previousSample.x) / elapsed * 1000,
    velocityY: (gesture.lastSample.y - gesture.previousSample.y) / elapsed * 1000,
  };
}

function itemSize(item: LevixelMediaItem): LevixelSize | undefined {
  return item.width && item.height ? { width: item.width, height: item.height } : undefined;
}

function applyGeometry(
  snapshot: HTMLElement,
  image: HTMLElement,
  geometry: SharedElementGeometry,
): void {
  applyKeyframe(snapshot, geometryKeyframe(geometry));
  applyKeyframe(image, contentKeyframe(geometry));
}

function geometryKeyframe(geometry: SharedElementGeometry): Keyframe {
  return {
    left: `${geometry.visible.left}px`,
    top: `${geometry.visible.top}px`,
    width: `${geometry.visible.width}px`,
    height: `${geometry.visible.height}px`,
    borderRadius: `${geometry.cornerRadius}px`,
  };
}

function contentKeyframe(geometry: SharedElementGeometry): Keyframe {
  return {
    left: `${geometry.content.left}px`,
    top: `${geometry.content.top}px`,
    width: `${geometry.content.width}px`,
    height: `${geometry.content.height}px`,
  };
}

function applyKeyframe(element: HTMLElement, keyframe: Keyframe | undefined): void {
  if (!keyframe)
    return;
  for (const [property, value] of Object.entries(keyframe)) {
    if (value !== undefined && value !== null && typeof value !== 'object')
      element.style.setProperty(camelToKebab(property), String(value));
  }
}

function camelToKebab(value: string): string {
  return value.replace(/[A-Z]/g, character => `-${character.toLowerCase()}`);
}

function isEditableTarget(target: EventTarget | null): boolean {
  return target instanceof HTMLInputElement
    || target instanceof HTMLTextAreaElement
    || (target instanceof HTMLElement && target.isContentEditable);
}

function nextFrame(): Promise<void> {
  return new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
}
