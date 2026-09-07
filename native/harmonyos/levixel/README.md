# Levixel

Shared-transition image and video viewer for HarmonyOS.

Visible source media expands from its on-screen position, size, and corner
radius into the full-screen viewer, then returns to the corresponding source
when dismissed.

## Installation

```shell
ohpm install @sandrox/levixel
```

## Requirements

- HarmonyOS API 23 or newer
- Phone devices
- Network access for remote thumbnails, images, and videos

The HAR declares `ohos.permission.INTERNET` so it can load remote media URLs
supplied by the host application.

## Usage

```ts
import {
  LevixelController,
  LevixelMediaItem,
  LevixelMediaType,
  LevixelSource,
  LevixelSourceImageFit,
  LevixelSourceViewport,
  LevixelViewer
} from '@sandrox/levixel';

@Entry
@Component
struct GalleryPage {
  private readonly viewer: LevixelController = new LevixelController();
  @State private items: LevixelMediaItem[] = [
    {
      id: 'coast',
      mediaType: LevixelMediaType.IMAGE,
      sourceUrl: 'https://example.com/coast.jpg',
      thumbnailUrl: 'https://example.com/coast-thumb.jpg',
      title: 'Wide Coast',
      aspectWidth: 2400,
      aspectHeight: 1600
    }
  ];

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      LevixelViewer({ controller: this.viewer, items: this.items }) {
        Column() {
          Row() {
            Text('Photos')
              .fontSize(24)
              .layoutWeight(1)
            Button('Open first')
              .enabled(this.items.length > 0)
              .onClick(() => {
                this.viewer.open(this.items[0].id);
              })
          }
          .width('100%')
          .padding(16)

          Stack({ alignContent: Alignment.TopStart }) {
            LevixelSourceViewport({ controller: this.viewer, viewportId: 'media-grid' }) {
              Grid() {
                ForEach(this.items, (item: LevixelMediaItem) => {
                  GridItem() {
                    LevixelSource({
                      controller: this.viewer,
                      itemId: item.id,
                      viewportId: 'media-grid',
                      cornerRadius: 12,
                      imageFit: LevixelSourceImageFit.COVER,
                      content: (): void => {
                        this.Thumbnail(item)
                      }
                    })
                  }
                  .height(160)
                }, (item: LevixelMediaItem) => item.id)
              }
              .columnsTemplate('1fr 1fr')
              .width('100%')
              .height('100%')
            }
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Thumbnail(item: LevixelMediaItem) {
    Image(item.thumbnailUrl)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
  }
}
```

`LevixelViewer` owns only the full-screen presentation layer; everything inside
its content builder remains host-owned UI. Place it at the root of the region
the viewer must cover. Create one `LevixelController` as a plain, stable field
and pass that same instance to the viewer and its sources and viewports. Do not
recreate it in `build()` or wrap it in `@State` or `@Prop`; the components share
the controller by object identity. A controller belongs to one mounted viewer.

A `LevixelSource` marks each currently mounted media source by stable `itemId`
and opens it when tapped. To open from another control, call
`controller.open(itemId)` after the viewer has mounted. The ID must exist in
the viewer's current `items`; opening without a visible source uses a fade.

Supply the host's image renderer through `content`, with the same media and
composition as the item's `thumbnailUrl`. Define the UI in an `@Builder` method,
then call it from the builder parameter as shown above. Use `decoration` for labels or badges;
it is hidden with the source during transitions but excluded from snapshots.
The source's `cornerRadius` controls both visible clipping and transition
geometry, and `imageFit` must match the renderer's actual fit. Custom filters or
transforms that change the thumbnail's appearance are not reproduced by the
shared transition.

Wrap a scrolling or virtualized source collection in
`LevixelSourceViewport`, then give its sources the same non-empty `viewportId`.
Viewport IDs must be unique within their controller.
The registered viewport defines the real clipping boundary: any positive-area
intersection remains a valid return target, while a fully clipped or unmounted
source produces a safe fade. Sources that are not inside a clipping container
may omit both the viewport and `viewportId`.

Every media item requires a stable, unique `id`, a full-resolution `sourceUrl`,
a `thumbnailUrl`, a display `title`, and finite positive `aspectWidth` and
`aspectHeight` values. For video items, use `LevixelMediaType.VIDEO`; the
thumbnail is also the playback poster. Rendering more than one visible source
for the same item is ambiguous and fails explicitly.

The host may replace `items` after prepending history, appending a page, or
reordering its data. Keep every media `id` stable and unique. An open viewer
uses an immutable snapshot of the array it opened with; later host updates are
used the next time the viewer opens. `items` may also contain unloaded or
off-screen entries with no mounted `LevixelSource`. If the current snapshot
item no longer has a visible source in the updated host UI,
dismissal uses a fade instead of returning to a stale position.

For a ready-made two-column screen, use `LevixelGallery`, a convenience
component implemented on the same `LevixelViewer`,
`LevixelSourceViewport`, and `LevixelSource` primitives, with its own controller.
Its navigation header is optional: set `showsNavigationHeader` to `true`,
provide `navigationTitle`, pass the window's top safe-area inset through
`navigationTopInset`, and handle `onNavigateBack` with the host router.

## License and source

Levixel is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for retained upstream notices.

Public releases, documentation, and issue tracking are available in the
[Levixel GitHub repository](https://github.com/sandroxy/levixel).
