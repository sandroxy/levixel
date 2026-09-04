const FULL_IMAGE_FADE_DURATION_MS: number = 140;

@Component
export struct LevixelImageViewer {
  @Prop sourceUrl: string = '';

  @State private fullImageReady: boolean = false;
  @State private fullImageOpacity: number = 0;
  @State private loadFailed: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.sourceUrl)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .opacity(this.fullImageOpacity)
        .onComplete(() => {
          this.loadFailed = false;
          this.fullImageReady = true;
          this.getUIContext().animateTo({ duration: FULL_IMAGE_FADE_DURATION_MS, curve: Curve.EaseOut }, () => {
            this.fullImageOpacity = 1;
          });
        })
        .onError(() => {
          this.loadFailed = true;
          this.fullImageReady = false;
          this.fullImageOpacity = 0;
        })

      if (!this.fullImageReady && !this.loadFailed) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(Color.White)
      }
    }
    .width('100%')
    .height('100%')
  }
}
