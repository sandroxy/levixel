# Release Process

## Artifact Graph

Levixel uses one canonical version with ecosystem-specific products:

| Platform | Public product | Canonical artifact |
| --- | --- | --- |
| Android | `io.gitee.sandrox:levixel` | Maven publication containing the AAR, POM, Gradle metadata, sources, and Javadocs |
| iOS | `Levixel` | Checksum-pinned Swift Package that downloads the XCFramework ZIP |
| HarmonyOS | `@sandrox/levixel` | OHPM HAR |
| React Native | `@sandrox/levixel` | npm tarball containing thin Expo Modules bridges and the accepted Android/iOS native artifacts |
| UniApp | `Sandrox-Levixel` | DCloud UTS-plugin ZIP containing thin Android/iOS bridges, shared UniApp runtimes, accepted native artifacts, and the canonical JavaScript SDK |

The raw Android AAR and HarmonyOS HAR are available for offline integration. Maven Central and OHPM remain the preferred channels because they carry package identity and version metadata.

## Immutable Candidate Rule

1. Start from the release commit with a clean worktree.
2. Build each candidate once.
3. Run the artifact self-checks in this repository.
4. Install those exact files in artifact-only consumer hosts. Consumer hosts must not compile or copy Levixel source.
5. Complete the required Android, iOS, HarmonyOS, React Native, and UniApp hand verification for the targets being released.
6. Publish only the accepted files and their recorded checksums. Never rebuild after acceptance or reuse a public version for different bytes.

Prepare the complete native candidate and release manifest with:

```sh
./scripts/prepare-native-release.sh
```

For a local pipeline rehearsal only:

```sh
./scripts/prepare-native-release.sh --allow-dirty --allow-unsigned
```

The formal candidate requires a clean worktree and Maven signing credentials.

## Android / Maven Central

Supply the ASCII-armored private key and passphrase without committing them:

```sh
export LEVIXEL_SIGNING_KEY="$(cat private-key.asc)"
export LEVIXEL_SIGNING_PASSWORD="..."
```

The canonical release-signing key fingerprint is:

```text
76C15313941EDE0281DB835E36B1957F0CEFA6B3
```

It signs `1.1.0` and later releases. The immutable `1.0.0` artifacts remain signed by retired key `B7D159C354B9EF7318D3544200BE5C219A0DD690`; retain its public key for historical verification but do not use it for new releases.

After the exact Maven candidate passes consumer verification, create the Central Portal bundle without rebuilding:

```sh
./scripts/prepare-maven-central-bundle.sh
```

Upload `dist/native-android/levixel-<version>-maven-central.zip` in user-managed mode and publish only after portal validation. Attach the accepted AAR and SHA-256 file to the matching GitHub Release as an offline mirror.

The retained `PhotoView 2.3.0` dependency is hosted by JitPack. Replacing or vendoring it requires a separate gesture regression pass and must not be folded into release packaging.

## iOS / Swift Package Manager

1. Create the source tag `levixel-v<version>` on the canonical source commit.
2. Build and verify `dist/native-ios/levixel-<version>.xcframework.zip` once.
3. Attach that exact ZIP to the matching GitHub Release.
4. Update the root `Package.swift` to the release URL and computed checksum.
5. Tag the public package repository with `<version>`.
6. Resolve the tag in a clean iOS consumer and run the final smoke test.

The default binary URL is the GitHub Release asset. Override it only when the permanent binary host changes:

```sh
LEVIXEL_IOS_BINARY_URL=https://example.com/levixel-<version>.xcframework.zip \
  ./scripts/package-native-ios.sh
```

If device acceptance was completed on a one-time XCFramework candidate before the release-metadata commit, promote those exact accepted bytes instead of rebuilding them:

```sh
LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_ZIP=/absolute/path/to/accepted.xcframework.zip \
LEVIXEL_IOS_ACCEPTED_XCFRAMEWORK_SHA256=<accepted-sha256> \
  ./scripts/prepare-native-release.sh
```

The packaging script verifies the supplied SHA-256, embedded framework version, slices, privacy manifest, and legal notices before copying the ZIP byte-for-byte to its canonical release filename. Use this path only when the release commit changes metadata or packaging and the accepted candidate was built from the same native source; record both the source commit and accepted checksum in the release review.

## HarmonyOS / OHPM

