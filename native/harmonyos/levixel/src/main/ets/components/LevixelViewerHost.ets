import i18n from '@ohos.i18n';
import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import { LevixelController, resolveLevixelContext } from '../controller/LevixelController';
import type {
  LevixelAction,
  LevixelActionLayout,
  LevixelViewerEvent,
  LevixelMediaContext,
  LevixelMediaItem,
  RectMetrics
} from '../model/LevixelModels';
import {
  snapshotLevixelActions,
  clampLevixelPan,
  cloneRect,
  cloneLevixelViewerEvent,
  LevixelMediaType,
  LevixelSourceImageFit
} from '../model/LevixelModels';
import type { LevixelResolvedSource, LevixelViewerContext } from '../controller/LevixelViewerContext';
import {
  intersectRects,
  mapSourceSnapshotToTarget,
  resolveImageGeometry
} from '../model/LevixelTransitionGeometry';
import type { LevixelTransitionGeometry as SharedElementGeometry } from '../model/LevixelTransitionGeometry';
import { LevixelImageViewer } from './LevixelImageViewer';
import { LevixelVideoPlayer } from './LevixelVideoPlayer';

const OPEN_SNAPSHOT_DURATION_MS: number = 300;
const OPEN_CONTENT_FADE_DURATION_MS: number = 140;
const CLOSE_DURATION_MS: number = 280;
const CLOSE_FADE_DURATION_MS: number = 180;
const RESET_DURATION_MS: number = 200;
const SNAPSHOT_CAPTURE_SCALE: number = 1;
const IMAGE_RESOURCE_CONNECT_TIMEOUT_MS: number = 3000;
const IMAGE_RESOURCE_READ_TIMEOUT_MS: number = 5000;
const MAX_TRANSITION_IMAGE_CACHE_ENTRIES: number = 24;
const MAX_TRANSITION_IMAGE_CACHE_BYTES: number = 48 * 1024 * 1024;
const MAX_TRANSITION_IMAGE_DECODE_PIXELS: number = 2 * 1024 * 1024;

interface SharedElementState {
  pixelMap: image.PixelMap;
  geometry: SharedElementGeometry;
  radius: number;
}

interface OpeningSharedElementState extends SharedElementState {
  targetGeometry: SharedElementGeometry;
  previewPixelMap: image.PixelMap | null;
}

interface TransitionImageResource {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

@Component
export struct LevixelViewerHost {
  controller: LevixelController | null = null;
  @Prop actions: LevixelAction[] = [];
  @Prop actionLayout: LevixelActionLayout = 'list';
  @Prop actionListIcons: boolean = false;
  @State private sessionActionLayout: LevixelActionLayout = 'list';
  @State private sessionActionListIcons: boolean = false;
  @State private actionIconsLoaded: string[] = [];
  @Prop theme: 'dark' | 'light' = 'dark';
  @State private sessionTheme: 'dark' | 'light' = 'dark';
  onEvent: (event: LevixelViewerEvent) => void = (_event: LevixelViewerEvent): void => {};
  @State private actionsVisible: boolean = false;
  @State private actionSheetActive: boolean = false;
  @State private sessionActions: LevixelAction[] = [];
  @State private actionGroups: string[] = [];
  @State private retryVersions: number[] = [];
  @State private failedIds: string[] = [];
  @State private zoomScale: number = 1;
  @State private panX: number = 0;
  @State private panY: number = 0;
  @State private pinchLocked: boolean = false;
  private activeTouchIds: number[] = [];
  private pinchStartScale: number = 1;
  private pinchAnchorX: number = 0;
  private pinchAnchorY: number = 0;
  private panStartX: number = 0;
  private panStartY: number = 0;
  private sessionId: string = '';
  private pendingAction: LevixelAction | null = null;
  private pendingActionEvent: LevixelViewerEvent | null = null;
  private closing: boolean = false;
  private disposed: boolean = false;
  private closeAfterActions: boolean = false;

  private getViewerContext(): LevixelViewerContext {
    return resolveLevixelContext(this.controller);
  }
  @Prop @Watch('handleItemsChanged') items: LevixelMediaItem[] = [];
  private readonly imageResourceCache: Map<string, TransitionImageResource> = new Map<string, TransitionImageResource>();
  private readonly imageResourceRequests: Map<string, Promise<TransitionImageResource | null>> =
    new Map<string, Promise<TransitionImageResource | null>>();
  private imageResourceCacheBytes: number = 0;
  private transitionToken: number = 0;
  private snapshotPixelMap: image.PixelMap | null = null;
  private viewerPreviewItemId: string = '';
  private viewerPreviewPixelMap: image.PixelMap | null = null;
  private viewerRegistrationId: number = 0;

  @State rootWidth: number = 360;
  @State rootHeight: number = 720;
  @State rootLeft: number = 0;
  @State rootTop: number = 0;
  @State sessionItems: LevixelMediaItem[] = [];
  @State currentIndex: number = 0;
  @State viewerOpen: boolean = false;
  @State contentVisible: boolean = false;
  @State contentOpacity: number = 0;
  @State snapshotVisible: boolean = false;
  @State transitionActive: boolean = false;
  @State hiddenViewerMediaId: string = '';
  @State backgroundOpacity: number = 0;
  @State snapshotRect: RectMetrics = { left: 0, top: 0, width: 1, height: 1 };
  @State snapshotContentRect: RectMetrics = { left: 0, top: 0, width: 1, height: 1 };
  @State snapshotRadius: number = 0;
  @State snapshotOpacity: number = 1;
  @State dragOffsetY: number = 0;
  @State dragScale: number = 1;
  @State videoControlGestureActive: boolean = false;

  aboutToAppear(): void {
    this.snapshotItems();
    this.viewerRegistrationId = this.getViewerContext().registerViewer(
      (itemId: string): void => {
        this.openViewer(itemId);
      },
      (itemId: string): void => {
        this.prepareTransitionResource(itemId);
      },
      (): void => { this.closeViewer(); },
      (): boolean => this.retryCurrent(),
      (): boolean => {
        if (this.actionSheetActive) { this.actionsVisible = false; return true; }
        if (this.viewerOpen || this.transitionActive) { this.closeViewer(); return true; }
        return false;
      }
    );
  }

  private handleItemsChanged(): void {
    this.snapshotItems();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    if (this.sessionItems.length > 0) this.finishClose();
    this.transitionToken += 1;
    this.transitionActive = false;
    this.getViewerContext().setHiddenSource('');
    this.getViewerContext().unregisterViewer(this.viewerRegistrationId);
    this.viewerRegistrationId = 0;
    this.imageResourceCache.clear();
    this.imageResourceCacheBytes = 0;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.viewerOpen || this.transitionActive) {
        this.ViewerLayer()
      }

