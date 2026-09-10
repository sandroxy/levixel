# @sandrox/levixel

React Native and Expo integration for the Levixel shared-transition image and
video viewer.

Visible source media expands from its on-screen position, size, and corner
radius into the full-screen viewer, then returns to the corresponding source
when dismissed. The package includes the React Native components and the
required Android and iOS native runtimes.

## Install

```sh
pnpm add @sandrox/levixel
```

Levixel contains native code and requires a development build or a prebuilt
native application. It does not run in Expo Go.

```sh
npx expo prebuild
```

## Usage

```tsx
import { Levixel, type LevixelMediaItem } from '@sandrox/levixel';
import { FlatList, Image, StyleSheet } from 'react-native';

const items: LevixelMediaItem[] = [
  {
    id: 'cover',
    type: 'image',
    url: fullImageUrl,
    thumbnailUrl,
  },
];

const sourceFor = (item: LevixelMediaItem): string =>
  item.type === 'video'
    ? item.posterUrl ?? item.thumbnailUrl ?? item.url
    : item.thumbnailUrl ?? item.url;

const styles = StyleSheet.create({
  tile: {
    width: 160,
    height: 160,
    borderRadius: 12,
    overflow: 'hidden',
  },
});

<Levixel items={items} theme="dark">
  <FlatList
    data={items}
    keyExtractor={item => item.id}
    renderItem={({ item }) => (
      <Levixel.Source itemId={item.id} style={styles.tile}>
        <Image
          source={{ uri: sourceFor(item) }}
          style={StyleSheet.absoluteFill}
        />
      </Levixel.Source>
    )}
  />
</Levixel>
```

Each `Levixel.Source` accepts exactly one React element. Prefer `itemId` for
lists that can prepend, append, reorder, paginate, or virtualize: the source is
resolved against the current `items` by stable media identity on every render.
An `index` may be used instead for a fixed, fully rendered gallery. The two
properties are mutually exclusive and an unknown identity fails immediately.

For a rounded source, put one non-negative numeric `borderRadius` and
`overflow: 'hidden'` on `Levixel.Source` itself, as in the example. That style
is the single source of truth for both the visible clipping boundary and the
native transition geometry. Percentage, animated, and per-corner radii are not
representable by the uniform shared-element snapshot and fail explicitly.

Render `Levixel.Source` only for currently mounted list cells. `items` may
contain additional loaded media that is not on screen; those entries remain
pageable in the viewer but have no source-anchored return transition while
unmounted. One open viewer uses the current `items` as its session snapshot;
loading another page in the host affects the next open rather than mutating the
active viewer.

Every item `id` must be non-empty and unique within the gallery. `Levixel`
itself accepts an empty `items` array while asynchronous data is loading; render
no `Levixel.Source` until the corresponding item exists.

`galleryId` is optional and is generated automatically; provide one only when
the host needs to assign a stable identity to the gallery. `onIndexChange`
receives both the session index and stable `itemId`; use the id when host data
can change while the viewer is open. Video items should provide `posterUrl` or
`thumbnailUrl` for a source-anchored opening transition.

## Actions and direct control

Use `actions`, `actionLayout`, and `actionListIcons` on `<Levixel>`. A ref can
also open a media item without a mounted thumbnail, close the viewer, or retry
its current failed media:

```tsx
import { useRef, type ReactNode } from 'react';
import { Button } from 'react-native';
import { Levixel, type LevixelMediaItem, type LevixelRef } from '@sandrox/levixel';

export function Gallery({ items, children, onInspect }: {
  items: readonly LevixelMediaItem[];
  children: ReactNode;
  onInspect: (itemId: string) => void;
}) {
  const viewer = useRef<LevixelRef>(null);
  return (
    <Levixel
      ref={viewer}
      items={items}
      actions={[
        { id: 'inspect', label: 'View details',
          onPress: context => onInspect(context.itemId) },
      ]}
      actionLayout="list"
      onEvent={event => console.log(event.type, event.payload.itemId)}
    >
      <Button title="Open first" disabled={items.length === 0} onPress={() => {
        if (items.length > 0) void viewer.current?.open(items[0].id);
      }} />
      {children}
    </Levixel>
  );
}
```

`children` is the host's source list, bound with `Levixel.Source` as above.
The native viewer places the action sheet above itself. The host implements
saving, sharing, navigation, and any permissions required by those operations.

