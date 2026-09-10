# Levixel for Android

Shared-transition image and video viewer for Android API 21 and newer.

## Installation

Add Maven Central and JitPack to dependency resolution:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

Use the latest stable version shown on [Maven Central](https://central.sonatype.com/artifact/io.gitee.sandrox/levixel):

```kotlin
dependencies {
    implementation("io.gitee.sandrox:levixel:<version>")
}
```

The viewer uses PhotoView from JitPack for image zooming and panning. Maven
resolves the other runtime dependencies, including Material Components for the
action sheet. An offline AAR is also available from
[GitHub Releases](https://github.com/sandroxy/levixel/releases); when using it,
add the dependencies declared in the matching Maven POM yourself.

## Open a viewer

The public classes are in `com.sandrox.levixel`. On the UI thread, register the
visible source and add a viewer to the host's full-screen root view:

```java
LevixelMediaItem item = new LevixelMediaItem(
        "cover", LevixelMediaItem.MediaType.IMAGE, fullImageUrl, thumbnailUrl
);
List<LevixelMediaItem> items = Collections.singletonList(item);
String galleryId = "article-gallery";
LevixelSourceViewRegistry.register(
        LevixelSharedElementNames.forItem(galleryId, item), sourceImageView
);

LevixelViewerOverlayView viewer = new LevixelViewerOverlayView(
        activity, items, 0, false, galleryId, null
);
rootView.addView(viewer);
```

`activity` is the active host Activity, `rootView` its full-screen container,
and `sourceImageView` the mounted thumbnail. Use an edge-to-edge host for
uninterrupted system-bar transitions. The boolean constructor argument selects
the media canvas: `false` for dark, `true` for light. For video, use
`LevixelMediaItem.MediaType.VIDEO` with the video URL and poster URL.

The media list must be non-empty, with a unique, non-empty `id` for every item.
Each viewer copies its opening list. Host pagination or reordering affects the
next open, while the current viewer continues paging through its snapshot.

## Dynamic and rounded sources

Register each currently visible `ImageView` with the same `galleryId` and its
stable media ID. Before rebinding a reusable cell, call
`LevixelSourceViewRegistry.unregisterView(imageView)`, then register the new
media identity. Unregister sources when the host removes them.

Dismissal resolves the latest visible registered source by stable ID. If that
source is unmounted or fully clipped, the viewer fades instead of returning to
another cell at the same index. Items without a mounted thumbnail can still be
opened and paged through.

For a rounded source, use `register(key, imageView, cornerRadiusPx)` with the
uniform visible clipping radius in physical pixels. If only part of the source
intersects its effective viewport, the transition preserves that intersection
without rounding the list's clipping edge. Hosts that already own reliable
source geometry may use the constructor overload with `sourceHints`.

## Long press and actions

Pass actions and a listener to the full constructor:

```java
List<LevixelAction> actions = Collections.singletonList(
        new LevixelAction("inspect", "View details", event -> {
            String itemId = (String) event.payload.get("itemId");
            showDetails(itemId);
        })
);

LevixelViewerOverlayView viewer = new LevixelViewerOverlayView(
        activity, items, null, 0, false, galleryId,
        actions, LevixelActionLayout.LIST, false,
        new LevixelViewerOverlayView.Listener() {
            @Override public void onOverlayDismissed() {
                // Release the host's reference to this viewer.
            }
            @Override public void onOverlayIndexChange(int index) {}
            @Override public void onViewerEvent(LevixelViewerEvent event) {
                Log.d("Gallery", event.type + ": " + event.payload);
            }
        }
);
rootView.addView(viewer);
```

`showDetails` is application code. Levixel owns the sheet above the viewer;
the application owns saving, sharing, navigation, and any required permissions.

The full action constructor is
`LevixelAction(id, label, icon, group, disabled, destructive, onPress)`:

| Field | Meaning |
| --- | --- |
| `id` | Unique, non-blank action identifier |
| `label` | Non-blank text, displayed on up to two lines |
| `icon` | Image URI; nullable for lists, required for grids |
| `group` | Optional non-blank group; omitted actions share the default group |
| `disabled` | Prevents selection and callbacks |
| `destructive` | Danger styling; business confirmation remains the host's responsibility |
| `onPress` | Optional callback receiving a `LevixelViewerEvent` |

`LevixelActionLayout.LIST` is the default, regardless of the number of actions.
The following `actionListIcons` boolean defaults to `false`; set it to `true`
to show supplied list icons. Missing list icons keep an aligned empty space.
`GRID` always shows icons and rejects an action without one. A failed icon
load displays a neutral placeholder while preserving the label and action.

Groups and their actions retain first-appearance order. In a list, groups are
separated; in a grid, each group becomes one horizontally scrollable row.
Tall content scrolls vertically while Cancel remains available. The sheet keeps
its light palette in either viewer theme and follows system font scaling.

Long press works on images and videos; video controls and retry buttons do not
activate it. Moving or adding a second pointer cancels recognition. Empty
actions emit `longPress` without showing a sheet. Selecting an enabled action
closes the sheet before the action event and callback; the viewer stays open.
If both `onPress` and `onViewerEvent` handle an action, execute its business
operation in only one of them.

## Events, closing, and retry

`onViewerEvent` receives `type`, Unix time in milliseconds as `time`, and an
immutable `payload` map. Its media context is
`sessionId`, `galleryId`, `index`, `itemId`, and `mediaType` (`image` or `video`).
`getSessionId()` identifies this opening. Use `itemId` for asynchronous work;
`index` only identifies a position in the opening snapshot.

| Event | When it fires |
| --- | --- |
| `opened` | The opening transition has finished |
| `longPress` | Long press is recognized, before any action sheet opens |
| `indexChange` | The page changes; also includes `currentIndex` |
| `mediaLoad` | The full image is decoded or the video first frame is ready |
| `mediaError` | Loading failed; includes `code: LOAD_FAILED` and `message` |
| `action` | The sheet has closed after selection; includes `actionId` |
| `dismiss` | The viewer session ends, with its final current media context |

The initial `indexChange` precedes `opened`. Preloaded adjacent media can emit
load events before opening finishes or while another page is current; check
`itemId` rather than assuming all events refer to the visible page. Thumbnails
and posters do not count as a successful full-media load. Actions and their
callbacks are retained from the opening configuration.

Route the host's system Back handler to `viewer.handleBack()`: it closes an
open sheet first, then the viewer. Cancel and the sheet backdrop also leave the
viewer open. `viewer.requestClose()` explicitly closes the whole viewer;
`onOverlayDismissed` reports completion, and the viewer removes itself from its
parent. `dismissImmediately()` is available when an immediate close is needed.

`viewer.retry()` retries the current failed media and returns whether a request
started. It keeps the same session and does not start another request while
loading, after close, or when there is no eligible failed item. The viewer also
offers an on-screen retry button. Make viewer calls on the UI thread.

## License

Levixel is released under the MIT License. See [the retained notices](../../THIRD_PARTY_NOTICES.md).
