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

`onLevixelSourceActivate` preserves ordinary click activation for mouse, keyboard, and assistive input. On touch devices it recognizes a primary, movement-bounded tap from Pointer Events, so a source remains immediately responsive after vertical drag dismissal even when the browser suppresses the follow-up compatibility `click`. Scrolling or a cancelled pointer does not activate the source.

If the selector is omitted, does not match exactly one element per item, or the selected source has no usable geometry, Levixel opens with its native-style fade/loading fallback rather than guessing the wrong source rectangle.

Each media `id` must be non-empty and unique within one open request. The shared Levixel contract treats it as stable media identity, so the Web runtime rejects duplicates instead of accepting a request that other adapters cannot anchor unambiguously.

`openLevixel` accepts already measured `sourceHints` for hosts that own their DOM geometry. `prepareLevixelItem` preloads the transition preview (thumbnail or poster, falling back to the image URL), while `warmupLevixelItem` first reuses dimensions from an already loaded source element and otherwise preloads the same preview. Neither function runs automatically merely because the host renders a thumbnail list.

## Product behavior

- Images start aspect-fitted. Pinch or trackpad zoom, zoomed panning, double-tap zoom, horizontal paging, tap dismissal, and vertical drag dismissal follow the same interaction model as the native viewers.
- Thumbnail-to-full handoff keeps the preview visible while a synchronized full-resolution layer decodes, then atomically returns to one `<img>` on the next rendering update. Relative zoom and normalized visual center are preserved throughout.
- Images show no counter, toolbar, or always-visible close button. `counter: true` and `closeButton: true` fail contract validation instead of silently inventing UI.
- Video starts from its poster, primes the first frame, and shows the matching close, play, and timeline controls after a video tap.
- `Escape` closes and the left/right arrow keys page while the current image is fitted. Levixel does not modify browser history or a host router.
- The viewer is an accessible modal, traps focus while open, restores the previous focus and inline page styles on close, and respects reduced-motion preferences.

Web defaults `sourceVisibility` to `hidden`, matching the standalone Android/iOS source-handoff semantics. Classic UniApp intentionally remains `visible` to avoid a last-frame source flash in its WebView/Vapor handoff; the Web runtime does not change that platform-specific default.

## Lifecycle

Only one Web viewer session can exist. Opening again atomically replaces the previous session, restores its source element, and does not emit a duplicate `dismiss` event. `sourceVisibilityChange`, `indexChange`, and `dismiss` use the shared Levixel event JSON shape and timestamp semantics.

Backgrounding a page pauses active video without clearing subscriptions or closing the viewer. Resize and `visualViewport` changes re-fit unzoomed media and preserve zoomed viewport state.

## Browser boundary

The supported interaction matrix covers macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.

The implementation relies on Pointer Events, the Web Animations API, Shadow DOM, and modern media elements. Browsers outside the supported matrix, embedded WebViews, and compatibility bundles for legacy browsers are not claimed. No UMD, IIFE, or separately maintained browser implementation is shipped.

## Local development

```sh
cd adapters/web
npm ci
npm run dev
```

Open the printed local URL to exercise mixed images and videos, portrait and landscape media, loading states, paging, and repeated open/close transitions.

For an iPhone or another device on the same trusted local network, expose the development server on the LAN:

```sh
npm run dev:device
```

Open the printed `Network` URL on the device. Stop the server after testing; this command intentionally listens on all local interfaces.

Run the static, unit, and real-Chrome checks with:

```sh
npm run verify
```

Set `LEVIXEL_CHROME_PATH` if Chrome or Chromium is installed outside the standard macOS/Linux locations.

## License

Levixel Web is released under the MIT License. See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[PROVENANCE.md](PROVENANCE.md) for retained upstream notices and source
lineage.
