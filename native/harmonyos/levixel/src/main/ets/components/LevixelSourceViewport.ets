import { LevixelViewerContext } from '../controller/LevixelViewerContext';
import { LevixelController, resolveLevixelContext } from '../controller/LevixelController';
import { RectMetrics } from '../model/LevixelModels';

@Component
export struct LevixelSourceViewport {
  controller: LevixelController | null = null;
  @Prop @Watch('handleViewportIdChanged') viewportId: string = '';
  @Require @BuilderParam content: () => void;

  private registeredViewportId: string = '';
  private registrationId: number = 0;
  private mounted: boolean = false;
  private frameInWindow: RectMetrics | null = null;

  private getViewerContext(): LevixelViewerContext {
    return resolveLevixelContext(this.controller);
  }

  aboutToAppear(): void {
    this.mounted = true;
    this.registerViewport();
  }

  aboutToReuse(): void {
    this.mounted = true;
    this.registerViewport();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.unregisterViewport();
    this.frameInWindow = null;
  }

  aboutToRecycle(): void {
    this.mounted = false;
    this.unregisterViewport();
    this.frameInWindow = null;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldArea, newArea) => {
      if (!this.mounted) {
        return;
      }
      this.synchronizeRegistration();
      if (this.registrationId === 0) {
        return;
      }
      this.frameInWindow = {
        left: this.asPositionNumber(newArea.globalPosition.x),
        top: this.asPositionNumber(newArea.globalPosition.y),
        width: this.asDimension(newArea.width),
        height: this.asDimension(newArea.height)
      };
      this.getViewerContext().updateViewportFrame(this.viewportId, this.registrationId, this.frameInWindow);
    })
  }

  private handleViewportIdChanged(): void {
    this.unregisterViewport();
    this.registerViewport();
  }

  private synchronizeRegistration(): void {
    if (this.registrationId === 0 || this.registeredViewportId !== this.viewportId) {
      this.unregisterViewport();
      this.registerViewport();
    }
  }

  private registerViewport(): void {
    if (!this.mounted || this.registrationId !== 0) {
      return;
    }
    this.registrationId = this.getViewerContext().registerViewport(this.viewportId);
    this.registeredViewportId = this.viewportId;
    if (this.frameInWindow !== null) {
      this.getViewerContext().updateViewportFrame(this.viewportId, this.registrationId, this.frameInWindow);
    }
  }

  private unregisterViewport(): void {
    if (this.registrationId === 0) {
      return;
    }
    this.getViewerContext().unregisterViewport(this.registeredViewportId, this.registrationId);
    this.registeredViewportId = '';
    this.registrationId = 0;
  }

  private asPositionNumber(value: Length | undefined): number {
    if (value === undefined || (typeof value !== 'number' && typeof value !== 'string')) {
      return 0;
    }
    const numeric: number = Number(value);
    return Number.isFinite(numeric) ? numeric : 0;
  }

  private asDimension(value: Length | undefined): number {
    return Math.max(0, this.asPositionNumber(value));
  }
}
