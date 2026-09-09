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

## Actions and viewer control (development branch)

These additions are pending release. `<Levixel>` accepts `actions`, `onEvent`,
and a `ref` typed as `LevixelRef`:

```tsx
const viewer = useRef<LevixelRef>(null);
<Levixel ref={viewer} items={items} actions={[
  { id: 'inspect', label: 'Inspect', group: 'tools',
    onPress: context => showDetails(context.itemId) },
]} onEvent={event => console.log(event.type, event.payload.itemId)}>
  {children}
</Levixel>
// No mounted Source is required for programmatic opening.
await viewer.current?.open(items[0].id);
await viewer.current?.retry(); // boolean: whether a failed media request restarted
await viewer.current?.close();
```

Import `useRef` from React and `LevixelRef` from this package. Each action has a
unique `id`, `label`, optional URI `icon`, section `group`, `disabled`, `destructive`,
and `onPress`. Resolve bundled images with `Image.resolveAssetSource(...).uri`.
No actions means an event-only long press. The native drawer closes before the
business callback and leaves the viewer open. System Back closes the drawer
first; the ref's close method closes the entire viewer. Business behavior and
permissions belong to the application.
The close Promise resolves after dismissal, so subsequent native UI can be
presented from the host. The open Promise resolves when the native viewer request
has been created; wait for `opened` to observe the completed opening transition.

`actionLayout: 'list' | 'grid'` defaults to `'list'` and never changes with action
count. Lists support any number of actions and hide icons by default, even when
provided. Set `actionListIcons: true` to show list icons; missing icons leave an
aligned empty column. Grid always shows icons and requires a non-empty `icon`
on every action, including a single-action grid. Invalid grid configuration is
rejected before opening. Groups form list sections or horizontal grid rows;
excess content scrolls while Cancel stays accessible. Failed icons use a neutral
placeholder, never the first letter of the action label.

Events are `opened`, `longPress`, `indexChange`, `mediaLoad`, `mediaError`,
`action`, and `dismiss`. Their context contains `sessionId`, `galleryId`, `index`,
`itemId`, `mediaType`; action adds `actionId`, indexChange retains `currentIndex`,
and mediaError adds `code` and `message`. `opened` means the transition finished;
preloaded pages may report media readiness earlier. The existing `onIndexChange`
prop continues to work. Use either `onPress` or the `action` event for side effects.

Each opening retains its media, action configuration, and action callbacks across
rerenders and source cell recycling. `onEvent` and `onIndexChange` use the current
props. Use `itemId` for asynchronous work; `index` refers to that opening's array.
Unmounting the provider closes its viewer. Failures show a retry button.
