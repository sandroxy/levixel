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

The UTS package builds only the DCloud-independent shared runtimes and embeds the accepted native core artifacts. Compiler verification uses HBuilderX 5.07 by default; set `HBUILDERX_CONTENTS` when it is installed elsewhere. The generated ZIP must be installed unchanged in a classic uni-app consumer and hand-verified with a matching custom base, cloud package, or offline package on Android and iOS devices.

The accepted App native-plugin bridge remains available for existing and offline consumers. It is built separately because it requires the DCloud legacy SDK and is not a Marketplace upload candidate:

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
DCLOUD_IOS_SDK_ROOT=/absolute/path/to/DCloud-iOS-SDK \
  ./scripts/package-uniapp-legacy.sh
./scripts/verify-uniapp-legacy.sh
```

## Release Metadata

Validate versions, target declarations, notices, privacy metadata, and runtime identifiers:

```sh
./scripts/verify-release-metadata.sh
```

The release procedure and signing requirements are documented in [RELEASING.md](RELEASING.md).
