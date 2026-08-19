import http from '@ohos.net.http';
import image from '@ohos.multimedia.image';
import {
  cloneRect,
  LevixelMediaItem,
  LevixelMediaType,
  RectMetrics
} from '../model/LevixelModels';

const OPEN_SNAPSHOT_DURATION_MS: number = 300;
const OPEN_CONTENT_FADE_DURATION_MS: number = 140;
const CLOSE_DURATION_MS: number = 280;
const CLOSE_FADE_DURATION_MS: number = 180;
const RESET_DURATION_MS: number = 200;
const THUMBNAIL_RADIUS: number = 8;
const SNAPSHOT_CAPTURE_SCALE: number = 1;
const IMAGE_RESOURCE_CONNECT_TIMEOUT_MS: number = 3000;
const IMAGE_RESOURCE_READ_TIMEOUT_MS: number = 5000;

interface SharedElementGeometry {
  visibleFrame: RectMetrics;
  contentFrame: RectMetrics;
}

interface SharedElementState {
  pixelMap: image.PixelMap;
  geometry: SharedElementGeometry;
  radius: number;
}

interface TransitionImageResource {
  pixelMap: image.PixelMap;
  width: number;
  height: number;
}

enum TransitionImageFit {
  COVER,
  CONTAIN,
  FILL
}

@Component
export struct LevixelGallery {
  @Prop items: LevixelMediaItem[] = [];
  @Prop showsNavigationHeader: boolean = false;
  @Prop navigationTitle: string = 'Levixel';
  @Prop navigationTopInset: number = 0;
  onNavigateBack: () => void = (): void => {};
  private readonly tileRectsInWindow: Map<string, RectMetrics> = new Map<string, RectMetrics>();
  private readonly imageResourceCache: Map<string, TransitionImageResource> = new Map<string, TransitionImageResource>();
  private readonly imageResourceRequests: Map<string, Promise<TransitionImageResource | null>> =
    new Map<string, Promise<TransitionImageResource | null>>();
  private transitionToken: number = 0;
  private snapshotPixelMap: image.PixelMap | null = null;

  @State rootWidth: number = 360;
  @State rootHeight: number = 720;
  @State rootLeft: number = 0;
  @State rootTop: number = 0;
  @State currentIndex: number = 0;
  @State viewerOpen: boolean = false;
  @State contentVisible: boolean = false;
  @State contentOpacity: number = 0;
  @State snapshotVisible: boolean = false;
  @State transitionActive: boolean = false;
  @State hiddenSourceId: string = '';
  @State hiddenViewerMediaId: string = '';
  @State backgroundOpacity: number = 0;
  @State snapshotRect: RectMetrics = { left: 0, top: 0, width: 1, height: 1 };
  @State snapshotContentRect: RectMetrics = { left: 0, top: 0, width: 1, height: 1 };
  @State snapshotRadius: number = 0;
  @State dragOffsetY: number = 0;
  @State dragScale: number = 1;

  aboutToAppear(): void {
    this.preloadTransitionResources();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.GridSurface()

      if (this.viewerOpen || this.transitionActive) {
        this.ViewerLayer()
      }

      if (this.snapshotVisible && this.snapshotPixelMap !== null) {
        this.TransitionSnapshot()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.White)
    .onAreaChange((_oldArea, newArea) => {
      this.rootLeft = this.asPositionNumber(newArea.globalPosition.x, this.rootLeft);
      this.rootTop = this.asPositionNumber(newArea.globalPosition.y, this.rootTop);
      this.rootWidth = this.asPositiveNumber(newArea.width, this.rootWidth);
      this.rootHeight = this.asPositiveNumber(newArea.height, this.rootHeight);
    })
  }

