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
import { Image, StyleSheet } from 'react-native';

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
    overflow: 'hidden',
  },
});

<Levixel items={items} theme="dark">
  {items.map((item, index) => (
    <Levixel.Source key={item.id} index={index} style={styles.tile}>
      <Image
        source={{ uri: sourceFor(item) }}
        style={StyleSheet.absoluteFill}
      />
    </Levixel.Source>
  ))}
</Levixel>
```

Keep `items` in the same order as the rendered sources. Each `Levixel.Source`
accepts exactly one React element and its `index` must identify the matching
item. Wrapping the visible source lets Levixel use the real native view as the
opening and return anchor.

Every item `id` must be non-empty and unique within the gallery. `Levixel`
itself accepts an empty `items` array while asynchronous data is loading; render
no `Levixel.Source` until the corresponding item exists.

`galleryId` is optional and is generated automatically; provide one only when
the host needs to assign a stable identity to the gallery. Use `onIndexChange`
when the host needs to observe the currently visible item. Video items should
provide `posterUrl` or `thumbnailUrl` for a source-anchored opening transition.

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
