# Levixel

Shared-transition image and video viewer for HarmonyOS.

Visible source media expands from its on-screen position, size, and corner
radius into the full-screen viewer, then returns to the corresponding source
when dismissed.

## Installation

```shell
ohpm install @sandrox/levixel
```

## Public API

```ts
import {
  LevixelGallery,
  LevixelMediaItem,
  LevixelMediaType,
  RectMetrics
} from '@sandrox/levixel';
```

`LevixelGallery` provides the gallery surface. Media descriptors and source
geometry use the exported model types.

Public releases, documentation, and issue tracking are available at:

https://github.com/sandroxy/levixel
