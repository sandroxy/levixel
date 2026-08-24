# Changelog

## 1.1.0 - 2026-08-24

- Improved shared-transition behavior for loaded, loading, cached, and off-screen media.
- Fixed iOS loading-state layout and repeated-loading regressions.
- Stabilized HarmonyOS image presentation and video control-bar layout.
- Added artifact-only UniApp adapters for Android and iOS with canonical source geometry, bounded selected-preview handoff, strict contract validation, and identity-safe preview storage.
- Preserved the validated native and React Native interaction model while keeping UniApp HTML sources visible by default to avoid WebView handoff flashes.
- Exposed explicit iOS viewer sessions so framework adapters can close and clean up presentations without copying the native viewer core.
- Rotated the Maven Central release-signing key while retaining the `1.0.0` public key for historical verification.
- Moved the canonical public source, release assets, Swift Package, and npm trusted-publishing workflow to GitHub.

## 1.0.0 - 2026-08-20

- Published the native Android artifact to Maven Central.
- Added the binary iOS Swift Package for device and simulator builds.
- Included shared image and video transitions, paging, zoom, pan, drag-to-dismiss, loading placeholders, and media-aware return transitions.
- Included privacy metadata, source and Javadoc artifacts, checksums, signatures, and complete third-party notices.