1. Confirm the `@sandrox` scope and publisher access.
2. Build and inspect `dist/native-harmonyos/levixel-<version>.har` once.
3. Install that HAR in an artifact-only consumer and complete the HarmonyOS hand verification.
4. Publish the accepted HAR to OHPM without rebuilding.
5. Install the public package in a clean consumer and run a smoke test.
6. Run the `Mirror HarmonyOS HAR` workflow for the approved version. It verifies the OHPM SHA-512 integrity and package metadata, mirrors the exact HAR and SHA-256 file to the matching GitHub Release, and reconciles the HAR entry in the native release manifest.

## React Native / npm

The npm product embeds the native artifacts recorded in `dist/native-release/levixel-native-<version>.json`. It must not compile copied viewer source or resolve an unpinned native core during consumer installation.

1. Package and inspect the npm candidate once:

   ```sh
   ./scripts/package-react-native.sh
   ./scripts/verify-react-native-package.sh
   ```

2. Install the exact tarball in artifact-only Android and iOS React Native consumers. Verify transition, paging, zoom, pan, video, loading, retry, cached reopen, and return behavior.
3. Create the canonical source tag on the accepted commit:

   ```sh
   git tag -a levixel-react-native-v<version> -m "Levixel React Native <version>"
   ```

4. Attach the accepted files to the matching public GitHub Release without repacking:

   - `dist/react-native/levixel-react-native-<version>.tgz`
   - `dist/react-native/levixel-react-native-<version>.tgz.sha256`
   - `dist/native-release/levixel-native-<version>.json`

5. Run the public `Publish npm` workflow. npm Trusted Publishing must target:

   - Provider: GitHub Actions
   - Organization or user: `sandroxy`
   - Repository: `levixel`
   - Workflow filename: `publish-npm.yml`
   - Allowed action: `npm publish`

The workflow downloads and verifies the accepted GitHub Release assets and publishes through OIDC without a long-lived npm token. Direct local publication remains an authenticated fallback:

```sh
./scripts/publish-react-native.sh --dry-run
./scripts/publish-react-native.sh --publish
```

## UniApp / DCloud UTS Plugin

The Marketplace product supports classic uni-app Vue pages on Android/iOS. It embeds the accepted Android AAR and iOS device framework, while UTS owns only context lookup, JSON conversion, and callback transport. DOM geometry and bounded preview warmup stay in the canonical JavaScript SDK; platform behavior stays in the shared UniApp runtimes. Do not claim uni-app x support for this release.

The manifest source root is `uni_modules/Sandrox-Levixel`; shared runtimes and the legacy bridges remain in `adapters/uniapp`. `uni_modules/Sandrox-Levixel/js_sdk/canonical.js` is a checked-in generated mirror of `adapters/uniapp/js_sdk/index.js`. Regenerate it with `./scripts/sync-uniapp-canonical-js.sh` whenever the canonical SDK changes, then review the diff. Never hand-edit the generated mirror or rely on packaging to repair drift.

1. Build the candidate once:

   ```sh
   ./scripts/package-uniapp.sh
   ```

   Packaging fails before building if the generated canonical SDK or the declared source root has drifted.

2. Inspect the exact bytes and compile both generated native bridges with HBuilderX 5.07:

   ```sh
   ./scripts/verify-uniapp.sh
   ./scripts/verify-uniapp-uts-compiler.sh
   ```

3. Install `dist/uniapp/levixel-uniapp-<version>.zip` unchanged under `uni_modules/` in the artifact-only consumer. Verify transition, paging, zoom, pan, video, loading, retry, cached reopen, close timing, source alignment, and WebView return behavior on Android and iOS devices.
4. Complete the remaining contact, screenshot, and device fields in `dist/uniapp/levixel-uniapp-<version>-marketplace.md`.
5. Upload the accepted ZIP to the DCloud Marketplace without rebuilding. Publish only after the ZIP checksum still matches the accepted candidate.

The separately generated `levixel-uniapp-legacy-<version>.zip` remains available for existing App native-plugin/offline consumers. It is not the Marketplace artifact and must never replace the UTS ZIP in this release flow.

## Provenance

`THIRD_PARTY_NOTICES.md` is mandatory release content. Levixel branding does not require Galeria names in runtime APIs, but the MIT notices remain attached to every artifact that carries derivative code. See [PROVENANCE.md](PROVENANCE.md) for the audited lineage and classification.
