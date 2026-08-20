# @sandrox/levixel

React Native and Expo adapter for the Levixel shared-transition image and video
viewer.

The package contains thin Expo Modules bridges plus checksum-verified Levixel
native artifacts. It does not compile or copy the native viewer source into the
consuming application.

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

<Levixel items={items} theme="dark">
  {items.map((item, index) => (
    <Levixel.Source key={item.id} index={index} style={styles.tile}>
      <Image
        source={{ uri: item.thumbnailUrl ?? item.posterUrl ?? item.url }}
        style={StyleSheet.absoluteFill}
      />
    </Levixel.Source>
  ))}
</Levixel>
```

`Levixel.Source` must wrap the visible source image. This lets the native bridge
register its real platform view and preserve the shared pickup and return
transition.

## Requirements

- Expo SDK 54 or newer
- React Native 0.81 or newer
- React 19 or newer
- iOS 15.1 or newer

Android hosts must remain edge-to-edge for uninterrupted system-bar
transitions. Pure React Native hosts must also make Maven Central and JitPack
available because the validated Android core currently retains PhotoView 2.3.0.

## Distribution

Each npm release embeds the exact Android AAR and iOS XCFramework recorded by
the matching Levixel native release. The bridges contain platform integration
only; the native viewer core has a single canonical implementation.

Levixel is released under the MIT License. See `THIRD_PARTY_NOTICES.md` and
`PROVENANCE.md` for retained upstream notices and audited lineage.
