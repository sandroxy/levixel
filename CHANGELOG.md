# Changelog

## 1.2.0 - Unreleased

- Added a UniApp UTS 1.2.0 candidate for App-Android and App-iOS uni-app x Vapor on HBuilderX 5.24+, with Android API 23 and iOS 15 host minimums; VDOM, nvue, Web, mini apps, and HarmonyOS remain unsupported.
- Kept the canonical JavaScript API and shared Android/iOS UniApp runtimes, adding only FileSystemManager-backed preview ownership and a thin UTS local-path resolver.
- Reused the exact published 1.1.1 Android/iOS native artifacts through explicit native-release provenance; the legacy UniApp product and all other native products remain 1.1.1.
- Added classic/x UTS compiler checks, official uni-app x SDK typechecks, and an independent ZIP-consuming Vapor host; UniApp 1.2.0 remains unpublished until real-device acceptance completes.
- Normalized the `null` values generated for omitted optional UTS type properties at the UTS JavaScript boundary, while retaining canonical rejection of missing required fields, unknown fields, and empty strings.
- Added the first framework-independent Levixel Web package while preserving the accepted native interaction model and canonical JavaScript protocol.
- Added shared source transitions, image and video paging, fit/zoom/pan behavior, vertical dismissal, lifecycle restoration, accessibility, and reduced-motion handling for modern browsers.
- Added atomic preview-to-full-resolution image handoff and bounded touch source activation to prevent rapid-switch flashes and missed immediate reopens.
- Completed pre-release interaction acceptance on macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.
- Added deterministic npm packaging, SHA-256 sidecars, artifact-only browser verification, GitHub Release asset verification, and npm Trusted Publishing preparation.

## 1.1.1 - 2026-08-25

- Added the first DCloud Marketplace-ready UTS package for classic uni-app on Android and iOS while keeping the accepted legacy bridges and shared platform runtimes.
- Fixed iOS landscape previews opening above their fitted zoom level when their first layout occurred before valid view bounds were available.
- Fixed the duplicate loading-preview layer exposed by pinching during the iOS opening transition.
- Preserved the user's relative zoom level and visual center when an iOS loading preview hands off to the full-resolution image.
- Carried the accepted iOS core into the React Native and UniApp packages; Android and HarmonyOS native behavior remain unchanged in this coordinated version release.

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
