# Levixel Web

Framework-independent Web runtime for Levixel's shared-transition image and video viewer. A source media element expands continuously from its visible position, size, and corner radius into the full-screen viewer, then returns to the corresponding source when dismissed.

The package is ESM-only, includes public type declarations, and has no runtime dependencies. Importing it during server-side rendering is safe; viewer and preload calls require a live browser document.

## Installation

```sh
npm install @sandrox/levixel-web
```

## API

The Web package implements the shared Levixel JavaScript API:

```ts
import {
  closeLevixel,
  onLevixelEvent,
  onLevixelSourceActivate,
  openLevixel,
  openLevixelFromSelector,
  prepareLevixelItem,
  retryLevixel,
  type LevixelMediaItem,
  warmupLevixelItem,
} from '@sandrox/levixel-web';
```

For a list that can paginate, reorder, or virtualize, bind only the currently
mounted source elements by stable media ID:

```ts
const items: LevixelMediaItem[] = [
  {
    id: 'coast',
    type: 'image',
    url: '/media/coast-2400.jpg',
    thumbnailUrl: '/media/coast-600.jpg',
    width: 2400,
    height: 1600,
    alt: 'Wide coast',
  },
];

const mountedSources = () =>
  [...document.querySelectorAll<HTMLElement>('[data-levixel-item-id]')];

const sourceBindings = () => mountedSources().map(source => ({
  itemId: source.dataset.levixelItemId!,
  selector: `#${source.id}`,
  objectFit: 'cover' as const,
  cornerRadius: 12,
}));

const bindLevixelSource = (source: HTMLElement) =>
  onLevixelSourceActivate(source, () => {
    const itemId = source.dataset.levixelItemId!;
    void openLevixelFromSelector({
      items,
      initialItemId: itemId,
      sourceBindings: sourceBindings(),
    });
  });

```

Call `bindLevixelSource` from the list cell's mount hook and call its returned
disposer from the matching unmount hook. Newly virtualized cells therefore get
their own activation handler without retaining detached elements.

Every bound selector must identify at most one element. Bindings may be sparse
and in any order; `itemId` maps each mounted source to the current `items`
snapshot. Unknown or repeated ids, repeated selectors, and mixing
`sourceBindings` with `sourceSelector`/`sourceStyles` are rejected instead of
being guessed. In the example, every mounted source therefore needs its own
non-empty DOM `id`. A source that unmounts before return simply uses a fade for
that item. If a virtual list reuses the same DOM node for another media ID,
Levixel rejects that stale return target and fades instead of transitioning to
the recycled cell.

`onLevixelSourceActivate` preserves ordinary click activation for mouse, keyboard, and assistive input. On touch devices it recognizes a primary, movement-bounded tap from Pointer Events, so a source remains immediately responsive after vertical drag dismissal even when the browser suppresses the follow-up compatibility `click`. Scrolling or a cancelled pointer does not activate the source.

For a fixed gallery whose source elements are all mounted in exactly the same
order as `items`, the concise static mode remains available:

```ts
void openLevixelFromSelector({
  items,
  index: 0,
  sourceSelector: '.gallery-source',
  sourceStyles: items.map(() => ({ objectFit: 'cover', cornerRadius: 12 })),
});
```

In static mode, omitting the selector, returning a count different from
`items.length`, or measuring unusable geometry produces an all-null source
snapshot. The viewer still opens without a shared source transition rather
than guessing a wrong item.

Each media `id` must be non-empty and unique within one open request. The shared Levixel contract treats it as stable media identity, so the Web runtime rejects duplicates instead of accepting a request that other adapters cannot anchor unambiguously.

One viewer session pages through the loaded `items` captured by that open call.
Appending or prepending host data is supported on the next open; Levixel does
not fetch another host page from inside an already open viewer.

`openLevixel` accepts already measured `sourceHints` for hosts that own their DOM geometry. `prepareLevixelItem` preloads the transition preview (thumbnail or poster, falling back to the image URL), while `warmupLevixelItem` first reuses dimensions from an already loaded source element and otherwise preloads the same preview. Neither function runs automatically merely because the host renders a thumbnail list.

## Long press and actions

Both opening functions accept `actions`, `actionLayout`, and `actionListIcons`:

```ts
await openLevixelFromSelector({
  items,
  initialItemId: 'coast',
  sourceBindings: sourceBindings(),
  actionLayout: 'list',
  actions: [
    { id: 'inspect', label: 'View details', group: 'tools',
      onPress: context => showDetails(context.itemId) },
  ],
});
```

`showDetails` is application code. The viewer provides the sheet and its layer
above the media; saving, sharing, navigation, and permissions belong to the host.

| Action field | Meaning |
| --- | --- |
| `id` | Unique, non-blank action identifier |
| `label` | Non-blank text, displayed on up to two lines |
| `icon` | Image URI; optional for a list, required for a grid |
| `group` | Optional non-blank group; omitted actions share the default group |
| `disabled` | Defaults to `false`; prevents selection and callbacks |
| `destructive` | Defaults to `false`; danger styling, without business confirmation |
| `onPress` | Optional callback receiving media context and `actionId` |

The default `actionLayout` is `'list'`, independent of the action count. List
icons are hidden unless `actionListIcons` is `true`; a missing list icon then
keeps an aligned empty space. `'grid'` always shows icons and requires one for
every action. Failed icon loads use a neutral placeholder. Invalid action
configuration is rejected before opening.

Groups and their actions keep first-appearance order. List groups are separated;
each grid group forms one horizontally scrollable row. Tall content scrolls
vertically while Cancel stays available. The sheet keeps a light palette in
either viewer theme, accounts for safe areas, and supports keyboard navigation.

Images and videos recognize long press, excluding video controls and retry
buttons. Moving or adding another pointer cancels recognition. Empty or omitted
`actions` emits only `longPress`. The viewer suppresses image context menus and
selection within its own media, including the iOS Safari image callout; source
elements in the host page keep their normal browser behavior.

Selection dismisses the sheet before the `action` event and `onPress` callback,
leaving the viewer open. If both callbacks handle an action, execute the business
operation in only one. Cancel, the backdrop, and Escape close the sheet first;
`closeLevixel()` closes the whole viewer. Await it before presenting host UI
that requires the viewer to be gone.

## Events and retry

```ts
const removeListener = onLevixelEvent(event => {
  console.log(event.type, event.payload);
});