      if (this.snapshotVisible && this.snapshotPixelMap !== null) {
        this.TransitionSnapshot()
      }

    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.actionsVisible, this.ActionDrawer(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: false,
      preferType: SheetType.BOTTOM,
      mode: SheetMode.OVERLAY,
      backgroundColor: '#DEDEDE',
      onDisappear: (): void => { this.finishAction(); }
    })
    .hitTestBehavior(this.viewerOpen || this.transitionActive ? HitTestMode.Default : HitTestMode.None)
    .onAreaChange((_oldArea, newArea) => {
      this.rootLeft = this.asPositionNumber(newArea.globalPosition.x, this.rootLeft);
      this.rootTop = this.asPositionNumber(newArea.globalPosition.y, this.rootTop);
      this.rootWidth = this.asPositiveNumber(newArea.width, this.rootWidth);
      this.rootHeight = this.asPositiveNumber(newArea.height, this.rootHeight);
    })
  }

  @Builder
  private ViewerLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.sessionTheme === 'light' ? Color.White : Color.Black)
        .opacity(this.backgroundOpacity)

      if (this.contentVisible) {
        Stack({ alignContent: Alignment.TopStart }) {
          Swiper() {
            ForEach(this.sessionItems, (item: LevixelMediaItem) => {
              this.ViewerPage(item, this.sessionId)
            }, (item: LevixelMediaItem, index: number): string => item.id + ':' + this.retryVersions[index])
          }
          .index(this.currentIndex)
          .loop(false)
          .indicator(false)
          .disableSwipe(this.transitionActive || this.closing || this.videoControlGestureActive || this.actionSheetActive || this.zoomScale > 1.01 || this.pinchLocked)
          .onChange((index: number) => {
            if (this.closing || this.disposed || index < 0 || index >= this.sessionItems.length) return;
            this.videoControlGestureActive = false;
            this.currentIndex = index;
            this.resetZoom();
            this.emitViewerEvent('indexChange', index);
            this.syncHiddenSourceToCurrentItem();
            this.prepareCurrentTransitionResource();
            this.resetDragState(false);
          })
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .opacity(this.contentOpacity)
        .translate({ x: 0, y: this.dragOffsetY })
        .scale({ x: this.dragScale, y: this.dragScale })
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 8 })
            .onActionUpdate((event) => {
              if (this.videoControlGestureActive || this.zoomScale > 1.01 || this.pinchLocked || this.actionSheetActive) {
                return;
              }
              this.updateVerticalDrag(event.offsetY);
            })
            .onActionEnd((event) => {
              if (this.videoControlGestureActive || this.zoomScale > 1.01 || this.pinchLocked || this.actionSheetActive) {
                this.resetDragState(true);
                return;
              }
              this.finishVerticalDrag(event.velocityY);
            })
            .onActionCancel(() => {
              if (this.videoControlGestureActive || this.zoomScale > 1.01 || this.pinchLocked || this.actionSheetActive) {
                this.resetDragState(true);
                return;
              }
              this.animateDragBack();
            })
        )
      }
      if (this.viewerOpen && !this.transitionActive && this.failedIds.includes(this.sessionItems[this.currentIndex].id)) {
        Button(i18n.System.getSystemLanguage().startsWith('zh') ? '加载失败，重试' : 'Unable to load. Retry')
          .position({ x: '50%', y: '50%' })
          .translate({ x: '-50%', y: '-50%' })
          .onClick(() => { this.retryCurrent(); })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ViewerPage(item: LevixelMediaItem, sessionId: string) {
    Stack({ alignContent: Alignment.Center }) {
      this.ViewerMedia(item, sessionId)
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        event.changedTouches.forEach((touch: TouchObject) => {
          if (!this.activeTouchIds.includes(touch.id)) this.activeTouchIds.push(touch.id);
        });
      } else if (event.type === TouchType.Up) {
        this.activeTouchIds = this.activeTouchIds.filter((id: number): boolean =>
          !event.changedTouches.some((touch: TouchObject): boolean => touch.id === id));
      } else if (event.type === TouchType.Cancel) this.activeTouchIds = [];
      if (this.activeTouchIds.length > 1) this.pinchLocked = true;
      else if (this.activeTouchIds.length === 0) this.pinchLocked = false;
    })
    .gesture(GestureGroup(GestureMode.Exclusive,
      LongPressGesture({ repeat: false, duration: 500 }).tag('levixel-long-press')
        .onAction(() => { this.showActions(); }),
      GestureGroup(GestureMode.Parallel,
      PinchGesture({ fingers: 2 }).tag('levixel-pinch')
        .onActionStart((event: GestureEvent) => {
          this.pinchLocked = true;
          this.resetDragState(true);
          this.pinchStartScale = this.zoomScale;
          this.pinchAnchorX = (event.pinchCenterX - this.rootWidth / 2 - this.panX) / this.zoomScale;
          this.pinchAnchorY = (event.pinchCenterY - this.rootHeight / 2 - this.panY) / this.zoomScale;
        })
        .onActionUpdate((event: GestureEvent) => {
          this.zoomScale = Math.max(1, Math.min(8, this.pinchStartScale * event.scale));
          this.applyPan(item, event.pinchCenterX - this.rootWidth / 2 - this.pinchAnchorX * this.zoomScale,
            event.pinchCenterY - this.rootHeight / 2 - this.pinchAnchorY * this.zoomScale);
        }),
      PanGesture({ direction: PanDirection.All, distance: 8, fingers: 1 }).tag('levixel-pan')
        .onActionStart(() => { this.panStartX = this.panX; this.panStartY = this.panY; })
        .onActionUpdate((event: GestureEvent) => {
          if (!this.pinchLocked) this.applyPan(item, this.panStartX + event.offsetX, this.panStartY + event.offsetY);
        })),
      TapGesture({ count: 2 }).tag('levixel-double-tap')
        .onAction(() => {
          if (this.zoomScale > 1.01) this.resetZoom();
          else this.zoomScale = 2.4;
        }),
      TapGesture({ count: 1 }).tag('levixel-tap')
        .onAction(() => { if (item.mediaType === LevixelMediaType.IMAGE) this.closeViewer(); })
    ))
    .onGestureJudgeBegin((info: GestureInfo): GestureJudgeResult => {
      if (this.closing || this.transitionActive || this.videoControlGestureActive || this.actionSheetActive) return GestureJudgeResult.REJECT;
      if (info.tag === 'levixel-long-press' && this.pinchLocked) return GestureJudgeResult.REJECT;
      if (info.tag === 'levixel-pan' && (this.zoomScale <= 1.01 || this.pinchLocked)) return GestureJudgeResult.REJECT;
      if (item.mediaType === LevixelMediaType.VIDEO && info.tag !== 'levixel-long-press') return GestureJudgeResult.REJECT;
      return GestureJudgeResult.CONTINUE;
    })
  }

  @Builder
  private ViewerMedia(item: LevixelMediaItem, sessionId: string) {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.previewSourceFor(item))
        .draggable(false)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .syncLoad(this.previewUsesPixelMap(item))

      if (item.mediaType === LevixelMediaType.IMAGE) {
        LevixelImageViewer({
          sourceUrl: item.sourceUrl,
          onMediaState: (loaded: boolean): void => { this.mediaState(item.id, sessionId, loaded); }
        })
      } else {
        LevixelVideoPlayer({
          itemId: item.id,
          onMediaState: (loaded: boolean): void => { this.mediaState(item.id, sessionId, loaded); },
          sourceUrl: item.sourceUrl,
          active: this.isActiveVideoItem(item),
          showPosterForDismiss: this.dragOffsetY !== 0,
          onCloseRequested: (): void => {
            this.closeViewer();
          },
          onControlInteractionChange: (active: boolean): void => {
            this.videoControlGestureActive = active;
            if (active) {
              this.resetDragState(true);
            }
          }
        })
      }
    }
    .width(this.targetRectFor(item).width)
    .height(this.targetRectFor(item).height)
    .scale({ x: this.isCurrentImage(item) ? this.zoomScale : 1, y: this.isCurrentImage(item) ? this.zoomScale : 1 })
    .translate({ x: this.isCurrentImage(item) ? this.panX : 0, y: this.isCurrentImage(item) ? this.panY : 0 })
    .id(this.viewerSnapshotId(item))
    .opacity(this.hiddenViewerMediaId === item.id ? 0 : 1)
  }

  @Builder
  private TransitionSnapshot() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.snapshotPixelMap as image.PixelMap)
        .draggable(false)
        .width(this.snapshotContentRect.width)
        .height(this.snapshotContentRect.height)
        .objectFit(ImageFit.Fill)
        .position({ x: this.snapshotContentRect.left, y: this.snapshotContentRect.top })
    }
    .width(this.snapshotRect.width)
    .height(this.snapshotRect.height)
    .position({ x: this.snapshotRect.left, y: this.snapshotRect.top })
    .borderRadius(this.snapshotRadius)
    .clip(true)
    .opacity(this.snapshotOpacity)
  }

  private openViewer(itemId: string): void {
    if (this.disposed || this.viewerOpen || this.transitionActive) {
      return;
    }
    const sessionItems: LevixelMediaItem[] = this.snapshotItems();
    const index: number = sessionItems.findIndex((item: LevixelMediaItem): boolean => item.id === itemId);
    if (index < 0 || index >= sessionItems.length) {
      throw new Error(`LevixelSource itemId "${itemId}" does not reference an item in LevixelViewer.items.`);
    }

    const actions: LevixelAction[] = snapshotLevixelActions(this.actions, this.actionLayout);
    if (typeof this.actionListIcons !== 'boolean') throw new Error('Levixel actionListIcons must be boolean.');
    if (this.theme !== 'dark' && this.theme !== 'light') throw new Error('Levixel theme must be dark or light.');
    const source: LevixelResolvedSource | null = this.getViewerContext().resolveSource(itemId);
    const token: number = this.beginTransition();
    const item: LevixelMediaItem = sessionItems[index];
    this.sessionId = this.getViewerContext().createSessionId();
    this.currentIndex = index;
    this.sessionActions = actions;
    this.sessionActionLayout = this.actionLayout;
    this.sessionActionListIcons = this.actionListIcons;
    this.sessionTheme = this.theme;
    this.actionIconsLoaded = [];
    this.actionGroups = [];
    this.sessionActions.forEach((action: LevixelAction) => {
      const group: string = action.group ?? '';
      if (!this.actionGroups.includes(group)) this.actionGroups.push(group);
    });
    this.retryVersions = sessionItems.map((_item: LevixelMediaItem): number => 0);
    this.failedIds = [];
    this.resetZoom();
    this.sessionItems = sessionItems;
    this.continueOpeningViewer(token, item, index, source);
  }

  private async continueOpeningViewer(
    token: number,
    item: LevixelMediaItem,
    index: number,
    source: LevixelResolvedSource | null
  ): Promise<void> {
    const sourceState: OpeningSharedElementState | null = await this.captureSourceState(item, source);
    if (!this.isActiveTransition(token)) {
      return;
    }

    this.viewerPreviewPixelMap = sourceState !== null ? sourceState.previewPixelMap : null;
    this.viewerPreviewItemId = this.viewerPreviewPixelMap !== null ? item.id : '';
    this.snapshotOpacity = 1;

    this.currentIndex = index;
    this.viewerOpen = true;
    this.contentVisible = true;
    this.contentOpacity = 0;
    this.getViewerContext().setHiddenSource('');
    this.hiddenViewerMediaId = item.id;
    this.backgroundOpacity = 0;
    this.resetDragState(false);

    if (sourceState === null) {
      this.performOpenFadeFallback(token, index);
      return;
    }

    const targetGeometry: SharedElementGeometry = sourceState.targetGeometry;
    this.applySnapshotState(sourceState);
    this.snapshotVisible = true;
    this.getViewerContext().setHiddenSource(item.id);

    setTimeout(() => {
      if (!this.isActiveTransition(token)) {
        return;
      }
      this.getUIContext().animateTo({ duration: OPEN_SNAPSHOT_DURATION_MS, curve: Curve.EaseOut }, () => {
        this.applySnapshotGeometry(targetGeometry);
        this.backgroundOpacity = 1;
        this.snapshotRadius = 0;
      });
      setTimeout(() => {
        if (!this.isActiveTransition(token)) {
          return;
        }
        this.beginOpenPreviewHandoff(token, index);
      }, OPEN_SNAPSHOT_DURATION_MS);
    }, 0);
  }

  private performOpenFadeFallback(token: number, index: number): void {
    this.hiddenViewerMediaId = '';
    this.snapshotVisible = false;
    this.getUIContext().animateTo({ duration: OPEN_CONTENT_FADE_DURATION_MS, curve: Curve.EaseOut }, () => {
      this.backgroundOpacity = 1;
      this.contentOpacity = 1;
    });
    setTimeout(() => {
      if (this.isActiveTransition(token)) {
        this.getViewerContext().setHiddenSource(this.sessionItems[index].id);
        this.finishOpenTransition(index);
      }
    }, OPEN_CONTENT_FADE_DURATION_MS + 20);
  }

  private finishOpenTransition(index: number): void {
    if (index === this.currentIndex) {
      this.getViewerContext().setHiddenSource(this.sessionItems[index].id);
    }
    this.snapshotVisible = false;
    this.snapshotPixelMap = null;
    this.transitionActive = false;
    this.resetDragState(false);
    this.emitViewerEvent('opened', index);
  }

  private async closeViewer(): Promise<void> {
    if (this.closing || this.sessionItems.length === 0) return;
    this.closing = true;
    this.pendingAction = null;
    this.pendingActionEvent = null;
    if (this.actionSheetActive) {
      this.closeAfterActions = true;
      this.actionsVisible = false;
      return;
    }
    await this.performCloseViewer();
  }

  private async performCloseViewer(): Promise<void> {
    if (this.transitionActive) {
      this.finishClose();
      return;
    }

    const token: number = this.beginTransition();
    const item: LevixelMediaItem = this.sessionItems[this.currentIndex];
    const pageState: SharedElementState | null = await this.captureViewerState(item);
    if (!this.isActiveTransition(token)) {
      return;
    }

    const targetState: SharedElementState | null = pageState !== null
      ? await this.resolveCloseTargetState(item, pageState.pixelMap)
      : null;
    if (!this.isActiveTransition(token)) {
      return;
    }

    if (pageState === null || targetState === null) {
      this.performCloseFadeFallback(token);
      return;
    }

    this.applySnapshotState(pageState);
    this.snapshotVisible = true;
    this.getViewerContext().setHiddenSource(item.id);
    this.hiddenViewerMediaId = item.id;

    setTimeout(() => {
      if (this.isActiveTransition(token)) {
        this.getUIContext().animateTo({ duration: CLOSE_DURATION_MS, curve: Curve.EaseOut }, () => {
          this.applySnapshotGeometry(targetState.geometry);
          this.backgroundOpacity = 0;
          this.contentOpacity = 0;
          this.snapshotRadius = targetState.radius;
        });
        setTimeout(() => {
          if (this.isActiveTransition(token)) {
            this.finishClose();
          }
        }, CLOSE_DURATION_MS + 30);
      }
    }, 0);
  }

  private performCloseFadeFallback(token: number): void {
    this.hiddenViewerMediaId = '';
    this.snapshotVisible = false;
    this.getUIContext().animateTo({ duration: CLOSE_FADE_DURATION_MS, curve: Curve.EaseOut }, () => {
      this.backgroundOpacity = 0;
      this.contentOpacity = 0;
    });
    setTimeout(() => {
      if (this.isActiveTransition(token)) {
        this.finishClose();
      }
    }, CLOSE_FADE_DURATION_MS + 20);
  }

  private finishClose(): void {
    const event: LevixelViewerEvent | null = this.sessionItems.length > 0 ? this.viewerEvent('dismiss', this.currentIndex) : null;
    this.actionsVisible = false;
    this.actionSheetActive = false;
    this.closeAfterActions = false;
    this.pendingAction = null;
    this.pendingActionEvent = null;
    this.sessionActions = [];
    this.actionGroups = [];
    this.actionIconsLoaded = [];
    this.retryVersions = [];
    this.failedIds = [];
    this.activeTouchIds = [];
    this.resetZoom();
    this.transitionToken += 1;
    this.viewerOpen = false;
    this.contentVisible = false;
    this.contentOpacity = 0;
    this.snapshotVisible = false;
    this.snapshotPixelMap = null;
    this.viewerPreviewItemId = '';
    this.viewerPreviewPixelMap = null;
    this.sessionItems = [];
    this.transitionActive = false;
    this.closing = false;
    this.getViewerContext().setHiddenSource('');
    this.hiddenViewerMediaId = '';
    this.backgroundOpacity = 0;
    this.snapshotRadius = 0;
    this.snapshotOpacity = 1;
    this.videoControlGestureActive = false;
    this.resetDragState(false);
    if (event !== null) { this.getViewerContext().emit(event); this.onEvent(cloneLevixelViewerEvent(event)); }
  }

  private isCurrentImage(item: LevixelMediaItem): boolean {
    return item.mediaType === LevixelMediaType.IMAGE && this.sessionItems[this.currentIndex]?.id === item.id;
  }

  private resetZoom(): void { this.zoomScale = 1; this.panX = 0; this.panY = 0; this.pinchLocked = false; }

  private applyPan(item: LevixelMediaItem, x: number, y: number): void {
    const rect: RectMetrics = this.targetRectFor(item);
    const pan = clampLevixelPan(this.zoomScale, x, y, rect.width, rect.height, this.rootWidth, this.rootHeight);
    this.panX = pan.x;
    this.panY = pan.y;
  }

  private viewerEvent(type: string, index: number, actionId?: string): LevixelViewerEvent {
    const item: LevixelMediaItem = this.sessionItems[index];
    const payload: LevixelMediaContext = {
      sessionId: this.sessionId, galleryId: this.sessionId, index: index, itemId: item.id, mediaType: item.mediaType
    };
    if (type === 'indexChange') payload.currentIndex = index;
    if (actionId !== undefined) payload.actionId = actionId;
    if (type === 'mediaError') { payload.code = 'LOAD_FAILED'; payload.message = 'Media could not be loaded'; }
    return { type: type, payload: payload, time: Date.now() };
  }

  private emitViewerEvent(type: string, index: number): void {
    if (index < 0 || index >= this.sessionItems.length) return;
    const event: LevixelViewerEvent = this.viewerEvent(type, index);
    this.getViewerContext().emit(event);
    this.onEvent(cloneLevixelViewerEvent(event));
  }

  private mediaState(itemId: string, sessionId: string, loaded: boolean): void {
    if (sessionId !== this.sessionId || !this.viewerOpen || this.closing || this.disposed) return;
    const index: number = this.sessionItems.findIndex((item: LevixelMediaItem): boolean => item.id === itemId);
    if (index < 0) return;
    this.failedIds = this.failedIds.filter((id: string): boolean => id !== itemId);
    if (!loaded) this.failedIds.push(itemId);
    this.emitViewerEvent(loaded ? 'mediaLoad' : 'mediaError', index);
  }

  private retryCurrent(): boolean {
    if (!this.viewerOpen || this.closing || this.transitionActive || this.actionSheetActive) return false;
    const itemId: string = this.sessionItems[this.currentIndex].id;
    if (!this.failedIds.includes(itemId)) return false;
    this.failedIds = this.failedIds.filter((id: string): boolean => id !== itemId);
    const versions: number[] = this.retryVersions.slice();
    versions[this.currentIndex] += 1;
    this.retryVersions = versions;
    return true;
  }

  private showActions(): void {
    if (!this.viewerOpen || this.closing || this.transitionActive || this.actionSheetActive || this.pinchLocked) return;
    this.emitViewerEvent('longPress', this.currentIndex);
    if (this.viewerOpen && !this.closing && !this.transitionActive && this.sessionActions.length > 0) {
      this.actionSheetActive = true;
      this.actionsVisible = true;
    }
  }

  private finishAction(): void {
    this.actionSheetActive = false;
    if (this.closeAfterActions) {
      this.closeAfterActions = false;
      this.performCloseViewer();
      return;
    }
    const action: LevixelAction | null = this.pendingAction;
    const event: LevixelViewerEvent | null = this.pendingActionEvent;
    this.pendingAction = null;
    this.pendingActionEvent = null;
    if (action === null || event === null || !this.viewerOpen || this.closing || this.sessionId !== event.payload.sessionId) return;
    this.getViewerContext().emit(event);
    this.onEvent(cloneLevixelViewerEvent(event));
    if (action.onPress !== undefined) action.onPress(event);
  }

  private actionDrawerHeight(): number {
    const body: number = this.sessionActionLayout === 'list'
      ? this.sessionActions.length * this.actionListRowHeight() + Math.max(0, this.actionGroups.length - 1) * 8
        + Math.max(0, this.sessionActions.length - this.actionGroups.length) * 0.5
      : this.actionGroups.length * this.actionGridRowHeight();
    const top: number = this.sessionActionLayout === 'list' ? 8 : 32;
    return Math.min(this.rootHeight * 0.8, top + body + 8.5 + this.actionCancelHeight() + 16);
  }

  private actionGridRowHeight(): number {
    return Math.max(124, 60 + 8 + this.fontPointsToVp(16) * 2 + 24);
  }

  private actionListRowHeight(): number {
    return Math.max(64, this.fontPointsToVp(20) * 2 + 24);
  }

  private actionCancelHeight(): number {
    return Math.max(56, this.fontPointsToVp(22) + 24);
  }

  private fontPointsToVp(value: number): number {
    return this.getUIContext().px2vp(this.getUIContext().fp2px(value));
  }

  private actionsInGroup(group: string): LevixelAction[] {
    return this.sessionActions.filter((action: LevixelAction): boolean => (action.group ?? '') === group);
  }

  private selectAction(action: LevixelAction): void {
    if (!this.actionsVisible || this.closing || action.disabled === true) return;
    this.pendingAction = action;
    this.pendingActionEvent = this.viewerEvent('action', this.currentIndex, action.id);
    this.actionsVisible = false;
  }

  @Builder
  private ActionIcon(action: LevixelAction, size: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (action.icon !== undefined) {
        if (!this.actionIconsLoaded.includes(action.id)) {
          Text('•••').fontSize(18).fontColor('#2F343B')
        }
        Image(action.icon).width(size).height(size).objectFit(ImageFit.Contain).draggable(false)
          .onComplete(() => {
            if (!this.actionIconsLoaded.includes(action.id)) this.actionIconsLoaded = this.actionIconsLoaded.concat([action.id]);
          })
          .onError(() => {
            this.actionIconsLoaded = this.actionIconsLoaded.filter((id: string): boolean => id !== action.id);
          })
      }
    }.width(size).height(size).accessibilityLevel('no')
  }

  @Builder
  private ActionDrawer() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.actionGroups, (group: string, groupIndex: number) => {
            if (this.sessionActionLayout === 'list') {
              if (groupIndex > 0) { Blank().height(8) }
              ForEach(this.actionsInGroup(group), (action: LevixelAction, index: number) => {
                if (index > 0) { Divider().color('#12000000').strokeWidth(0.5).margin({ left: 24, right: 24 }) }
                Row({ space: 12 }) {
                  if (this.sessionActionListIcons) { this.ActionIcon(action, 24) }
                  Text(action.label).fontSize(16).lineHeight('20fp').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                    .textAlign(this.sessionActionListIcons ? TextAlign.Start : TextAlign.Center).layoutWeight(1)
                    .fontColor(action.destructive ? '#C73934' : '#4B5057')
                }.width('100%').height(this.actionListRowHeight()).padding({ left: 24, right: 24, top: 12, bottom: 12 })
                .enabled(action.disabled !== true).opacity(action.disabled === true ? 0.4 : 1)
                .accessibilityText(action.label).onClick(() => { this.selectAction(action); })
              }, (action: LevixelAction): string => action.id)
            } else {
              Scroll() {
                Row({ space: 10 }) {
                  ForEach(this.actionsInGroup(group), (action: LevixelAction) => {
                    Column({ space: 8 }) {
                      Stack({ alignContent: Alignment.Center }) { this.ActionIcon(action, 30) }
                        .width(60).height(60).borderRadius(16).backgroundColor('#FFFFFF')
                      Text(action.label).fontSize(12).lineHeight('16fp').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                        .textAlign(TextAlign.Center).width('100%')
                        .fontColor(action.destructive ? '#C73934' : '#4B5057')
                    }.width(72).height(this.actionGridRowHeight() - 24)
                    .enabled(action.disabled !== true).opacity(action.disabled === true ? 0.4 : 1)
                    .accessibilityText(action.label).onClick(() => { this.selectAction(action); })
                  }, (action: LevixelAction): string => action.id)
                }.padding({ left: 16, right: 16, top: 8, bottom: 16 }).alignItems(VerticalAlign.Top)
              }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.TopStart)
                .width('100%').height(this.actionGridRowHeight())
            }
          }, (group: string): string => group)
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
        .nestedScroll({ scrollForward: NestedScrollMode.SELF_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      Divider().color('#12000000').strokeWidth(0.5).margin({ top: 8 })
      Button(i18n.System.getSystemLanguage().startsWith('zh') ? '取消' : 'Cancel')
        .width('100%').height(this.actionCancelHeight()).backgroundColor(Color.Transparent).fontSize(16).fontColor('#445F83')
        .onClick(() => { this.actionsVisible = false; })
    }.width('100%').height(this.actionDrawerHeight()).padding({ top: this.sessionActionLayout === 'list' ? 8 : 32, bottom: 16 })
  }

  private beginTransition(): number {
    this.transitionToken += 1;
    this.transitionActive = true;
    this.videoControlGestureActive = false;
    return this.transitionToken;
  }

  private isActiveTransition(token: number): boolean {
    return !this.disposed && this.transitionActive && this.transitionToken === token;
  }

  private async captureSourceState(
    item: LevixelMediaItem,
    source: LevixelResolvedSource | null
  ): Promise<OpeningSharedElementState | null> {
    if (source === null) {
      return null;
    }
    const sourceRect: RectMetrics = this.localRect(source.frameInWindow);
    const visibleSourceRect: RectMetrics | null = this.visibleSourceRect(source, sourceRect);
    if (visibleSourceRect === null) {
      return null;
    }
    const targetRect: RectMetrics = this.targetRectFor(item);
    const cachedResource: TransitionImageResource | undefined = this.cachedImageResource(item.thumbnailUrl);
    if (cachedResource !== undefined) {
      return this.createOpeningSourceState(cachedResource, source, sourceRect, visibleSourceRect, targetRect);
    }

    const pixelMap: image.PixelMap | null = await this.capturePixelMap(source.snapshotId);
    if (pixelMap !== null) {
      const capturedResource: TransitionImageResource = await this.describePixelMap(pixelMap, sourceRect);
      return this.createOpeningSnapshotState(
        capturedResource, item, source, sourceRect, visibleSourceRect, targetRect
      );
    }

    const readyResource: TransitionImageResource | undefined = this.cachedImageResource(item.thumbnailUrl);
    return readyResource !== undefined
      ? this.createOpeningSourceState(readyResource, source, sourceRect, visibleSourceRect, targetRect)
      : null;
  }

  private createOpeningSourceState(
    resource: TransitionImageResource,
    source: LevixelResolvedSource,
    sourceRect: RectMetrics,
    visibleSourceRect: RectMetrics,
    targetRect: RectMetrics
  ): OpeningSharedElementState | null {
    const sourceState: SharedElementState | null = this.createImageResourceState(
      resource,
      sourceRect,
      source.imageFit,
      this.visibleSourceRadius(sourceRect, visibleSourceRect, source.cornerRadius),
      visibleSourceRect
    );
    const targetGeometry: SharedElementGeometry | null = resolveImageGeometry(
      resource.width, resource.height, targetRect, LevixelSourceImageFit.COVER
    );
    if (sourceState === null || targetGeometry === null) {
      return null;
    }
    return {
      pixelMap: sourceState.pixelMap,
      geometry: sourceState.geometry,
      radius: sourceState.radius,
      targetGeometry: targetGeometry,
      previewPixelMap: resource.pixelMap
    };
  }

  private createOpeningSnapshotState(
    resource: TransitionImageResource,
    item: LevixelMediaItem,
    source: LevixelResolvedSource,
    sourceRect: RectMetrics,
    visibleSourceRect: RectMetrics,
    targetRect: RectMetrics
  ): OpeningSharedElementState | null {
    const snapshotAtTarget: RectMetrics = mapSourceSnapshotToTarget(
      item.aspectWidth, item.aspectHeight, sourceRect, targetRect, source.imageFit
    );
    const sourceState: SharedElementState | null = this.createImageResourceState(
      resource,
      sourceRect,
      LevixelSourceImageFit.FILL,
      this.visibleSourceRadius(sourceRect, visibleSourceRect, source.cornerRadius),
      visibleSourceRect
    );
    const targetGeometry: SharedElementGeometry | null = resolveImageGeometry(
      resource.width, resource.height, snapshotAtTarget, LevixelSourceImageFit.FILL, targetRect
    );
    if (sourceState === null || targetGeometry === null) {
      return null;
    }
    return {
      pixelMap: sourceState.pixelMap,
      geometry: sourceState.geometry,
      radius: sourceState.radius,
      targetGeometry: targetGeometry,
      previewPixelMap: null
    };
  }

  private async describePixelMap(
    pixelMap: image.PixelMap,
    fallbackFrame: RectMetrics
  ): Promise<TransitionImageResource> {
    try {
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      return {
        pixelMap: pixelMap,
        width: Math.max(1, info.size.width),
        height: Math.max(1, info.size.height)
      };
    } catch (_error) {
      return {
        pixelMap: pixelMap,
        width: Math.max(1, fallbackFrame.width),
        height: Math.max(1, fallbackFrame.height)
      };
    }
  }

  private async captureViewerState(item: LevixelMediaItem): Promise<SharedElementState | null> {
    const frame: RectMetrics = this.currentViewerRectFor(item);
    const visibleFrame: RectMetrics | null = intersectRects(frame, {
      left: 0, top: 0, width: this.rootWidth, height: this.rootHeight
    });
    if (visibleFrame === null) return null;
    const fullResource: TransitionImageResource | undefined = this.cachedImageResource(this.displayUrl(item));
    const previewResource: TransitionImageResource | undefined = this.cachedImageResource(item.thumbnailUrl);
    const transitionResource: TransitionImageResource | undefined = fullResource ?? previewResource;
    if (transitionResource !== undefined) {
      return this.createImageResourceState(
        transitionResource,
        frame,
        LevixelSourceImageFit.COVER,
        0,
        visibleFrame
      );
    }

    const pixelMap: image.PixelMap | null = await this.capturePixelMap(this.viewerSnapshotId(item));
    if (pixelMap === null) {
      return null;
    }
    return {
      pixelMap: pixelMap,
      geometry: {
        visibleFrame: visibleFrame,
        contentFrame: {
          left: frame.left - visibleFrame.left, top: frame.top - visibleFrame.top,
          width: frame.width, height: frame.height
        }
      },
      radius: 0
    };
  }

  private async resolveCloseTargetState(
    item: LevixelMediaItem,
    transitionPixelMap: image.PixelMap
  ): Promise<SharedElementState | null> {
    if (!this.items.some((candidate: LevixelMediaItem): boolean => candidate.id === item.id)) {
      return null;
    }
    const source: LevixelResolvedSource | null = this.getViewerContext().resolveSource(item.id);
    if (source === null) {
      return null;
    }
    const targetRect: RectMetrics = this.localRect(source.frameInWindow);
    const visibleTargetRect: RectMetrics | null = this.visibleSourceRect(source, targetRect);
    if (visibleTargetRect === null) {
      return null;
    }
    const radius: number = this.visibleSourceRadius(targetRect, visibleTargetRect, source.cornerRadius);

    const resource: TransitionImageResource = await this.describePixelMap(
      transitionPixelMap, this.targetRectFor(item)
    );
    return this.createImageResourceState(resource, targetRect, source.imageFit, radius, visibleTargetRect);
  }

  private async capturePixelMap(componentId: string): Promise<image.PixelMap | null> {
    try {
      return await this.getUIContext().getComponentSnapshot().get(componentId, {
        scale: SNAPSHOT_CAPTURE_SCALE,
        waitUntilRenderFinished: true
      });
    } catch (_error) {
      return null;
    }
  }

  private createImageResourceState(
    resource: TransitionImageResource,
    containerFrame: RectMetrics,
    fit: LevixelSourceImageFit,
    radius: number,
    clippingFrame: RectMetrics = containerFrame
  ): SharedElementState | null {
    const geometry: SharedElementGeometry | null = resolveImageGeometry(
      resource.width, resource.height, containerFrame, fit, clippingFrame
    );
    if (geometry === null) {
      return null;
    }
    return {
      pixelMap: resource.pixelMap,
      geometry: geometry,
      radius: radius
    };
  }

  private applySnapshotState(state: SharedElementState): void {
    this.snapshotPixelMap = state.pixelMap;
    this.snapshotRadius = state.radius;
    this.snapshotOpacity = 1;
    this.applySnapshotGeometry(state.geometry);
  }

  private applySnapshotGeometry(geometry: SharedElementGeometry): void {
    this.snapshotRect = cloneRect(geometry.visibleFrame);
    this.snapshotContentRect = cloneRect(geometry.contentFrame);
  }

  private viewerSnapshotId(item: LevixelMediaItem): string {
    return this.getViewerContext().viewerSnapshotId(item.id);
  }

  private async loadImageResource(url: string): Promise<TransitionImageResource | null> {
    const cached: TransitionImageResource | undefined = this.cachedImageResource(url);
    if (cached !== undefined) {
      return cached;
    }

    const pending: Promise<TransitionImageResource | null> | undefined = this.imageResourceRequests.get(url);
    if (pending !== undefined) {
      return await pending;
    }

    const request: Promise<TransitionImageResource | null> = this.createImageResourceRequest(url);
    this.imageResourceRequests.set(url, request);
    const resource: TransitionImageResource | null = await request;
    this.imageResourceRequests.delete(url);
    if (resource !== null && !this.disposed) {
      this.cacheImageResource(url, resource);
    }
    return resource;
  }

  private cachedImageResource(url: string): TransitionImageResource | undefined {
    const resource: TransitionImageResource | undefined = this.imageResourceCache.get(url);
    if (resource !== undefined) {
      this.imageResourceCache.delete(url);
      this.imageResourceCache.set(url, resource);
    }
    return resource;
  }

  private cacheImageResource(url: string, resource: TransitionImageResource): void {
    const existing: TransitionImageResource | undefined = this.imageResourceCache.get(url);
    if (existing !== undefined) {
      this.imageResourceCacheBytes -= this.estimatedImageResourceBytes(existing);
      this.imageResourceCache.delete(url);
    }
    this.imageResourceCache.set(url, resource);
    this.imageResourceCacheBytes += this.estimatedImageResourceBytes(resource);
    while (this.imageResourceCache.size > MAX_TRANSITION_IMAGE_CACHE_ENTRIES ||
      this.imageResourceCacheBytes > MAX_TRANSITION_IMAGE_CACHE_BYTES) {
      let oldestUrl: string = '';
      this.imageResourceCache.forEach((_cached: TransitionImageResource, cachedUrl: string) => {
        if (oldestUrl.length === 0) {
          oldestUrl = cachedUrl;
        }
      });
      if (oldestUrl.length === 0) {
        break;
      }
      const oldest: TransitionImageResource | undefined = this.imageResourceCache.get(oldestUrl);
      if (oldest !== undefined) {
        this.imageResourceCacheBytes -= this.estimatedImageResourceBytes(oldest);
      }
      this.imageResourceCache.delete(oldestUrl);
    }
  }

  private estimatedImageResourceBytes(resource: TransitionImageResource): number {
    return Math.max(1, resource.width) * Math.max(1, resource.height) * 4;
  }

  private async createImageResourceRequest(url: string): Promise<TransitionImageResource | null> {
    let request: http.HttpRequest | null = null;
    try {
      request = http.createHttp();
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: true,
        connectTimeout: IMAGE_RESOURCE_CONNECT_TIMEOUT_MS,
        readTimeout: IMAGE_RESOURCE_READ_TIMEOUT_MS
      });
      if (response.resultType !== http.HttpDataType.ARRAY_BUFFER) {
        return null;
      }

      const source: image.ImageSource = image.createImageSource(response.result as ArrayBuffer);
      try {
        const sourceInfo: image.ImageInfo = await source.getImageInfo(0);
        const pixelMap: image.PixelMap = await source.createPixelMap({
          desiredSize: this.boundedDecodeSize(sourceInfo.size.width, sourceInfo.size.height)
        });
        const info: image.ImageInfo = await pixelMap.getImageInfo();
        return {
          pixelMap: pixelMap,
          width: Math.max(1, info.size.width),
          height: Math.max(1, info.size.height)
        };
      } finally {
        try {
          await source.release();
        } catch (_error) {
        }
      }
    } catch (_error) {
      return null;
    } finally {
      if (request !== null) {
        request.destroy();
      }
    }
  }

  private boundedDecodeSize(width: number, height: number): image.Size {
    const safeWidth: number = Math.max(1, width);
    const safeHeight: number = Math.max(1, height);
    const pixelCount: number = safeWidth * safeHeight;
    if (pixelCount <= MAX_TRANSITION_IMAGE_DECODE_PIXELS) {
      return {
        width: safeWidth,
        height: safeHeight
      };
    }
    const scale: number = Math.sqrt(MAX_TRANSITION_IMAGE_DECODE_PIXELS / pixelCount);
    return {
      width: Math.max(1, Math.round(safeWidth * scale)),
      height: Math.max(1, Math.round(safeHeight * scale))
    };
  }

  private updateVerticalDrag(offsetY: number): void {
    if (this.closing || this.transitionActive || this.videoControlGestureActive || this.zoomScale > 1.01 || this.pinchLocked || this.actionSheetActive) {
      return;
    }
    this.dragOffsetY = offsetY;
    const distanceRatio: number = Math.min(1, Math.abs(offsetY) / Math.max(1, this.rootHeight));
    this.dragScale = Math.max(0.84, 1 - distanceRatio * 0.16);
    this.backgroundOpacity = 1 - Math.min(0.9, distanceRatio * 1.25);
  }

  private finishVerticalDrag(velocityY: number): void {
    if (this.closing || this.videoControlGestureActive || this.zoomScale > 1.01 || this.pinchLocked || this.actionSheetActive) {
      this.resetDragState(true);
      return;
    }
    const distanceThreshold: number = this.rootHeight * 0.16;
    const quickFlingDistance: number = this.rootHeight * 0.06;
    const velocityThreshold: number = 1300;
    const dismissByDistance: boolean = Math.abs(this.dragOffsetY) > distanceThreshold;
    const dismissByFling: boolean = Math.abs(this.dragOffsetY) > quickFlingDistance && Math.abs(velocityY) > velocityThreshold;
    if (dismissByDistance || dismissByFling) {
      this.closeViewer();
      return;
    }
    this.animateDragBack();
  }

  private animateDragBack(): void {
    this.getUIContext().animateTo({ duration: RESET_DURATION_MS, curve: Curve.EaseOut }, () => {
      this.resetDragState(true);
    });
  }

  private resetDragState(keepBackground: boolean): void {
    this.dragOffsetY = 0;
    this.dragScale = 1;
    if (keepBackground) {
      this.backgroundOpacity = 1;
    }
  }

  private syncHiddenSourceToCurrentItem(): void {
    if (!this.viewerOpen || this.currentIndex < 0 || this.currentIndex >= this.sessionItems.length) {
      this.getViewerContext().setHiddenSource('');
      return;
    }
    this.getViewerContext().setHiddenSource(this.sessionItems[this.currentIndex].id);
  }

  private prepareCurrentTransitionResource(): void {
    if (this.currentIndex < 0 || this.currentIndex >= this.sessionItems.length) {
      return;
    }
    this.loadImageResource(this.sessionItems[this.currentIndex].thumbnailUrl);
  }

  private prepareTransitionResource(itemId: string): void {
    const item: LevixelMediaItem | undefined = this.items.find((candidate: LevixelMediaItem): boolean => {
      return candidate.id === itemId;
    });
    if (item !== undefined) {
      this.loadImageResource(item.thumbnailUrl);
    }
  }

  private localRect(rectInWindow: RectMetrics): RectMetrics {
    return {
      left: rectInWindow.left - this.rootLeft,
      top: rectInWindow.top - this.rootTop,
      width: rectInWindow.width,
      height: rectInWindow.height
    };
  }

  private visibleSourceRect(source: LevixelResolvedSource, sourceRect: RectMetrics): RectMetrics | null {
    let clippingFrame: RectMetrics = {
      left: 0,
      top: 0,
      width: this.rootWidth,
      height: this.rootHeight
    };
    if (source.viewportInWindow !== null) {
      const viewportInHost: RectMetrics = this.localRect(source.viewportInWindow);
      const clippedViewport: RectMetrics | null = intersectRects(clippingFrame, viewportInHost);
      if (clippedViewport === null) {
        return null;
      }
      clippingFrame = clippedViewport;
    }
    return intersectRects(sourceRect, clippingFrame);
  }

  private visibleSourceRadius(sourceRect: RectMetrics, visibleRect: RectMetrics, cornerRadius: number): number {
    return this.rectsApproximatelyEqual(sourceRect, visibleRect) ? cornerRadius : 0;
  }

  private rectsApproximatelyEqual(first: RectMetrics, second: RectMetrics): boolean {
    const tolerance: number = 0.5;
    return Math.abs(first.left - second.left) <= tolerance &&
      Math.abs(first.top - second.top) <= tolerance &&
      Math.abs(first.width - second.width) <= tolerance &&
      Math.abs(first.height - second.height) <= tolerance;
  }

  private targetRectFor(item: LevixelMediaItem): RectMetrics {
    const availableWidth: number = Math.max(1, this.rootWidth);
    const availableHeight: number = Math.max(1, this.rootHeight);
    const aspectWidth: number = Math.max(1, item.aspectWidth);
    const aspectHeight: number = Math.max(1, item.aspectHeight);
    const scale: number = Math.min(
      availableWidth / aspectWidth,
      availableHeight / aspectHeight
    );
    const width: number = aspectWidth * scale;
    const height: number = aspectHeight * scale;
    return {
      left: (this.rootWidth - width) * 0.5,
      top: (this.rootHeight - height) * 0.5,
      width: width,
      height: height
    };
  }

  private currentViewerRectFor(item: LevixelMediaItem): RectMetrics {
    const baseRect: RectMetrics = this.targetRectFor(item);
    const zoom: number = this.isCurrentImage(item) ? this.zoomScale : 1;
    const panX: number = this.isCurrentImage(item) ? this.panX : 0;
    const panY: number = this.isCurrentImage(item) ? this.panY : 0;
    const left: number = baseRect.left + baseRect.width * (1 - zoom) / 2 + panX;
    const top: number = baseRect.top + baseRect.height * (1 - zoom) / 2 + panY;
    return {
      left: this.rootWidth * 0.5 + (left - this.rootWidth * 0.5) * this.dragScale,
      top: this.rootHeight * 0.5 + (top - this.rootHeight * 0.5) * this.dragScale + this.dragOffsetY,
      width: baseRect.width * zoom * this.dragScale,
      height: baseRect.height * zoom * this.dragScale
    };
  }

  private displayUrl(item: LevixelMediaItem): string {
    return item.mediaType === LevixelMediaType.VIDEO ? item.thumbnailUrl : item.sourceUrl;
  }

  private previewSourceFor(item: LevixelMediaItem): string | image.PixelMap {
    if (this.viewerPreviewItemId === item.id && this.viewerPreviewPixelMap !== null) {
      return this.viewerPreviewPixelMap;
    }
    const cached: TransitionImageResource | undefined = this.imageResourceCache.get(item.thumbnailUrl);
    return cached !== undefined ? cached.pixelMap : item.thumbnailUrl;
  }

  private previewUsesPixelMap(item: LevixelMediaItem): boolean {
    if (this.viewerPreviewItemId === item.id && this.viewerPreviewPixelMap !== null) {
      return true;
    }
    return this.imageResourceCache.has(item.thumbnailUrl);
  }

  private beginOpenPreviewHandoff(token: number, index: number): void {
    if (!this.isActiveTransition(token) || index < 0 || index >= this.sessionItems.length) {
      return;
    }

    // Loading belongs to the media layer, never to the transition lock.
    // A slow thumbnail must not prevent dismissing or paging the viewer.
    this.hiddenViewerMediaId = '';
    this.contentOpacity = 1;
    setTimeout(() => {
      if (!this.isActiveTransition(token)) {
        return;
      }
      this.getUIContext().animateTo({ duration: OPEN_CONTENT_FADE_DURATION_MS, curve: Curve.EaseOut }, () => {
        this.snapshotOpacity = 0;
      });
      setTimeout(() => {
        if (this.isActiveTransition(token)) {
          this.finishOpenTransition(index);
        }
      }, OPEN_CONTENT_FADE_DURATION_MS + 20);
    }, 0);
  }

  private isActiveVideoItem(item: LevixelMediaItem): boolean {
    if (item.mediaType !== LevixelMediaType.VIDEO || this.transitionActive || !this.viewerOpen) {
      return false;
    }
    if (this.currentIndex < 0 || this.currentIndex >= this.sessionItems.length) {
      return false;
    }
    return this.sessionItems[this.currentIndex].id === item.id;
  }

  private snapshotItems(): LevixelMediaItem[] {
    const itemIds: Set<string> = new Set<string>();
    const snapshot: LevixelMediaItem[] = [];
    for (let index: number = 0; index < this.items.length; index += 1) {
      const item: LevixelMediaItem = this.items[index];
      if (item.id.trim().length === 0) {
        throw new Error(`Levixel items[${index}].id must be a non-empty string.`);
      }
      if (itemIds.has(item.id)) {
        throw new Error(`Levixel items[${index}].id must be unique within items.`);
      }
      if (item.mediaType !== LevixelMediaType.IMAGE && item.mediaType !== LevixelMediaType.VIDEO) {
        throw new Error(`Levixel items[${index}].mediaType must be IMAGE or VIDEO.`);
      }
      if (item.sourceUrl.trim().length === 0) {
        throw new Error(`Levixel items[${index}].sourceUrl must be a non-empty string.`);
      }
      if (item.thumbnailUrl.trim().length === 0) {
        throw new Error(`Levixel items[${index}].thumbnailUrl must be a non-empty string.`);
      }
      if (!Number.isFinite(item.aspectWidth) || item.aspectWidth <= 0 ||
        !Number.isFinite(item.aspectHeight) || item.aspectHeight <= 0) {
        throw new Error(`Levixel items[${index}] aspectWidth and aspectHeight must be finite positive numbers.`);
      }
      itemIds.add(item.id);
      snapshot.push({
        id: item.id,
        mediaType: item.mediaType,
        sourceUrl: item.sourceUrl,
        thumbnailUrl: item.thumbnailUrl,
        title: item.title,
        aspectWidth: item.aspectWidth,
        aspectHeight: item.aspectHeight
      });
    }
    return snapshot;
  }

  private asPositionNumber(value: Length | undefined, fallback: number): number {
    if (value === undefined) {
      return fallback;
    }
    if (typeof value !== 'number' && typeof value !== 'string') {
      return fallback;
    }
    const numeric: number = Number(value);
    if (Number.isNaN(numeric)) {
      return fallback;
    }
    return numeric;
  }

  private asPositiveNumber(value: Length | undefined, fallback: number): number {
    const numeric: number = this.asPositionNumber(value, fallback);
    if (numeric <= 0) {
      return fallback;
    }
    return numeric;
  }
}
