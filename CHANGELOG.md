# Changelog

## 1.3.0 - 2026-08-31

- Resolved legacy UniApp iOS source geometry against the visible page viewport, restoring shared transitions when the bridge root view differs from the rendered page.
- Made UniApp return transitions follow the source rectangle's positive-area intersection with the effective page viewport: partially visible sources remain shared-transition targets, while fully offscreen sources fade safely.
- Restored UniApp iOS return transitions by keeping synthetic-anchor hosts registry-visible while hiding only the generated anchor views.
- Made UniApp warmup dimension-only, bounded click-time preview waiting, and constrained managed previews by per-file size, total bytes, entry count, and idle lifetime.
- Rebound React Native iOS Fabric source views after component mounting and reuse so recycled list cells remain valid open and return-transition targets.
- Made a clipped, uniform numeric `Levixel.Source` radius authoritative for React Native Android/iOS transition geometry, preventing square-to-rounded flashes across image renderers and recycled source cells.
- Made Android shared-element names collision-safe across galleries and between stable item identities and legacy indices.
- Rejected detached, hidden, and fully clipped iOS and Web source views so unavailable transition targets fall back cleanly instead of animating from stale geometry.
- Prevented Android video posters from flashing after progress-bar seeks by making the decoded-frame handoff idempotent across renderer callbacks, page reactivation, and cancelled dismiss gestures.
- Accepted empty asynchronous `items` state in the React Native provider while keeping every rendered source index strict, and removed stale Android/iOS source bindings when media becomes empty or the wrapped image changes.
- Added stable item identities to the iOS native data source and transition registry, then carried them through the React Native and UniApp iOS bridges so reordered lists return to the correct source.
- Required non-empty, unique stable IDs wherever identity-backed return is used: native Android and HarmonyOS sessions, native iOS identified data sources, and React Native, UniApp, and Web adapter contracts.
- Ensured the iOS image viewport completes its first nested layout before calculating fit scale, including pages configured before valid bounds exist.
- Added stable ID entry points for dynamic React Native, UniApp, and Web lists;
  sparse mounted sources now map deterministically across prepend, append,
  reorder, pagination, virtualization, and UniApp component query scopes
  without weakening native contracts.
- Added stable media ids to adapter index-change/open-result payloads so host
  list updates cannot make a session index identify the wrong item.
- Isolated each open HarmonyOS viewer from later host list updates while still
  resolving its return target against the latest visible source by stable ID.

## 1.2.0 - 2026-08-28

- Added UniApp UTS support for App-Android and App-iOS uni-app x Vapor on HBuilderX 5.24+, with Android API 23 and iOS 15 host minimums; VDOM, nvue, Web, mini apps, and HarmonyOS remain unsupported.
- Kept the public JavaScript API and shared Android/iOS UniApp runtimes while improving local preview ownership and path conversion for uni-app x.
- Coordinated Android, iOS, HarmonyOS, React Native, UTS, and the optional UniApp legacy bridge at 1.2.0; native viewer behavior remains unchanged from the 1.1.1 cores.
- Normalized the `null` values generated for omitted optional UTS type properties while retaining strict rejection of missing required fields, unknown fields, and empty strings.
- Matched Vapor source CSS and native transition radii in `px`, preventing a brief square-corner source flash during iOS open and close transitions.
- Added the first framework-independent Levixel Web package with shared source transitions, image and video paging, fit/zoom/pan behavior, vertical dismissal, lifecycle restoration, accessibility, and reduced-motion handling.
- Added atomic preview-to-full-resolution image handoff and bounded touch source activation to prevent rapid-switch flashes and missed immediate reopens.
- Added support for macOS Chrome, macOS Safari, Android Chrome, and iOS Safari, with npm distribution and downloadable SHA-256 sidecars.

## 1.1.1 - 2026-08-25

- Added the first DCloud Marketplace-ready UTS package for classic uni-app on Android and iOS while keeping the legacy bridges and shared platform runtimes.
- Fixed iOS landscape previews opening above their fitted zoom level when their first layout occurred before valid view bounds were available.
- Fixed the duplicate loading-preview layer exposed by pinching during the iOS opening transition.
- Preserved the user's relative zoom level and visual center when an iOS loading preview hands off to the full-resolution image.
- Carried the updated iOS core into the React Native and UniApp packages; Android and HarmonyOS native behavior remain unchanged in this coordinated version release.

## 1.1.0 - 2026-08-24

- Improved shared-transition behavior for loaded, loading, cached, and off-screen media.
- Fixed iOS loading-state layout and repeated-loading regressions.
- Stabilized HarmonyOS image presentation and video control-bar layout.
- Added UniApp adapters for Android and iOS with consistent source geometry, bounded selected-preview handoff, strict contract validation, and identity-safe preview storage.
- Preserved the native and React Native interaction model while keeping UniApp HTML sources visible by default to avoid WebView handoff flashes.
- Exposed explicit iOS viewer sessions so framework adapters can close and clean up presentations without copying the native viewer core.
- Rotated the Maven Central release-signing key while retaining the `1.0.0` public key for historical verification.
- Moved the public source, release assets, Swift Package, and npm trusted-publishing workflow to GitHub.

## 1.0.0 - 2026-08-20

- Published the native Android artifact to Maven Central.
- Added the binary iOS Swift Package for device and simulator builds.
- Included shared image and video transitions, paging, zoom, pan, drag-to-dismiss, loading placeholders, and media-aware return transitions.
- Included privacy metadata, source and Javadoc artifacts, checksums, signatures, and complete third-party notices.
