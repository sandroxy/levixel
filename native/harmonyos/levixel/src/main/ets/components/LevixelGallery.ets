import {
  LevixelMediaItem,
  LevixelMediaType,
  LevixelSourceImageFit
} from '../model/LevixelModels';
import { LevixelSource } from './LevixelSource';
import { LevixelSourceViewport } from './LevixelSourceViewport';
import { LevixelViewer } from './LevixelViewer';
import { LevixelController } from '../controller/LevixelController';

const GALLERY_VIEWPORT_ID: string = 'gallery-grid';
const THUMBNAIL_RADIUS: number = 8;

@Component
export struct LevixelGallery {
  private readonly controller: LevixelController = new LevixelController();
  @Prop items: LevixelMediaItem[] = [];
  @Prop showsNavigationHeader: boolean = false;
  @Prop navigationTitle: string = 'Levixel';
  @Prop navigationTopInset: number = 0;
  onNavigateBack: () => void = (): void => {};

  build() {
    LevixelViewer({ controller: this.controller, items: this.items }) {
      Column() {
        if (this.showsNavigationHeader) {
          this.NavigationHeader()
        }

        if (!this.showsNavigationHeader) {
          this.DefaultHeader()
        }

        Stack({ alignContent: Alignment.TopStart }) {
          LevixelSourceViewport({
            controller: this.controller,
            viewportId: GALLERY_VIEWPORT_ID
          }) {
            this.GalleryGrid()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.White)
    }
  }

  @Builder
  private DefaultHeader() {
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
  private GalleryGrid() {
    Grid() {
      ForEach(this.items, (item: LevixelMediaItem) => {
        GridItem() {
          LevixelSource({
            controller: this.controller,
            itemId: item.id,
            viewportId: GALLERY_VIEWPORT_ID,
            cornerRadius: THUMBNAIL_RADIUS,
            imageFit: LevixelSourceImageFit.COVER,
            content: (): void => {
              this.ThumbnailImage(item)
            },
            decoration: (): void => {
              this.ThumbnailOverlay(item)
            }
          })
        }
        .width('100%')
        .height(132)
        .backgroundColor('#F2F4F7')
      }, (item: LevixelMediaItem) => item.id)
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(12)
    .rowsGap(12)
    .padding({ left: 12, right: 12, top: 12, bottom: 28 })
    .width('100%')
    .height('100%')
  }

  @Builder
  private ThumbnailImage(item: LevixelMediaItem) {
    Image(item.thumbnailUrl)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
  }

  @Builder
  private ThumbnailOverlay(item: LevixelMediaItem) {
    if (item.mediaType === LevixelMediaType.VIDEO) {
      this.VideoBadge()
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
  }

  @Builder
  private VideoBadge() {
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
  }
}
