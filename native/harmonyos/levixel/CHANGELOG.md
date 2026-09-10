# Changelog

## 1.4.0 - Unreleased

- Adds long-press events and a native action drawer with configurable groups and callbacks.
- Supports explicit list and grid layouts, optional list icons, and required grid icons.
- Adds pinch zoom and bounded panning, coordinated with paging and drag dismissal.
- Adds session events, media load/error events, and visible/programmatic retry.
- Preserves zoomed image geometry during closing, waits for sheet dismissal, and isolates late video callbacks from replacement players.

## 1.3.0 - 2026-09-07

- Aligns the package version with the coordinated Levixel 1.3.0 release.
- Separates the full-screen viewer from host-owned source UI through
  `LevixelViewer`, `LevixelSource`, and `LevixelSourceViewport`, connected by an
  explicit `LevixelController`; the ready-made `LevixelGallery` uses the same
  public primitives.
- Adds `LevixelController.open(itemId)` for host-controlled opening alongside
  direct source taps.
- Supports paginated, prepended, reordered, and virtualized source collections
  by stable media ID, including precise scroll-viewport clipping and safe fades
  for fully unavailable return sources.
- Keeps each open viewer on an immutable media snapshot, preserves thumbnail
  proportions, and bounds transition-image caching. Opening and dismissal do
  not wait for a transition image to download.

## 1.2.0 - 2026-08-28

- Aligns the package version with the coordinated Levixel 1.2.0 release.
- Keeps the HarmonyOS API and viewer behavior unchanged.

## 1.1.1 - 2026-08-25

- Aligns the package version with the Levixel 1.1.1 cross-platform release.
- Keeps the HarmonyOS API and viewer behavior unchanged.

## 1.1.0 - 2026-08-20

- Aligns the package version with the Levixel 1.1.0 cross-platform release.
- Keeps the HarmonyOS viewer behavior unchanged.

## 1.0.0 - 2026-08-20

- First public HarmonyOS release.
- Adds shared transitions, image and video paging, loading placeholders, and
  drag dismissal.
