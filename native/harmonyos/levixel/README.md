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
  LevixelAction,
  LevixelController,
  LevixelMediaItem,
  LevixelMediaType,
  LevixelSource,
  LevixelSourceImageFit,
  LevixelSourceViewport,
  LevixelViewer,
  LevixelViewerEvent
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

  private readonly actions: LevixelAction[] = [
    {
      id: 'inspect', label: 'View details',
      onPress: (event: LevixelViewerEvent): void => {
        console.info(`Selected media: ${event.payload.itemId}`);
      }
    }
  ];

  onBackPress(): boolean {
    return this.viewer.handleBack();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      LevixelViewer({
        controller: this.viewer, items: this.items,
        actions: this.actions, actionLayout: 'list'
      }) {
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

## Actions and viewer events

`LevixelViewer` and `LevixelGallery` accept an `actions: LevixelAction[]` array.
Actions and their callbacks are captured when the viewer opens.

| Action field | Meaning |
| --- | --- |
| `id` | Unique, non-blank action identifier |
| `label` | Non-blank text, displayed on up to two lines |
| `icon` | Image URI; optional for a list, required for a grid |
| `group` | Optional non-blank group; omitted actions share the default group |
| `disabled` | Defaults to `false`; prevents selection and callbacks |
| `destructive` | Defaults to `false`; danger styling, without business confirmation |
| `onPress` | Optional callback receiving a `LevixelViewerEvent` |

`actionLayout` defaults to `'list'`, independent of the action count. List icons
are hidden unless `actionListIcons` is `true`; missing icons then keep an aligned
empty space. `'grid'` always displays icons and rejects an action without one.
A failed icon load uses a neutral placeholder.

Groups and their actions keep first-appearance order. List groups are separated;
each grid group becomes a horizontally scrollable row. Tall content scrolls
while Cancel stays available. Labels follow system font scaling.

Images and videos recognize long press, excluding playback controls and retry
buttons. Movement and multi-touch cancel recognition. A long press emits
`longPress`; non-empty `actions` also opens a system sheet above the viewer.
An empty array keeps only the event. Selection dismisses the sheet before
emitting `action` and calling `onPress`, leaving the viewer open. The host owns
saving, sharing, navigation, and any permissions required by those operations.

Use the component's `onEvent` or `controller.onEvent(listener)` to receive
`LevixelViewerEvent` values. The controller subscription returns a function
that removes the listener. If these handlers and `onPress` are all installed,
execute each business operation in only one place.

Events include `type`, `time` (Unix milliseconds), and `payload`. Media context
contains `sessionId`, `galleryId`, `index`, `itemId`, and `mediaType`.

| Event | When it fires |
| --- | --- |
| `opened` | The opening transition has finished |
| `longPress` | Long press is recognized, before any sheet opens |
| `indexChange` | The page changes; also includes `currentIndex` |
| `mediaLoad` | The full image is decoded or the video first frame is ready |
| `mediaError` | Loading failed; includes `code: LOAD_FAILED` and `message` |
| `action` | The sheet has closed after selection; includes `actionId` |
| `dismiss` | The session ends, with its final current media context |

Media events can arrive before `opened` or concern an adjacent preloaded page;
use `itemId` rather than assuming all events describe the current page.
Thumbnails and posters do not count as a successful full-media load.
`sessionId` identifies one opening; `index` belongs to its opening snapshot,
not a later host array. Changed actions and media apply to the next open.

`controller.close()` closes the viewer after dismissing an open action sheet.
Forward the page's `onBackPress()`
to `controller.handleBack()`: it dismisses an open sheet first, then the
viewer, and returns whether it handled the request. `controller.retry()`
retries the current failed item and returns whether a retry started. It keeps
the session and does not repeat an active load or retry an ended session.
The viewer also displays a retry button after a media load failure. Cancel and
the sheet backdrop leave the viewer open.

Images support pinch zoom, double-tap zoom, and panning within the image
bounds. Paging and vertical drag dismissal resume at the base zoom scale.
Set `theme` to `'light'` for a white media canvas or leave its default `'dark'`.
The action sheet keeps the same light palette in either theme.

## License and source

Levixel is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for retained upstream notices.

Public releases, documentation, and issue tracking are available in the
[Levixel GitHub repository](https://github.com/sandroxy/levixel).
