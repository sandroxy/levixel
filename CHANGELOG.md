# Changelog

## 1.4.0 - Unreleased

- Adds image and video long-press events and viewer-owned action drawers on native Android/iOS, React Native, Web, and UniApp, with explicit list/grid layouts, optional list icons, groups, and arbitrary business callbacks.
- Adds native, React Native, Web, and UniApp session events, media-load/error events, visible retry controls, and programmatic retry and close APIs.
- Preserves media identity and registered source corners during iOS transitions, retains asynchronous image-loading targets until completion, and safely finalizes Android viewers during host removal.
- Adds React Native viewer refs for opening, closing, and retrying without a mounted thumbnail; opening snapshots retain their action callbacks during list updates.
- Adds action drawers, session events, and retry to classic uni-app UTS/nativeplugin and uni-app x Vapor. Close resolves after dismissal; closing or opening newer media cancels pending source measurement and path resolution requests.
- Keeps Web drawer keyboard focus visible without shifting media, waits for drawer dismissal before action callbacks, and prevents video playback from resuming after a media-load callback closes the viewer.
- Fixes the React Native Swift new-architecture build flag so the iOS bridge uses the host's configured architecture.

## 1.3.0 - 2026-09-07

- Isolated the UniApp Android viewer in its own full-screen window, preventing the host list from shifting when opening or closing the viewer at the bottom of a page.
- Restored Web shared transitions for thumbnails scrolled into view by correcting document-root viewport clipping.
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
- Separated the HarmonyOS viewer from host-owned source UI through public
  viewer, source, and clipping-viewport components connected by an explicit
  controller; the ready-made gallery uses those same primitives, and hosts can
  open media by stable ID from their own controls.
- Preserved HarmonyOS thumbnail proportions through the opening transition,
  kept cropped source snapshots separate from original-image caching, and
  removed network waits from transition preparation. The full image fades over
  its preview without stretching the source crop.

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