// From a host retry control:
const { retried } = await retryLevixel();
// When the host no longer needs viewer events:
removeListener();
```

Events use `{ type, payload, time }`, with `time` in Unix milliseconds.
Media context contains `sessionId`, `galleryId`, `index`, `itemId`, and
`mediaType` (`image` or `video`).

| Event | Meaning |
| --- | --- |
| `ready` | The event channel is ready; the viewer need not be open |
| `opened` | The opening transition has finished |
| `longPress` | Long press is recognized, before the sheet opens |
| `indexChange` | The page changes; includes `currentIndex` and media identity |
| `mediaLoad` | The full image is decoded or the video first frame is ready |
| `mediaError` | Loading failed; includes `code: LOAD_FAILED` and `message` |
| `action` | The sheet has closed after selection; includes `actionId` |
| `dismiss` | The session ends, with its final current media context |
| `sourceVisibilityChange` | A source changes visibility; includes `hidden`, `galleryId`, `index`, and `itemId` |

Load events may describe a preloaded adjacent item or arrive before `opened`.
Use their `itemId`; thumbnails and posters do not count as a successful full
media load. The viewer shows a retry button after failure. `retryLevixel()`
returns `{ retried: boolean }`, keeps the existing session, and does not repeat
a request that is loading or has no eligible failure. `closeLevixel()` resolves
with `{ closed: true }` after dismissal.

## Product behavior

- Images start aspect-fitted. Pinch or trackpad zoom, zoomed panning, double-tap zoom, horizontal paging, tap dismissal, and vertical drag dismissal follow the same interaction model as the native viewers.
- Thumbnail-to-full handoff keeps the preview visible while a synchronized full-resolution layer decodes, then atomically returns to one `<img>` on the next rendering update. Relative zoom and normalized visual center are preserved throughout.
- Images show no counter, toolbar, or always-visible close button. `counter: true` and `closeButton: true` fail contract validation instead of silently inventing UI.
- Video starts from its poster, primes the first frame, and shows the matching close, play, and timeline controls after a video tap.
- `Escape` dismisses the action sheet first, then the viewer. Left/right arrow keys page while the current image is fitted and the sheet is closed. Levixel does not modify browser history or a host router.
- The viewer is an accessible modal, traps focus while open, restores the previous focus and inline page styles on close, and respects reduced-motion preferences.

Web defaults `sourceVisibility` to `hidden`, matching the standalone Android/iOS source-handoff semantics. Classic UniApp intentionally remains `visible` to avoid a last-frame source flash in its WebView/Vapor handoff; the Web runtime does not change that platform-specific default.

## Lifecycle

Only one Web viewer session can exist. Opening again ends the previous session,
restores its source, and emits its `dismiss` once. Each opening retains its
media, actions, and action callbacks. Updating host arrays affects the next
open. Use `itemId` for business data and `sessionId` to distinguish openings;
`index` belongs to the opening snapshot, not a later host array.

Action callbacks wait for the sheet's dismissal. Closing or replacing the
session during that dismissal cancels a still-pending selection callback.
Repeated `closeLevixel()` calls wait for the same viewer to finish closing.

Backgrounding a page pauses active video without clearing subscriptions or closing the viewer. Resize and `visualViewport` changes re-fit unzoomed media and preserve zoomed viewport state.

## Browser boundary

The supported interaction matrix covers macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.

The implementation relies on Pointer Events, the Web Animations API, Shadow DOM, and modern media elements. Browsers outside the supported matrix, embedded WebViews, and compatibility bundles for legacy browsers are not claimed. No UMD, IIFE, or separately maintained browser implementation is shipped.

## License and source

Levixel Web is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[PROVENANCE.md](PROVENANCE.md) for retained upstream notices and source
lineage.

For source builds and browser testing, see the
[development guide](https://github.com/sandroxy/levixel/blob/master/DEVELOPMENT.md#web).
