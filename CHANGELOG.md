# Changelog

## 1.1.0 - 2026-08-20

- Adds the artifact-only UniApp adapter for Android and iOS with canonical
  source geometry, bounded selected-preview handoff, structured events, and
  strict contract validation.
- Exposes explicit iOS viewer sessions so framework adapters can close and
  clean up presentations without copying the native viewer core.
- Preserves the validated native and React Native interaction model while
  keeping UniApp HTML sources visible by default to avoid WebView handoff
  flashes.
- Resolves Android UniApp DOM geometry directly in the native viewer instead
  of synthesizing hidden source views or starting a second image-loading path.
- Stores UniApp remote previews in identity-safe managed files, resolves DCloud
  virtual paths before native handoff, and lets the selected item bypass the
  serialized background queue without reintroducing runtime temp-path reuse.
  Loaded sources receive a bounded foreground wait before fallback; LRU
  eviction and stale-file cleanup remain in place.

## 1.0.0 - 2026-08-20

- First public native release of Levixel for Android, iOS, and HarmonyOS.
- Includes shared transitions, image and video paging, drag dismissal, and
  platform-supported zoom and pan interactions.
- Establishes artifact-only verification hosts and release provenance records.