  @Builder
  private GridSurface() {
    Column() {
      if (this.showsNavigationHeader) {
        this.NavigationHeader()
      }

      Scroll() {
        Column() {
          if (!this.showsNavigationHeader) {
            Row() {
              Column() {
                Text('Levixel')
                  .fontSize(28)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#101828')
                  .width('100%')
                Text('Shared transition gallery')
                  .fontSize(13)
                  .fontColor('#667085')
                  .margin({ top: 4 })
                  .width('100%')
              }
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 18, bottom: 14 })
          }

          Grid() {
            ForEach(this.items, (item: LevixelMediaItem, index: number) => {
              GridItem() {
                this.ThumbnailTile(item, index)
              }
            }, (item: LevixelMediaItem) => item.id)
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .padding({ left: 12, right: 12, top: 12, bottom: 28 })
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private NavigationHeader() {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Image($r('app.media.levixel_arrow_back'))
          .width(24)
          .height(24)
      }
      .width(56)
      .height(56)
      .onClick(() => {
        this.onNavigateBack();
      })

      Text(this.navigationTitle)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(56 + this.navigationTopInset)
    .padding({ top: this.navigationTopInset, right: 16 })
    .backgroundColor('#172A48')
  }

  @Builder
  private ThumbnailTile(item: LevixelMediaItem, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(item.thumbnailUrl)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .id(this.sourceSnapshotId(item))
        .opacity(this.hiddenSourceId === item.id ? 0 : 1)

      if (item.mediaType === LevixelMediaType.VIDEO) {
        this.VideoBadge(this.hiddenSourceId === item.id)
      }

      Text(item.title)
        .fontSize(12)
        .fontColor(Color.White)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor('#80000000')
        .borderRadius(6)
        .position({ x: 8, y: 104 })
        .opacity(this.hiddenSourceId === item.id ? 0 : 1)
    }
    .height(132)
    .width('100%')
    .clip(true)
    .borderRadius(8)
    .backgroundColor('#F2F4F7')
    .onClick(() => {
      this.openViewer(index);
    })
    .onAreaChange((_oldArea, newArea) => {
      this.tileRectsInWindow.set(item.id, {
        left: this.asPositionNumber(newArea.globalPosition.x, this.rootLeft),
        top: this.asPositionNumber(newArea.globalPosition.y, this.rootTop),
        width: this.asPositiveNumber(newArea.width, 1),
        height: this.asPositiveNumber(newArea.height, 1)
      });
    })
  }

  @Builder
  private VideoBadge(hidden: boolean) {
    Row() {
      Text('▶')
        .fontSize(13)
        .fontColor(Color.White)
      Text('VIDEO')
        .fontSize(10)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .margin({ left: 4 })
    }
    .padding({ left: 7, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#99000000')
    .borderRadius(6)
    .position({ x: 8, y: 8 })
    .opacity(hidden ? 0 : 1)
  }

  @Builder
  private ViewerLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .opacity(this.backgroundOpacity)

      if (this.contentVisible) {
        Stack({ alignContent: Alignment.TopStart }) {
          Swiper() {
            ForEach(this.items, (item: LevixelMediaItem) => {
              this.ViewerPage(item)
            }, (item: LevixelMediaItem) => item.id)
          }
          .index(this.currentIndex)
          .loop(false)
          .indicator(false)
          .onChange((index: number) => {
            this.currentIndex = index;
            this.syncHiddenSourceToCurrentItem();
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
              this.updateVerticalDrag(event.offsetY);
            })
            .onActionEnd((event) => {
              this.finishVerticalDrag(event.velocityY);
            })
            .onActionCancel(() => {
              this.animateDragBack();
            })
        )
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ViewerPage(item: LevixelMediaItem) {
    Stack({ alignContent: Alignment.Center }) {
      this.ViewerMedia(item)
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (!this.transitionActive) {
        this.closeViewer();
      }
    })
  }

  @Builder
  private ViewerMedia(item: LevixelMediaItem) {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.displayUrl(item))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)

      if (item.mediaType === LevixelMediaType.VIDEO) {
        Column() {
          Text('▶')
            .fontSize(42)
            .fontColor(Color.White)
          Text('Video item shares the same transition path')
            .fontSize(13)
            .fontColor('#D0D5DD')
            .margin({ top: 8 })
        }
        .padding(16)
        .backgroundColor('#80000000')
        .borderRadius(8)
      }
    }
    .width(this.targetRectFor(item).width)
    .height(this.targetRectFor(item).height)
    .id(this.viewerSnapshotId(item))
    .opacity(this.hiddenViewerMediaId === item.id ? 0 : 1)
  }

  @Builder
  private TransitionSnapshot() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image(this.snapshotPixelMap as image.PixelMap)
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
  }

