# Development

This document is for Levixel maintainers and contributors. Application
developers integrating a published package should start with [README.md](README.md)
or [README-EN.md](README-EN.md).

Levixel keeps every maintained implementation and adapter in this repository. Generated output belongs under `dist/` and is ignored by Git.

The `verify-*` scripts in this repository inspect package identity, metadata, legal notices, checksums, binary contents, and public contracts. Final interaction acceptance happens in separate artifact-only consumer hosts. Those hosts install the generated artifact and never import this source tree.

Ordinary source tests do not require a version bump. Artifact-consumer testing
does: before building a release candidate, set `plugin.yaml` and every package
manifest to an unused target version and commit that release intent. The latest
published stable version remains identified by its public tag and Release; it
is not inferred from the development branch's version. A target version can
have multiple rejected builds, but each build receives a content-derived
candidate id and only an accepted candidate may be published.

## Native Cores

Build and inspect all native artifacts:

```sh
./scripts/package-native-all.sh
./scripts/verify-native-all.sh
```

Platform-specific commands are also available:

```sh
./scripts/package-native-android.sh
./scripts/verify-native-android.sh

./scripts/package-native-ios.sh
./scripts/verify-native-ios.sh

./scripts/package-native-harmonyos.sh
./scripts/verify-native-harmonyos.sh
```

Verification commands are read-only: they inspect artifacts that already exist
and never rebuild them implicitly. `verify-native-ios.sh` additionally runs the
current iOS source tests and confirms that the packaged XCFramework exposes the
API required by the current adapters. Use
`./scripts/verify-native-ios.sh --artifact-only` only when auditing an immutable
historical XCFramework independently of newer source.

Android requires the repository Gradle wrapper. iOS requires Xcode command-line tools. HarmonyOS requires DevEco Studio tooling and `ohpm`; custom locations can be supplied through `DEVECO_STUDIO_CONTENTS`, `DEVECO_SDK_HOME`, `HVIGORW`, and `OHPM` where used by the packaging scripts.

HarmonyOS consumer coverage must update the host `items` while a viewer is
open. The active viewer must retain its immutable opening snapshot, while its
return transition resolves the latest visible grid source by stable media id
and fades when that source is no longer mounted.

The iOS source-only regression entry point is:

```sh
./scripts/test-native-ios-source.sh
```

## React Native

Build and inspect the immutable npm candidate:

```sh
./scripts/verify-react-native-contract.sh
./scripts/package-react-native.sh
./scripts/verify-react-native-package.sh
```

The tarball embeds the accepted Android AAR and iOS XCFramework. It must be tested as a tarball dependency in Android and iOS consumer hosts before publication.
Contract verification requires Node.js 22.6 or newer. It exercises the shared
request validator only; TypeScript component compilation and Android/iOS bridge
integration remain artifact-consumer checks. Packaging also type-checks the
adapter-facing iOS API against the exact embedded XCFramework on macOS; the same
API surface is inspected portably when a release asset is verified on Linux.
React Native packaging verifies its temporary candidate before installing it in
`dist/` and refuses to replace different same-version bytes unless `--replace`
is explicitly supplied for a rejected, still-untagged local candidate.
Artifact-consumer coverage must render sources by `itemId`, then prepend,
append, reorder, and recycle mounted cells before reopening. TypeScript
component compilation is required in addition to the pure contract test.

## UniApp

The public UTS plugin source root is `uni_modules/Sandrox-Levixel`; the DCloud-independent Android/iOS runtimes and the legacy bridges remain under `adapters/uniapp`. `adapters/uniapp/js_sdk/index.js` is the only hand-maintained canonical JavaScript SDK. After changing it, regenerate the checked-in plugin copy and review the resulting diff:

```sh
./scripts/sync-uniapp-canonical-js.sh
```

Do not edit `uni_modules/Sandrox-Levixel/js_sdk/canonical.js` directly. Packaging and release verification use `--check` and fail on any byte-level drift instead of overwriting the generated file.

Build and inspect the DCloud Marketplace UTS candidate:

```sh
./scripts/package-uniapp.sh
./scripts/verify-uniapp.sh
DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT=/absolute/path/to/Android-uni-app-x-SDK \
DCLOUD_UNIAPP_X_IOS_SDK_ROOT=/absolute/path/to/UniAppX-iOS \
  ./scripts/verify-uniapp-uts-compiler.sh
```

The package command requires a clean worktree for a formal candidate. It builds into temporary storage first and refuses to overwrite a different same-version ZIP, checksum sidecar, or Marketplace material. Use `--allow-dirty` only for a local pipeline rehearsal; use `--replace` only after deliberately rejecting the previous local candidate, then repeat every artifact-only and device acceptance step.

