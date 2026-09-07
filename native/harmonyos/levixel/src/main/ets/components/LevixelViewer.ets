import { LevixelController, resolveLevixelContext } from '../controller/LevixelController';
import { LevixelMediaItem } from '../model/LevixelModels';
import { LevixelViewerHost } from './LevixelViewerHost';

@Component
export struct LevixelViewer {
  controller: LevixelController | null = null;
  @Prop items: LevixelMediaItem[] = [];
  @Require @BuilderParam content: () => void;

  aboutToAppear(): void {
    resolveLevixelContext(this.controller);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()

      LevixelViewerHost({
        controller: this.controller,
        items: this.items
      })
    }
    .width('100%')
    .height('100%')
  }
}
