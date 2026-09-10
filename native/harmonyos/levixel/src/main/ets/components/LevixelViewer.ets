import { LevixelAction, LevixelActionLayout, LevixelViewerEvent } from '../model/LevixelModels';
import { LevixelController, resolveLevixelContext } from '../controller/LevixelController';
import { LevixelMediaItem } from '../model/LevixelModels';
import { LevixelViewerHost } from './LevixelViewerHost';

@Component
export struct LevixelViewer {
  controller: LevixelController | null = null;
  @Prop items: LevixelMediaItem[] = [];
  @Prop actions: LevixelAction[] = [];
  @Prop actionLayout: LevixelActionLayout = 'list';
  @Prop actionListIcons: boolean = false;
  @Prop theme: 'dark' | 'light' = 'dark';
  onEvent: (event: LevixelViewerEvent) => void = (_event: LevixelViewerEvent): void => {};
  @Require @BuilderParam content: () => void;

  aboutToAppear(): void {
    resolveLevixelContext(this.controller);
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()

      LevixelViewerHost({
        controller: this.controller,
        items: this.items, actions: this.actions, actionLayout: this.actionLayout, actionListIcons: this.actionListIcons, theme: this.theme, onEvent: this.onEvent
      })
    }
    .width('100%')
    .height('100%')
  }
}