The UTS package builds only the DCloud-independent shared runtimes and embeds the accepted native core artifacts. Compiler verification requires the HBuilderX minimum declared in `uni_modules/Sandrox-Levixel/package.json` or newer. It generates classic/x Kotlin and Swift, then typechecks the x output against the extracted official SDKs; set `HBUILDERX_CONTENTS` when HBuilderX is installed elsewhere. No SDK absolute path is committed.

The Marketplace ZIP root directly contains `package.json` and `utssdk/`. Install those exact contents under `uni_modules/Sandrox-Levixel/` in separate classic and uni-app x Vapor consumers. Classic may use a matching custom base, cloud package, or offline package. Android/iOS Vapor has no public offline SDK, so x App packaging and device acceptance must use HBuilderX standard run, a matching custom base, or cloud packaging. **Only the classic and uni-app x Vapor Android/iOS targets declared in the plugin metadata are supported; VDOM, nvue, HarmonyOS, mini apps, and Web are not supported by the UniApp package.** Every release candidate must pass both classic/x Android/iOS device matrices against its recorded SHA-256 before publication.

The consumer matrix must include a prepend-style chat list, an append-style
paginated list, a sparse virtualized source set, out-of-order bindings, and
component-scoped selector queries. The active viewer consumes the loaded item
snapshot from one open call; host pagination inside an already open viewer is
outside the public contract.

The accepted App native-plugin bridge remains available for existing and offline consumers. It is built separately because it requires the DCloud legacy SDK and is not a Marketplace upload candidate:

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
DCLOUD_IOS_SDK_ROOT=/absolute/path/to/DCloud-iOS-SDK \
  ./scripts/package-uniapp-legacy.sh
./scripts/verify-uniapp-legacy.sh
```

The legacy ZIP is a compatibility artifact, not a second UniApp implementation. It may be attached to a GitHub Release only after that exact ZIP has passed Android and iOS artifact-only smoke tests. The package must not embed or redistribute the DCloud Android/iOS SDK used to compile the bridge.

## Web

The framework-independent browser runtime is developed under `adapters/web`. It preserves the shared JavaScript fields and event JSON but owns only browser-specific DOM geometry, media elements, input handling, accessibility, and lifecycle restoration. The current Android/iOS/UniApp behavior is its interaction reference; the earlier H5 proof of concept is not a source dependency.

Install its locked development tooling, run the real-browser demo, and execute all checks with:

```sh
cd adapters/web
npm ci
npm run dev
npm run verify
```

The automated suite uses a system Chrome/Chromium binary rather than downloading a browser. Set `LEVIXEL_CHROME_PATH` when necessary. `./scripts/verify-web.sh` also validates the declared target package metadata, legal-file bytes, and npm payload allowlist. Manual interaction acceptance covers macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.
It must also exercise prepended and appended media, sparse mounted DOM sources,
out-of-order bindings, source removal before dismissal, and a connected DOM
node recycled to a different stable identity.

Build and verify the exact npm candidate from a clean release commit:

```sh
./scripts/package-web.sh
./scripts/verify-web-package.sh
```

The package command writes `dist/web/levixel-web-<version>.tgz` and its SHA-256 sidecar, then installs that exact tarball in a temporary consumer for SSR import, public type, and real-Chrome interaction verification. It refuses to overwrite different candidate bytes silently. Use `--allow-dirty` only for a local pipeline rehearsal and `--replace` only after deliberately rejecting the previous local candidate.

`plugin.yaml` is the only source of truth for the root version, independently staged target versions, artifact paths, and UniApp native provenance. Native Android/iOS/HarmonyOS, React Native, and the UniApp legacy target normally inherit the root version; Web and UniApp UTS may declare explicit target versions. UniApp packaging must resolve `native-release-version` from that manifest and embed the exact AAR/XCFramework recorded by the corresponding native release manifest. Do not copy a current release number into development prose.

`contract/open.schema.json` declares cross-item media identity with the custom
`x-levixel-uniqueBy` annotation. JSON Schema 2020-12 does not evaluate that rule
on its own, so every runtime must also reject duplicate IDs and retain a behavior
test for that boundary.

## Release Metadata

Validate versions, target declarations, notices, privacy metadata, and runtime identifiers:

```sh
./scripts/verify-documentation.sh
./scripts/verify-release-metadata.sh
```

`verify-documentation.sh` is safe during ordinary development.
`verify-release-metadata.sh` belongs to release preparation after the unused
target version and dated changelog entries are committed; passing it alone does
not mean that any concrete bytes were accepted. Immediately before creating
formal artifacts, run `./scripts/verify-release-readiness.sh`. It fails closed
unless the root version is unused locally and on `origin`, the release entry is
first in each coordinated changelog, and all release metadata is internally
consistent.

The root README files describe the latest stable binaries. Keep unreleased API
examples in `CHANGELOG.md` or maintainer documentation until a compatible
artifact is accepted and its new version becomes the stable installation target.

The release procedure and signing requirements are documented in [RELEASING.md](RELEASING.md).