  private async openViewer(index: number): Promise<void> {
    if (index < 0 || index >= this.items.length || this.transitionActive) {
      return;
    }

    const token: number = this.beginTransition();
    const item: LevixelMediaItem = this.items[index];
    const sourceState: SharedElementState | null = await this.captureSourceState(item, index);
    if (!this.isActiveTransition(token)) {
      return;
    }

    this.currentIndex = index;
    this.viewerOpen = true;
    this.contentVisible = true;
    this.contentOpacity = 0;
    this.hiddenSourceId = '';
    this.hiddenViewerMediaId = item.id;
    this.backgroundOpacity = 0;
    this.resetDragState(false);

    if (sourceState === null) {
      this.performOpenFadeFallback(token, index);
      return;
    }

    const targetGeometry: SharedElementGeometry = this.viewerGeometryFor(item);
    this.applySnapshotState(sourceState);
    this.snapshotVisible = true;
    this.hiddenSourceId = item.id;

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
        this.hiddenViewerMediaId = '';
        this.getUIContext().animateTo({ duration: OPEN_CONTENT_FADE_DURATION_MS, curve: Curve.EaseOut }, () => {
          this.contentOpacity = 1;
        });
        setTimeout(() => {
          if (this.isActiveTransition(token)) {
            this.finishOpenTransition(index);
          }
        }, OPEN_CONTENT_FADE_DURATION_MS + 20);
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
        this.hiddenSourceId = this.items[index].id;
        this.finishOpenTransition(index);
      }
    }, OPEN_CONTENT_FADE_DURATION_MS + 20);
  }

  private finishOpenTransition(index: number): void {
    if (index === this.currentIndex) {
      this.hiddenSourceId = this.items[index].id;
    }
    this.snapshotVisible = false;
    this.snapshotPixelMap = null;
    this.transitionActive = false;
    this.resetDragState(false);
  }

  private async closeViewer(): Promise<void> {
    if (this.transitionActive) {
      return;
    }

    const token: number = this.beginTransition();
    const item: LevixelMediaItem = this.items[this.currentIndex];
    const pageState: SharedElementState | null = await this.captureViewerState(item);
    if (!this.isActiveTransition(token)) {
      return;
    }

    const targetState: SharedElementState | null = await this.captureCloseTargetState(item);
    if (!this.isActiveTransition(token)) {
      return;
    }

    if (pageState === null || targetState === null) {
      this.performCloseFadeFallback(token);
      return;
    }

    this.applySnapshotState(pageState);
    this.snapshotVisible = true;
    this.hiddenSourceId = item.id;
    this.hiddenViewerMediaId = item.id;

    setTimeout(() => {
      if (this.isActiveTransition(token)) {
        this.getUIContext().animateTo({ duration: CLOSE_DURATION_MS, curve: Curve.EaseOut }, () => {
          this.applySnapshotGeometry(targetState.geometry);
          this.backgroundOpacity = 0;
          this.contentOpacity = 0;
          this.snapshotRadius = THUMBNAIL_RADIUS;
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
    this.transitionToken += 1;
    this.viewerOpen = false;
    this.contentVisible = false;
    this.contentOpacity = 0;
    this.snapshotVisible = false;
    this.snapshotPixelMap = null;
    this.transitionActive = false;
    this.hiddenSourceId = '';
    this.hiddenViewerMediaId = '';
    this.backgroundOpacity = 0;
    this.snapshotRadius = 0;
    this.resetDragState(false);
  }

  private beginTransition(): number {
    this.transitionToken += 1;
    this.transitionActive = true;
    return this.transitionToken;
  }

  private isActiveTransition(token: number): boolean {
    return this.transitionActive && this.transitionToken === token;
  }

  private async captureSourceState(item: LevixelMediaItem, index: number): Promise<SharedElementState | null> {
    const sourceRect: RectMetrics = this.sourceRectFor(item, index);
    const resource: TransitionImageResource | null = await this.loadImageResource(item.thumbnailUrl);
    if (resource !== null) {
      return this.createImageResourceState(resource, sourceRect, TransitionImageFit.COVER, THUMBNAIL_RADIUS);
    }

    const pixelMap: image.PixelMap | null = await this.capturePixelMap(this.sourceSnapshotId(item));
    if (pixelMap === null) {
      return null;
    }
    return {
      pixelMap: pixelMap,
      geometry: this.defaultGeometryFor(sourceRect),
      radius: THUMBNAIL_RADIUS
    };
  }

  private async captureViewerState(item: LevixelMediaItem): Promise<SharedElementState | null> {
    const resource: TransitionImageResource | null = await this.loadImageResource(this.displayUrl(item));
    if (resource !== null) {
      return this.createImageResourceState(resource, this.currentViewerRectFor(item), TransitionImageFit.FILL, 0);
    }

    const pixelMap: image.PixelMap | null = await this.capturePixelMap(this.viewerSnapshotId(item));
    if (pixelMap === null) {
      return null;
    }
    return {
      pixelMap: pixelMap,
      geometry: this.defaultGeometryFor(this.currentViewerRectFor(item)),
      radius: 0
    };
  }

  private async captureCloseTargetState(item: LevixelMediaItem): Promise<SharedElementState | null> {
    const targetRect: RectMetrics | null = this.closeTargetRectFor(item);
    if (targetRect === null) {
      return null;
    }

    const resource: TransitionImageResource | null = await this.loadImageResource(item.thumbnailUrl);
    if (resource !== null) {
      return this.createImageResourceState(resource, targetRect, TransitionImageFit.COVER, THUMBNAIL_RADIUS);
    }

    const pixelMap: image.PixelMap | null = await this.capturePixelMap(this.sourceSnapshotId(item));
    if (pixelMap === null) {
      return null;
    }
    return {
      pixelMap: pixelMap,
      geometry: this.defaultGeometryFor(targetRect),
      radius: THUMBNAIL_RADIUS
    };
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
    fit: TransitionImageFit,
    radius: number
  ): SharedElementState {
    return {
      pixelMap: resource.pixelMap,
      geometry: this.geometryForImageResource(resource, containerFrame, fit),
      radius: radius
    };
  }

  private applySnapshotState(state: SharedElementState): void {
    this.snapshotPixelMap = state.pixelMap;
    this.snapshotRadius = state.radius;
    this.applySnapshotGeometry(state.geometry);
  }

  private applySnapshotGeometry(geometry: SharedElementGeometry): void {
    this.snapshotRect = cloneRect(geometry.visibleFrame);
    this.snapshotContentRect = cloneRect(geometry.contentFrame);
  }

  private defaultGeometryFor(visibleFrame: RectMetrics): SharedElementGeometry {
    return {
      visibleFrame: cloneRect(visibleFrame),
      contentFrame: {
        left: 0,
        top: 0,
        width: visibleFrame.width,
        height: visibleFrame.height
      }
    };
  }

  private viewerGeometryFor(item: LevixelMediaItem): SharedElementGeometry {
    const resource: TransitionImageResource | undefined = this.imageResourceCache.get(this.displayUrl(item));
    if (resource !== undefined) {
      return this.geometryForImageResource(resource, this.viewerContainerBounds(), TransitionImageFit.CONTAIN);
    }
    return this.defaultGeometryFor(this.targetRectFor(item));
  }

  private sourceSnapshotId(item: LevixelMediaItem): string {
    return `levixel-source-${item.id}`;
  }

  private viewerSnapshotId(item: LevixelMediaItem): string {
    return `levixel-viewer-${item.id}`;
  }

  private preloadTransitionResources(): void {
    this.items.forEach((item: LevixelMediaItem) => {
      this.loadImageResource(item.thumbnailUrl);
      this.loadImageResource(this.displayUrl(item));
    });
  }

  private async loadImageResource(url: string): Promise<TransitionImageResource | null> {
    const cached: TransitionImageResource | undefined = this.imageResourceCache.get(url);
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
    if (resource !== null) {
      this.imageResourceCache.set(url, resource);
    }
    return resource;
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
      const pixelMap: image.PixelMap = await source.createPixelMap();
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      try {
        await source.release();
      } catch (_error) {
      }
      return {
        pixelMap: pixelMap,
        width: Math.max(1, info.size.width),
        height: Math.max(1, info.size.height)
      };
    } catch (_error) {
      return null;
    } finally {
      if (request !== null) {
        request.destroy();
      }
    }
  }

  private geometryForImageResource(
    resource: TransitionImageResource,
    containerFrame: RectMetrics,
    fit: TransitionImageFit
  ): SharedElementGeometry {
    const contentFrame: RectMetrics = this.contentFrameForImageFit(
      resource.width,
      resource.height,
      containerFrame,
      fit
    );
    const visibleFrame: RectMetrics | null = this.intersectionRect(containerFrame, contentFrame);
    const clippedVisibleFrame: RectMetrics = visibleFrame !== null ? visibleFrame : cloneRect(containerFrame);
    return {
      visibleFrame: clippedVisibleFrame,
      contentFrame: {
        left: contentFrame.left - clippedVisibleFrame.left,
        top: contentFrame.top - clippedVisibleFrame.top,
        width: contentFrame.width,
        height: contentFrame.height
      }
    };
  }

  private contentFrameForImageFit(
    imageWidth: number,
    imageHeight: number,
    containerFrame: RectMetrics,
    fit: TransitionImageFit
  ): RectMetrics {
    if (fit === TransitionImageFit.FILL) {
      return cloneRect(containerFrame);
    }

    const widthScale: number = containerFrame.width / Math.max(1, imageWidth);
    const heightScale: number = containerFrame.height / Math.max(1, imageHeight);
    const scale: number = fit === TransitionImageFit.COVER
      ? Math.max(widthScale, heightScale)
      : Math.min(widthScale, heightScale);
    const width: number = imageWidth * scale;
    const height: number = imageHeight * scale;
    return {
      left: containerFrame.left + (containerFrame.width - width) * 0.5,
      top: containerFrame.top + (containerFrame.height - height) * 0.5,
      width: width,
      height: height
    };
  }

  private intersectionRect(first: RectMetrics, second: RectMetrics): RectMetrics | null {
    const left: number = Math.max(first.left, second.left);
    const top: number = Math.max(first.top, second.top);
    const right: number = Math.min(first.left + first.width, second.left + second.width);
    const bottom: number = Math.min(first.top + first.height, second.top + second.height);
    if (right <= left || bottom <= top) {
      return null;
    }
    return {
      left: left,
      top: top,
      width: right - left,
      height: bottom - top
    };
  }

  private updateVerticalDrag(offsetY: number): void {
    if (this.transitionActive) {
      return;
    }
    this.dragOffsetY = offsetY;
    const distanceRatio: number = Math.min(1, Math.abs(offsetY) / Math.max(1, this.rootHeight));
    this.dragScale = Math.max(0.84, 1 - distanceRatio * 0.16);
    this.backgroundOpacity = 1 - Math.min(0.9, distanceRatio * 1.25);
  }

  private finishVerticalDrag(velocityY: number): void {
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
    if (!this.viewerOpen || this.currentIndex < 0 || this.currentIndex >= this.items.length) {
      this.hiddenSourceId = '';
      return;
    }
    this.hiddenSourceId = this.items[this.currentIndex].id;
  }

  private sourceRectFor(item: LevixelMediaItem, index: number): RectMetrics {
    const measured: RectMetrics | null = this.measuredSourceRectFor(item);
    if (measured) {
      return cloneRect(measured);
    }
    const gap: number = 12;
    const sidePadding: number = 12;
    const headerHeight: number = 92;
    const tileWidth: number = (this.rootWidth - sidePadding * 2 - gap) / 2;
    const tileHeight: number = 132;
    const column: number = index % 2;
    const row: number = Math.floor(index / 2);
    return {
      left: sidePadding + column * (tileWidth + gap),
      top: headerHeight + row * (tileHeight + gap),
      width: tileWidth,
      height: tileHeight
    };
  }

  private closeTargetRectFor(item: LevixelMediaItem): RectMetrics | null {
    const measured: RectMetrics | null = this.measuredSourceRectFor(item);
    if (measured === null || !this.isRectVisible(measured)) {
      return null;
    }
    return measured;
  }

  private measuredSourceRectFor(item: LevixelMediaItem): RectMetrics | null {
    const rectInWindow: RectMetrics | undefined = this.tileRectsInWindow.get(item.id);
    if (rectInWindow === undefined) {
      return null;
    }
    return {
      left: rectInWindow.left - this.rootLeft,
      top: rectInWindow.top - this.rootTop,
      width: rectInWindow.width,
      height: rectInWindow.height
    };
  }

  private isRectVisible(rect: RectMetrics): boolean {
    const right: number = rect.left + rect.width;
    const bottom: number = rect.top + rect.height;
    return right > 0 && bottom > 0 && rect.left < this.rootWidth && rect.top < this.rootHeight;
  }

  private targetRectFor(item: LevixelMediaItem): RectMetrics {
    const availableWidth: number = Math.max(1, this.rootWidth);
    const availableHeight: number = Math.max(1, this.rootHeight);
    const resource: TransitionImageResource | undefined = this.imageResourceCache.get(this.displayUrl(item));
    const aspectWidth: number = resource !== undefined ? resource.width : item.aspectWidth;
    const aspectHeight: number = resource !== undefined ? resource.height : item.aspectHeight;
    const scale: number = Math.min(
      availableWidth / Math.max(1, aspectWidth),
      availableHeight / Math.max(1, aspectHeight)
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

  private viewerContainerBounds(): RectMetrics {
    return {
      left: 0,
      top: 0,
      width: Math.max(1, this.rootWidth),
      height: Math.max(1, this.rootHeight)
    };
  }

  private currentViewerRectFor(item: LevixelMediaItem): RectMetrics {
    const baseRect: RectMetrics = this.targetRectFor(item);
    if (this.dragOffsetY === 0 && this.dragScale === 1) {
      return baseRect;
    }
    return {
      left: this.rootWidth * 0.5 + (baseRect.left - this.rootWidth * 0.5) * this.dragScale,
      top: this.rootHeight * 0.5 + (baseRect.top - this.rootHeight * 0.5) * this.dragScale + this.dragOffsetY,
      width: baseRect.width * this.dragScale,
      height: baseRect.height * this.dragScale
    };
  }

  private displayUrl(item: LevixelMediaItem): string {
    return item.mediaType === LevixelMediaType.VIDEO ? item.thumbnailUrl : item.sourceUrl;
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
