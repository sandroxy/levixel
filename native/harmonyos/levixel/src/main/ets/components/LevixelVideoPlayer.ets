import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';

@Component
export struct LevixelVideoPlayer {
  @Prop itemId: string = '';
  @Prop sourceUrl: string = '';
  @Prop active: boolean = false;
  @Prop showPosterForDismiss: boolean = false;
  onCloseRequested: () => void = (): void => {};
  onControlInteractionChange: (active: boolean) => void = (_active: boolean): void => {};

  private readonly surfaceController: XComponentController = new XComponentController();
  private player: media.AVPlayer | null = null;
  private surfaceId: string = '';
  private playbackGeneration: number = 0;
  private controlInteractionActive: boolean = false;
  private wasPlayingBeforeScrub: boolean = false;

  @State private firstFrameReady: boolean = false;
  @State private loading: boolean = false;
  @State private playbackFailed: boolean = false;
  @State private playing: boolean = false;
  @State private controlsVisible: boolean = false;
  @State private durationMs: number = 0;
  @State private currentTimeMs: number = 0;
  @State private scrubTimeMs: number = 0;
  @State private scrubbing: boolean = false;

  aboutToDisappear(): void {
    this.releasePlayer();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.active) {
        XComponent({
          id: `levixel-video-surface-${this.itemId}`,
          type: XComponentType.TEXTURE,
          controller: this.surfaceController
        })
          .width('100%')
          .height('100%')
          .opacity(this.firstFrameReady && !this.showPosterForDismiss ? 1 : 0)
          .animation({ duration: 140, curve: Curve.EaseOut })
          .onLoad(() => {
            this.surfaceId = this.surfaceController.getXComponentSurfaceId();
            this.preparePlayer();
          })
          .onDestroy(() => {
            this.surfaceId = '';
            this.releasePlayer();
          })
      }

