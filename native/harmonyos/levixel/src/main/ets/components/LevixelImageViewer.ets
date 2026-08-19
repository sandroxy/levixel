@Component
export struct LevixelImageViewer {
  @Prop sourceUrl: string = '';

  @State private fullImageVisible: boolean = false;
  @State private loadFailed: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.sourceUrl)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .opacity(this.fullImageVisible ? 1 : 0)
        .animation({ duration: 120, curve: Curve.EaseOut })
        .onComplete(() => {
          this.loadFailed = false;
          this.fullImageVisible = true;
        })
        .onError(() => {
          this.loadFailed = true;
          this.fullImageVisible = false;
        })

      if (!this.fullImageVisible && !this.loadFailed) {
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
