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
  LevixelGallery,
  LevixelMediaItem,
  LevixelMediaType
} from '@sandrox/levixel';

@Entry
@Component
struct GalleryPage {
  private readonly items: LevixelMediaItem[] = [
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
    LevixelGallery({
      items: this.items
    })
  }
}
```

`LevixelGallery` renders the thumbnail grid and the full-screen viewer as one
surface so opening and return transitions stay anchored to the corresponding
item. Every media item requires a stable `id`, a full-resolution `sourceUrl`, a
`thumbnailUrl`, a display `title`, and positive `aspectWidth` / `aspectHeight`
values. For video items, set `mediaType` to `LevixelMediaType.VIDEO` and use the
thumbnail as the poster shown before playback.

The host may replace `items` after prepending history, appending a page, or
reordering its data. Keep every media `id` stable and unique. An open viewer
uses an immutable snapshot of the array it opened with; later host updates are
shown by the grid and take effect the next time the viewer opens. If the
current snapshot item no longer has a visible source in the updated grid,
dismissal uses a fade instead of returning to a stale position.

The navigation header is optional. When enabling it, provide
`navigationTitle`, pass the host window's top safe-area inset through
`navigationTopInset`, and handle `onNavigateBack` with the host application's
router. `RectMetrics` and `cloneRect` are exported for hosts that need to work
with Levixel source geometry directly.

## License and source

Levixel is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for retained upstream notices.

Public releases, documentation, and issue tracking are available in the
[Levixel GitHub repository](https://github.com/sandroxy/levixel).