      if (this.active && this.loading && !this.playbackFailed && !this.showPosterForDismiss) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(Color.White)
      }

      if (this.active && this.firstFrameReady && this.controlsVisible && !this.showPosterForDismiss) {
        this.VideoControls()
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      if (!this.active) {
        return;
      }
      if (this.playbackFailed) {
        this.releasePlayer();
        this.preparePlayer();
        return;
      }
      this.controlsVisible = !this.controlsVisible;
    })
  }

  @Builder
  private VideoControls() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('×')
          .fontSize(30)
          .fontColor(Color.White)
      }
      .width(48)
      .height(48)
      .margin({ left: 12, top: 12 })
      .borderRadius(24)
      .backgroundColor('#66000000')
      .onTouch((event: TouchEvent) => {
        this.handleControlTouch(event);
      })
      .onClick(() => {
        this.onCloseRequested();
      })

      Row() {
        Stack({ alignContent: Alignment.Center }) {
          Text(this.playing ? 'Ⅱ' : '▶')
            .fontSize(this.playing ? 17 : 20)
            .fontColor(Color.White)
        }
        .width(44)
        .height(44)
        .onClick(() => {
          this.togglePlayback();
        })

        Slider({
          value: this.scrubbing ? this.scrubTimeMs : this.currentTimeMs,
          min: 0,
          max: Math.max(1, this.durationMs),
          step: 1,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor(Color.White)
          .trackColor('#66FFFFFF')
          .blockColor(Color.White)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.handleSliderChange(value, mode);
          })

        Text(`${this.formatTime(this.scrubbing ? this.scrubTimeMs : this.currentTimeMs)} / ${this.formatTime(this.durationMs)}`)
          .fontSize(12)
          .fontColor(Color.White)
          .margin({ left: 8 })
      }
      .height(56)
      .padding({ left: 6, right: 12 })
      .margin({ left: 12, right: 12, bottom: 20 })
      .borderRadius(12)
      .backgroundColor('#99000000')
      .align(Alignment.Bottom)
      .onTouch((event: TouchEvent) => {
        this.handleControlTouch(event);
      })
    }
    .width('100%')
    .height('100%')
  }

  private preparePlayer(): void {
    if (!this.active || this.surfaceId.length === 0 || this.player !== null) {
      return;
    }

    const generation: number = ++this.playbackGeneration;
    this.firstFrameReady = false;
    this.loading = true;
    this.playbackFailed = false;
    this.playing = false;
    this.durationMs = 0;
    this.currentTimeMs = 0;
    media.createAVPlayer()
      .then((player: media.AVPlayer) => {
        if (!this.isCurrentGeneration(generation) || !this.active || this.surfaceId.length === 0) {
          player.release().catch((_error: BusinessError) => {});
          return;
        }
        this.player = player;
        this.bindPlayerEvents(player, generation);
        try {
          player.url = this.sourceUrl;
        } catch (_error) {
          this.handlePlayerFailure(generation);
        }
      })
      .catch((_error: BusinessError) => {
        this.handlePlayerFailure(generation);
      });
  }

  private bindPlayerEvents(player: media.AVPlayer, generation: number): void {
    player.on('stateChange', (state: media.AVPlayerState, _reason: media.StateChangeReason) => {
      if (!this.isCurrentPlayer(player, generation)) {
        return;
      }
      if (state === 'initialized') {
        try {
          player.surfaceId = this.surfaceId;
          player.prepare().catch((_error: BusinessError) => {
            this.handlePlayerFailure(generation);
          });
        } catch (_error) {
          this.handlePlayerFailure(generation);
        }
      } else if (state === 'prepared') {
        this.durationMs = Math.max(0, player.duration);
        this.playPlayer();
      } else if (state === 'playing') {
        this.playing = true;
      } else if (state === 'paused') {
        this.playing = false;
      } else if (state === 'completed') {
        this.playing = false;
        this.currentTimeMs = this.durationMs;
      } else if (state === 'error') {
        this.handlePlayerFailure(generation);
      }
    });
    player.on('startRenderFrame', () => {
      if (!this.isCurrentPlayer(player, generation)) {
        return;
      }
      this.firstFrameReady = true;
      this.loading = false;
      this.playbackFailed = false;
    });
    player.on('timeUpdate', (timeMs: number) => {
      if (!this.isCurrentPlayer(player, generation) || this.scrubbing) {
        return;
      }
      this.currentTimeMs = Math.max(0, timeMs);
    });
    player.on('durationUpdate', (durationMs: number) => {
      if (!this.isCurrentPlayer(player, generation)) {
        return;
      }
      this.durationMs = Math.max(0, durationMs);
    });
    player.on('error', (_error: BusinessError) => {
      this.handlePlayerFailure(generation);
    });
  }

  private playPlayer(): void {
    const player: media.AVPlayer | null = this.player;
    if (player === null || !this.active) {
      return;
    }
    if (player.state === 'completed') {
      player.seek(0, media.SeekMode.SEEK_CLOSEST);
      this.currentTimeMs = 0;
    }
    if (player.state !== 'prepared' && player.state !== 'paused' && player.state !== 'completed') {
      return;
    }
    player.play().catch((_error: BusinessError) => {
      this.handlePlayerFailure(this.playbackGeneration);
    });
  }

  private pausePlayer(): void {
    const player: media.AVPlayer | null = this.player;
    if (player === null || player.state !== 'playing') {
      return;
    }
    player.pause().catch((_error: BusinessError) => {
      this.handlePlayerFailure(this.playbackGeneration);
    });
  }

  private togglePlayback(): void {
    if (this.playing) {
      this.pausePlayer();
    } else {
      this.playPlayer();
    }
  }

  private handleSliderChange(value: number, mode: SliderChangeMode): void {
    if (mode === SliderChangeMode.Begin) {
      this.beginControlInteraction();
      this.scrubbing = true;
      this.scrubTimeMs = value;
      this.wasPlayingBeforeScrub = this.playing;
      this.pausePlayer();
      return;
    }
    if (mode === SliderChangeMode.Moving) {
      this.scrubTimeMs = value;
      return;
    }

    if (mode === SliderChangeMode.Click) {
      this.beginControlInteraction();
      this.wasPlayingBeforeScrub = this.playing;
      this.pausePlayer();
    }
    this.scrubTimeMs = value;
    this.currentTimeMs = value;
    const player: media.AVPlayer | null = this.player;
    if (player !== null) {
      try {
        player.seek(Math.round(value), media.SeekMode.SEEK_CLOSEST);
      } catch (_error) {
      }
    }
    this.scrubbing = false;
    if (this.wasPlayingBeforeScrub) {
      this.playPlayer();
    }
    this.endControlInteraction();
  }

  private handleControlTouch(event: TouchEvent): void {
    event.stopPropagation();
    if (event.type === TouchType.Down) {
      this.beginControlInteraction();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.endControlInteraction();
    }
  }

  private beginControlInteraction(): void {
    if (this.controlInteractionActive) {
      return;
    }
    this.controlInteractionActive = true;
    this.onControlInteractionChange(true);
  }

  private endControlInteraction(): void {
    if (!this.controlInteractionActive) {
      return;
    }
    this.controlInteractionActive = false;
    this.onControlInteractionChange(false);
  }

  private handlePlayerFailure(generation: number): void {
    if (!this.isCurrentGeneration(generation)) {
      return;
    }
    this.loading = false;
    this.playbackFailed = true;
    this.playing = false;
    this.firstFrameReady = false;
  }

  private releasePlayer(): void {
    this.endControlInteraction();
    this.playbackGeneration += 1;
    const player: media.AVPlayer | null = this.player;
    this.player = null;
    this.firstFrameReady = false;
    this.loading = false;
    this.playbackFailed = false;
    this.playing = false;
    this.controlsVisible = false;
    this.scrubbing = false;
    this.wasPlayingBeforeScrub = false;
    this.durationMs = 0;
    this.currentTimeMs = 0;
    if (player === null) {
      return;
    }
    player.release().catch((_error: BusinessError) => {});
  }

  private isCurrentGeneration(generation: number): boolean {
    return this.playbackGeneration === generation;
  }

  private isCurrentPlayer(player: media.AVPlayer, generation: number): boolean {
    return this.player === player && this.isCurrentGeneration(generation) && this.active;
  }

  private formatTime(milliseconds: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(milliseconds / 1000));
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    const minuteText: string = minutes < 10 ? `0${minutes}` : minutes.toString();
    const secondText: string = seconds < 10 ? `0${seconds}` : seconds.toString();
    return `${minuteText}:${secondText}`;
  }
}
