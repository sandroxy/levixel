# Changelog

## 1.4.0

Unreleased.

- Adds configurable long-press actions, explicit list/grid layouts, optional list icons, grouped scrolling rows, and keyboard access.
- Aligns the drawer palette and spacing with the native viewers, with animated opening and dismissal that respect reduced-motion preferences. Action callbacks run after the drawer closes.
- Adds session-aware lifecycle and media-load events, visible retry, and `retryLevixel()`.
- Replacement now emits the outgoing viewer's `dismiss` event with its media and session context.
- Repeated close requests wait for the same completed dismissal; replacing a closing drawer cancels its pending action.
- Keeps keyboard-focused actions visible within scrolling drawers without shifting the media, and prevents playback from resuming when a media-load callback closes the viewer.

## 1.3.0

- Restored shared transitions for thumbnails scrolled into view by correcting document-root viewport clipping.
- Rejected duplicate media ids so each request has an unambiguous stable identity.
- Added stable ID `initialItemId` and sparse `sourceBindings` for prepended,
  appended, reordered, paginated, and virtualized DOM galleries.
- Added `itemId` to open results and index/source-visibility events.

## 1.2.0

- Added the first framework-independent Levixel Web runtime.
- Preserved the shared media, source-hint, source-visibility, and event protocol.
- Added shared source transitions, paging, fit/zoom/pan handoff, vertical dismissal, video controls, lifecycle restoration, accessibility, and reduced-motion handling.
- Preserved the visible preview until a decoded full-resolution image can take over atomically, preventing black flashes during rapid image switching.
- Added bounded source activation so a source can reopen immediately after touch drag dismissal without duplicate activation.
- Added automated unit, package, and real-Chrome interaction regression coverage.
- Added support for macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.
