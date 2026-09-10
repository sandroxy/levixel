# Levixel for iOS

Shared-transition image and video viewer for iOS 13.0 and newer.

## Installation

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/sandroxy/levixel.git
```

Choose **Up to Next Major Version**, using the latest stable
[GitHub Release](https://github.com/sandroxy/levixel/releases) as the lower bound,
or **Exact Version** to pin one release. Link `Levixel` to the App target.
Swift Package Manager verifies the downloaded XCFramework's checksum.

## Media and source binding

```swift
import Levixel

let items: [LevixelMediaItem] = [
    .imageURL(fullImageURL, thumbnailURL: thumbnailURL, placeholder: imageView.image),
    .video(url: videoURL, poster: posterURL)
]
let dataSource = LevixelArrayDataSource(
    items: items,
    itemIdentifiers: ["cover", "video"]
)
imageView.setupLevixelViewer(
    dataSource: dataSource,
    initialIndex: 0,
    configuration: LevixelViewerConfiguration(theme: .dark),
    galleryId: "article-gallery"
)
```

Configure each currently visible source `UIImageView` with the same data source
and `galleryId`, using its own `initialIndex`. `setupLevixelViewer` installs tap
activation. To open from another host control, call
`imageView.presentLevixelViewer(dataSource:initialIndex:configuration:galleryId:)`;
it returns an optional `LevixelViewerSession`. Supply `from:` when the host needs
to select the presenting view controller explicitly.

Use unique, non-empty `itemIdentifiers`, one per item, for dynamic lists. The
viewer captures its opening data. After a prepend, removal, or reorder, configure
the currently visible cells from the latest snapshot. An open viewer retains
its media order, while dismissal resolves the current source by stable ID.
Unavailable sources fade instead of returning to another cell at the same index.

Call `removeLevixelViewerInteraction()` before a reusable cell is rebound.
The viewer normally reads the `UIImageView` clipping radius. If an equal-sized
outer container owns the visible radius, pass that same value in the cell's
`LevixelViewerConfiguration.sourceCornerRadius`. A partly visible source uses
its real viewport intersection; a fully clipped or detached source is not a
shared-transition target.

## Long press and actions

Configure actions before binding the source. This example keeps a session in
its host view controller for later close and retry calls:

```swift
private var viewerSession: LevixelViewerSession?

private func bindViewer() {
    let configuration = LevixelViewerConfiguration(
        theme: .dark,
        actions: [
            LevixelAction(id: "inspect", label: "View details") { [weak self] event in
                self?.showDetails(itemId: event.context.itemId)
            }
        ],
        actionLayout: .list,
        actionListIcons: false,
        onEvent: { event in
            print(event.type, event.context.itemId)
        },
        onSession: { [weak self] session in
            self?.viewerSession = session
        }
    )
    imageView.setupLevixelViewer(
        dataSource: dataSource,
        initialIndex: 0,
        configuration: configuration,
        galleryId: "article-gallery"
    )
}
```

`imageView`, `dataSource`, and `showDetails(itemId:)` belong to the host. Use weak
captures when a retained source configuration calls its owning view controller.
Levixel places the sheet above the viewer. Saving, sharing, navigation, and any
required permissions remain application code.

| `LevixelAction` field | Meaning |
| --- | --- |
| `id` | Unique, non-blank action identifier |
| `label` | Non-blank text, displayed on up to two lines |
| `icon` | Optional `URL` for a list; required for a grid |
| `group` | Optional non-blank group; omitted actions share the default group |
| `disabled` | Defaults to `false`; prevents selection and callbacks |
| `destructive` | Defaults to `false`; danger styling, without business confirmation |
| `onPress` | Optional callback receiving `LevixelViewerEvent` |

`actionLayout` defaults to `.list`, regardless of the number of actions.
List icons are optional and stay hidden unless `actionListIcons` is `true`;
missing icons then keep an aligned empty space. `.grid` always shows icons and
requires one for every action. A failed icon load uses a neutral placeholder.
Invalid action IDs, blank text, or a grid action without an icon fail validation.

Groups and actions retain first-appearance order. List groups are separated;
each grid group becomes a horizontally scrollable row. Tall content scrolls
while Cancel remains available. The sheet keeps a light palette in either
viewer theme, follows Dynamic Type, and uses the system sheet presentation on
iOS 15 and newer. Its surrounding shape and transition follow the OS; older
supported systems use a UIKit presentation fallback.

Long press recognizes images and videos, excluding video controls and retry
buttons. Dragging or a second finger cancels recognition. An empty `actions`
array emits `longPress` without opening a sheet. Selection closes the sheet
before emitting `action` and calling `onPress`, leaving the viewer open. Use
only one of those callbacks for the business operation if both are installed.

## Events and session control

`configuration.onEvent` receives `LevixelViewerEvent`: `type`, `context`, optional
`actionId`, and `time` (Unix milliseconds). `context` contains `sessionId`,
`galleryId`, `index`, `itemId`, and `mediaType` (`image` or `video`).
`event.dictionary` exposes the equivalent `{ type, payload, time }` form.

| Event | When it fires |
| --- | --- |
| `opened` | The opening transition has finished |
| `longPress` | Long press is recognized, before any sheet opens |
| `indexChange` | The page changes; the dictionary payload includes `currentIndex` |
| `mediaLoad` | The full image is decoded or the video first frame is ready |
| `mediaError` | Loading failed; the dictionary payload includes `code: LOAD_FAILED` and `message` |
| `action` | The sheet has closed after selection; includes `actionId` |
| `dismiss` | The session ends, with its final current media context |

The initial `indexChange` precedes `opened`. Adjacent media can emit loading
events before the transition finishes or while another page is current.
Use `itemId` to associate events with media, and `sessionId` to identify an
opening. An `index` belongs only to that opening snapshot. Legacy data sources
without stable identifiers use the index string as `itemId`; dynamic lists
should provide explicit IDs. Thumbnails and posters are not a full-media load.
The existing `onIndexChange` and `onDismiss` callbacks remain available.

Each opening retains its actions and callbacks. Receive the session through
`onSession`, or retain the value returned by `presentLevixelViewer`. Cancel,
tapping the sheet backdrop, and dismissing the sheet leave the viewer open.
`session.close()` closes the entire viewer, including an open sheet. Use its
completion when presenting another host interface after close:

```swift
viewerSession?.close { [weak self] in
    self?.presentBusinessInterface()
}
```

Call `session.retry()` on the main thread to retry the current failed media;
it returns whether a retry started. Retry keeps the session and is a no-op when
there is no eligible failed media, another load is in progress, or the session
has ended. The viewer also displays a retry button after a load failure.

## License

Levixel is released under the MIT License. See [the retained notices](../../THIRD_PARTY_NOTICES.md).
