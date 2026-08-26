# Levixel Web

Framework-independent Web runtime for Levixel's shared-transition image and video viewer.

This directory is currently a source candidate, not a published npm release. Its package is deliberately marked `private` and uses the development-only version `0.0.0-development` until browser hand verification is complete and the coordinated Levixel release version is chosen.

## Validation demo

```sh
cd adapters/web
npm install
npm run dev
```

Open the printed local URL. The demo uses the same 18 media entries as the accepted UniApp validation page, including `Wide Coast` and the video cases, so behavior can be compared without treating the earlier H5 proof of concept as product source.

For an iPhone or another device on the same trusted local network, expose the validation server on the LAN:

```sh
npm run dev:device
```

Open the printed `Network` URL on the device. Stop the server after validation; this command intentionally listens on all local interfaces.

Run all static, unit, and real-Chrome checks with:

```sh
npm run verify
```

Set `LEVIXEL_CHROME_PATH` if Chrome or Chromium is installed outside the standard macOS/Linux locations.

## API

The Web package preserves the canonical Levixel JavaScript protocol:

```ts
import {
  closeLevixel,
  onLevixelEvent,
  onLevixelSourceActivate,
  openLevixel,
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
} from '@sandrox/levixel-web';
```

For a DOM gallery, keep the source elements in the same order as `items` and call the selector helper:

```ts
const items = [
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

const sourceStyles = items.map(() => ({ objectFit: 'cover', cornerRadius: 12 }));
const disposers = [...document.querySelectorAll<HTMLElement>('.gallery-source')].map(
  (source, index) => onLevixelSourceActivate(source, () => {
    void openLevixelFromSelector({
      items,
      index,
      sourceSelector: '.gallery-source',
      sourceStyles,
    });
  }),
);

const disposeGalleryActivation = () => disposers.forEach(dispose => dispose());
```

`onLevixelSourceActivate` preserves native click activation for mouse, keyboard, and assistive input. On touch devices it recognizes a primary, movement-bounded tap from Pointer Events, so a source remains immediately responsive after vertical drag dismissal even when the browser suppresses the follow-up compatibility `click`. Scrolling or a cancelled pointer does not activate the source.

If the selector is omitted, does not match exactly one element per item, or the selected source has no usable geometry, Levixel opens with its native-style fade/loading fallback rather than guessing the wrong source rectangle.

`openLevixel` accepts already measured `sourceHints` for hosts that own their DOM geometry. `prepareLevixelItem` and `warmupLevixelItem` only use the browser image cache; they do not download originals while a thumbnail list is merely being rendered unless the host explicitly calls them.

## Product behavior

- Images start aspect-fitted. Pinch/trackpad zoom, zoomed panning, double-tap zoom, horizontal paging, tap dismissal, and vertical drag dismissal follow the accepted native behavior.
- Thumbnail-to-full handoff keeps the preview visible while a synchronized full-resolution layer decodes, then atomically returns to one `<img>` on the next rendering update. Relative zoom and normalized visual center are preserved throughout.
- Images show no counter, toolbar, or always-visible close button. `counter: true` and `closeButton: true` fail contract validation instead of silently inventing UI.
- Video starts from its poster, primes the first frame, and exposes the matching close/play/timeline chrome after a video tap.
- `Escape` closes and the left/right arrow keys page while the current image is fitted. Levixel does not modify browser history or a host router.
- The viewer is an accessible modal, traps focus while open, restores the previous focus and inline page styles on close, and respects reduced-motion preferences.

Web defaults `sourceVisibility` to `hidden`, matching the standalone Android/iOS source-handoff semantics. Classic UniApp intentionally remains `visible`; that accepted platform-specific default is not changed by this runtime.

## Lifecycle

Only one Web viewer session can exist. Opening again atomically replaces the previous session, restores its source element, and does not emit a duplicate `dismiss` event. `sourceVisibilityChange`, `indexChange`, and `dismiss` keep the canonical event JSON shape and timestamp semantics.

Backgrounding a page pauses active video without clearing subscriptions or closing the viewer. Resize and `visualViewport` changes re-fit unzoomed media and preserve zoomed viewport state.

## Browser boundary

Importing the module is SSR-safe, but viewer and preload functions require a live browser document. The implementation relies on Pointer Events, the Web Animations API, Shadow DOM, and modern media elements. Automated coverage runs in real Chrome; Safari/iPhone and additional desktop/mobile hand verification remain release gates before support claims or npm publication.
