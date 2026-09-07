import { LevixelSourceRegistration, LevixelViewerContext } from '../controller/LevixelViewerContext';
import { LevixelController, resolveLevixelContext } from '../controller/LevixelController';
import { LevixelSourceImageFit, RectMetrics } from '../model/LevixelModels';

@Component
export struct LevixelSource {
  controller: LevixelController | null = null;
  @Prop @Watch('handleItemIdChanged') itemId: string = '';
  @Prop @Watch('handleConfigurationChanged') viewportId: string = '';
  @Prop @Watch('handleConfigurationChanged') cornerRadius: number = 0;
  @Prop @Watch('handleConfigurationChanged') imageFit: LevixelSourceImageFit = LevixelSourceImageFit.COVER;
  @Require @BuilderParam content: () => void;
  @BuilderParam decoration?: () => void;

  private registeredItemId: string = '';
  private registrationId: number = 0;
  private mounted: boolean = false;
  private frameInWindow: RectMetrics | null = null;
  private visible: boolean = false;
  @State private snapshotId: string = '';
  @State private hidden: boolean = false;

  private getViewerContext(): LevixelViewerContext {
    return resolveLevixelContext(this.controller);
  }

  aboutToAppear(): void {
    this.mounted = true;
    this.registerSource();
  }

  aboutToReuse(): void {
    this.mounted = true;
    this.registerSource();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.unregisterSource();
    this.clearPhysicalState();
  }

  aboutToRecycle(): void {
    this.mounted = false;
    this.unregisterSource();
    this.clearPhysicalState();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content()
      }
      .width('100%')
      .height('100%')
      .id(this.snapshotId)

      if (this.decoration !== undefined) {
        this.decoration()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .borderRadius(this.cornerRadius)
    .opacity(this.hidden ? 0 : 1)
    .onClick(() => {
      if (!this.mounted) {
        return;
      }
      this.visible = true;
      this.synchronizeRegistration();
      if (this.registrationId !== 0) {
        this.getViewerContext().updateSourceVisibility(this.itemId, this.registrationId, true);
      }
      this.getViewerContext().prepare(this.itemId);
      this.getViewerContext().open(this.itemId);
    })
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
      this.getViewerContext().updateSourceFrame(this.itemId, this.registrationId, this.frameInWindow);
    })
    .onVisibleAreaChange([0.0, 0.01], (_isExpanding: boolean, currentRatio: number) => {
      if (!this.mounted) {
        return;
      }
      this.visible = currentRatio > 0;
      this.synchronizeRegistration();
      if (this.registrationId !== 0) {
        this.getViewerContext().updateSourceVisibility(this.itemId, this.registrationId, this.visible);
        if (this.visible) {
          this.getViewerContext().prepare(this.itemId);
        }
      }
    }, true)
  }

  private handleItemIdChanged(): void {
    this.unregisterSource();
    this.registerSource();
  }

  private handleConfigurationChanged(): void {
    if (this.registrationId !== 0) {
      this.getViewerContext().updateSourceConfiguration(
        this.registeredItemId, this.registrationId, this.viewportId, this.cornerRadius, this.imageFit
      );
    }
  }

  private synchronizeRegistration(): void {
    if (this.registrationId === 0 || this.registeredItemId !== this.itemId) {
      this.unregisterSource();
      this.registerSource();
    }
  }

  private registerSource(): void {
    if (!this.mounted || this.registrationId !== 0) {
      return;
    }
    const registration: LevixelSourceRegistration = this.getViewerContext().registerSource(
      this.itemId,
      this.viewportId,
      this.cornerRadius,
      this.imageFit,
      (hidden: boolean): void => {
        this.hidden = hidden;
      }
    );
    this.registeredItemId = this.itemId;
    this.registrationId = registration.registrationId;
    this.snapshotId = registration.snapshotId;
    if (this.frameInWindow !== null) {
      this.getViewerContext().updateSourceFrame(this.itemId, this.registrationId, this.frameInWindow);
    }
    this.getViewerContext().updateSourceVisibility(this.itemId, this.registrationId, this.visible);
  }

  private unregisterSource(): void {
    if (this.registrationId === 0) {
      return;
    }
    this.getViewerContext().unregisterSource(this.registeredItemId, this.registrationId);
    this.registeredItemId = '';
    this.registrationId = 0;
    this.snapshotId = '';
    this.hidden = false;
  }

  private clearPhysicalState(): void {
    this.frameInWindow = null;
    this.visible = false;
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
