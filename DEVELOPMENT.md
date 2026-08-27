# Development

Levixel keeps every maintained implementation and adapter in this repository. Generated output belongs under `dist/` and is ignored by Git.

The `verify-*` scripts in this repository inspect package identity, metadata, legal notices, checksums, binary contents, and public contracts. Final interaction acceptance happens in separate artifact-only consumer hosts. Those hosts install the generated artifact and never import this source tree.

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

Android requires the repository Gradle wrapper. iOS requires Xcode command-line tools. HarmonyOS requires DevEco Studio tooling and `ohpm`; custom locations can be supplied through `DEVECO_STUDIO_CONTENTS`, `DEVECO_SDK_HOME`, `HVIGORW`, and `OHPM` where used by the packaging scripts.

## React Native

Build and inspect the immutable npm candidate:

```sh
./scripts/package-react-native.sh
./scripts/verify-react-native-package.sh
```

The tarball embeds the accepted Android AAR and iOS XCFramework. It must be tested as a tarball dependency in Android and iOS consumer hosts before publication.

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
./scripts/verify-uniapp-uts-compiler.sh
```

The UTS package builds only the DCloud-independent shared runtimes and embeds the accepted native core artifacts. Compiler verification uses HBuilderX 5.07 by default; set `HBUILDERX_CONTENTS` when it is installed elsewhere. The Marketplace ZIP root directly contains `package.json` and `utssdk/`; install those exact contents under `uni_modules/Sandrox-Levixel/` in a classic uni-app consumer, then hand-verify with a matching custom base, cloud package, or offline package on Android and iOS devices.

The accepted App native-plugin bridge remains available for existing and offline consumers. It is built separately because it requires the DCloud legacy SDK and is not a Marketplace upload candidate:

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
DCLOUD_IOS_SDK_ROOT=/absolute/path/to/DCloud-iOS-SDK \
  ./scripts/package-uniapp-legacy.sh
./scripts/verify-uniapp-legacy.sh
```

The legacy ZIP is a compatibility artifact, not a second UniApp implementation. It may be attached to a GitHub Release only after that exact ZIP has passed Android and iOS artifact-only smoke tests. The package must not embed or redistribute the DCloud Android/iOS SDK used to compile the bridge.

## Web

The framework-independent browser runtime is developed under `adapters/web`. It preserves the canonical JavaScript fields and event JSON but owns only browser-specific DOM geometry, media elements, input handling, accessibility, and lifecycle restoration. The accepted Android/iOS/UniApp implementations remain the product authority; the earlier H5 proof of concept is not a source dependency.

Install its locked development tooling, run the real-browser demo, and execute all checks with:

```sh
cd adapters/web
npm ci
npm run dev
npm run verify
```

The automated suite uses a system Chrome/Chromium binary rather than downloading a browser. Set `LEVIXEL_CHROME_PATH` when necessary. `./scripts/verify-web.sh` also validates the 1.2.0 package metadata, legal-file bytes, and npm payload allowlist. Manual interaction acceptance covers macOS Chrome, macOS Safari, Android Chrome, and iOS Safari.

Build and verify the exact npm candidate from a clean release commit:

```sh
./scripts/package-web.sh
./scripts/verify-web-package.sh
```

The package command writes `dist/web/levixel-web-<version>.tgz` and its SHA-256 sidecar, then installs that exact tarball in a temporary consumer for SSR import, public type, and real-Chrome interaction verification. It refuses to overwrite different candidate bytes silently. Use `--allow-dirty` only for a local pipeline rehearsal and `--replace` only after deliberately rejecting the previous local candidate.

Web uses an explicit target version in `plugin.yaml` while it is staged independently from the already published 1.1.1 products. Other targets continue to inherit the manifest version and their existing build behavior is unchanged.

## Release Metadata

Validate versions, target declarations, notices, privacy metadata, and runtime identifiers:

```sh
./scripts/verify-release-metadata.sh
```

The release procedure and signing requirements are documented in [RELEASING.md](RELEASING.md).