| `LevixelAction` field | Meaning |
| --- | --- |
| `id` | Unique, non-blank action identifier |
| `label` | Non-blank text, displayed on up to two lines |
| `icon` | Image URI; optional for a list, required for a grid |
| `group` | Optional non-blank group; omitted actions share the default group |
| `disabled` | Defaults to `false`; disables selection and callbacks |
| `destructive` | Defaults to `false`; danger styling, without business confirmation |
| `onPress` | Optional callback receiving media context and `actionId` |

`actionLayout` defaults to `'list'` and never depends on the action count.
List icons stay hidden unless `actionListIcons` is `true`; missing list icons
then keep an aligned empty space. `'grid'` always shows icons and rejects any
action without one. Resolve bundled React Native images to URIs with
`Image.resolveAssetSource(...).uri`. Failed image loads use a neutral placeholder.

Groups and actions keep first-appearance order. List groups are separated;
each grid group becomes a horizontally scrollable row. Tall content scrolls
while Cancel remains available. The sheet keeps a light palette in either
viewer theme and follows the platform's system font scaling and presentation.

Long press works on images and videos, excluding playback controls and retry
buttons. Dragging or adding a second finger cancels recognition. Missing or
empty `actions` emits only `longPress`, with no sheet. Selection dismisses the
sheet before notifying `onPress` and the `action` event; the viewer stays open.
If both callbacks handle actions, execute the business operation in only one.

| `LevixelRef` method | Result |
| --- | --- |
| `open(itemId)` | `Promise<void>`; requests opening a known stable ID, including off-screen items |
| `close()` | `Promise<void>`; resolves after the entire viewer closes |
| `retry()` | `Promise<boolean>`; reports whether a retry of current failed media started |

`open()` completion means the native request was created; the `opened` event
marks transition completion. Retry keeps the same session and returns `false`
when no failed media is eligible. The viewer also shows a retry button.
For another host modal, await `viewer.current?.close()` before presenting it.
A ref is only available while `<Levixel>` is mounted; optional chaining can
therefore produce `undefined`.

## Viewer events and lifecycle

`onEvent` receives a `LevixelEvent` with `{ type, payload, time }`; `time` is
Unix time in milliseconds. Media context contains `sessionId`, `galleryId`,
`index`, `itemId`, and `mediaType` (`image` or `video`).

| Event | When it fires |
| --- | --- |
| `opened` | The opening transition has finished |
| `longPress` | Long press is recognized, before a sheet opens |
| `indexChange` | The page changes; also includes `currentIndex` |
| `mediaLoad` | The full image is decoded or the video first frame is ready |
| `mediaError` | Loading failed; includes `code: LOAD_FAILED` and `message` |
| `action` | The sheet has closed after selection; includes `actionId` |
| `dismiss` | The session ends, with its final current media context |

The native initial `indexChange` precedes `opened`. Adjacent preloaded media may
emit load events before opening finishes or while another page is visible;
check `itemId` rather than assuming they describe the current page. A thumbnail
or poster alone is not a successful media load.

Each opening retains its media, actions, and action callbacks. Later renders
configure the next opening; `onEvent` and `onIndexChange` use current props.
Use `itemId` for business data and `sessionId` to distinguish openings; the
index belongs to the opening snapshot, not a subsequently updated host array.
Unmounting `<Levixel>` cleans up its viewer.

Cancel, the sheet backdrop, and native Back dismiss an open sheet first.
A programmatic `close()` closes the whole viewer. Keep the JavaScript thread
responsive for opening requests and business callbacks; the native runtimes
perform the viewer animations.

## Requirements

- Expo SDK 54 or newer
- React Native 0.81 or newer
- React 19 or newer
- iOS 15.1 or newer

Android hosts must remain edge-to-edge for uninterrupted system-bar
transitions. Pure React Native hosts must also make Maven Central and JitPack
available because the Android runtime uses PhotoView from JitPack.

## Distribution

The npm package includes the Android and iOS binaries required by the adapter;
installation does not download or build Levixel source code. Platform-specific
behavior remains in the native runtimes rather than being reimplemented in
JavaScript.

Levixel is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](https://github.com/sandroxy/levixel/blob/master/THIRD_PARTY_NOTICES.md)
and [PROVENANCE.md](https://github.com/sandroxy/levixel/blob/master/PROVENANCE.md)
for retained upstream notices and source lineage.
