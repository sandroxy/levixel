# Levixel

Levixel is a shared-transition image and video viewer for native, React Native,
and UniApp applications.

This directory is the only source of truth. Shared test hosts consume packaged
artifacts from `dist/`; they never compile plugin source directly. A release
publishes the same bytes that those hosts verified.

## Native Release Candidate

Build all three native artifacts once, verify them in their artifact-only test
hosts, and generate the release manifest:

```sh
./scripts/prepare-native-release.sh
```

Use `--allow-dirty --allow-unsigned` only while developing the release
pipeline. The formal candidate requires a clean worktree and Android signing
credentials.

See [RELEASING.md](RELEASING.md) for ecosystem publication steps and external
account prerequisites.

## Android

Build the AAR and its Maven repository:

```sh
./scripts/package-native-android.sh
```

Verify the Maven coordinate and its transitive metadata in the Android host:

```sh
./scripts/verify-native-android.sh
```

Public coordinate: `io.gitee.sandrox:levixel:1.1.0`.

The current Android core intentionally retains the already validated
`PhotoView 2.3.0` implementation. Consumers must make JitPack available until
that internal dependency is migrated in a separately validated change.

## iOS

Build the release XCFramework ZIP and checksum-pinned Swift Package manifest:

```sh
./scripts/package-native-ios.sh
```

Verify the binary, privacy manifest, legal notices, Swift Package checksum, and
the iOS consumer host:

```sh
./scripts/verify-native-ios.sh
```

The generated Swift Package repository contents are in
`dist/native-ios/swift-package`.

Public package repository: `https://github.com/sandroxy/levixel`.

## HarmonyOS

Build and verify the OHPM-ready HAR:

```sh
./scripts/package-native-harmonyos.sh
./scripts/verify-native-harmonyos.sh
```

On macOS the scripts discover a standard DevEco Studio installation. Set
`DEVECO_STUDIO_CONTENTS`, or set `DEVECO_SDK_HOME`, `HVIGORW`, and `OHPM`
individually, for a custom installation.

Public package: `@sandrox/levixel@1.1.0`.

## React Native

The React Native adapter is a separate npm product that embeds the already
packaged Android and iOS cores:

```sh
./scripts/package-react-native.sh
./scripts/verify-react-native.sh android
./scripts/verify-react-native.sh ios
```

Inspect the immutable npm tarball without rebuilding it:

```sh
./scripts/verify-react-native-package.sh
```

After the exact tarball passes Android and iOS hand verification, follow the
tagged publication procedure in [RELEASING.md](RELEASING.md). Do not rebuild
between hand verification and npm publication.

## UniApp

The UniApp adapter combines thin Android/iOS bridges, the canonical native
artifacts, and a strict JavaScript SDK into one DCloud native-plugin package:

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
  ./scripts/package-uniapp.sh
./scripts/verify-uniapp.sh
```

The verifier stages the exact ZIP in `uniapp-plugins-test/nativeplugins/` for
HBuilderX custom-base or offline-package validation. See
[adapters/uniapp/README.md](adapters/uniapp/README.md) for the public SDK and
source-geometry contract.

## License And Provenance

Levixel is independently maintained and substantially rewritten, but the
current implementation retains derivative code lineage. See
[PROVENANCE.md](PROVENANCE.md), [LICENSE](LICENSE), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
