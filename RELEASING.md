# Release Process

This document is for Levixel maintainers. Package installation and application
integration are documented in [README.md](README.md) and
[README-EN.md](README-EN.md).

## Artifact Graph

Levixel records every ecosystem product and its immutable artifact. Targets normally inherit the canonical manifest version; an independently staged target may explicitly declare its product version without relabeling already published artifacts on other platforms.

## Release state and candidate identity

The version in `plugin.yaml` is the current release target, not a declaration
that the version is already public. Published stability comes from the
immutable tag and public Release. Concrete local bytes are identified by the
candidate manifest, never by the version alone:

- platform `dist/` directories are mutable build workspaces;
- `dist/rehearsals/<version>/<candidate-id>/` contains dirty or unsigned local
  pipeline snapshots and is never publishable;
- `dist/candidates/<version>/<candidate-id>/` contains a clean, signed,
  immutable full artifact set and `candidate.json`;
- the candidate id binds the product version, source commit, and artifact-set
  SHA-256. Rebuilding a rejected still-unpublished version produces a new id;
  published versions can never be rebuilt or replaced.

After all coordinated artifacts have passed their repository self-checks,
snapshot them once with:

```sh
./scripts/prepare-release-candidate.sh
```

The separate `integrated-plugins` repository must consume the printed absolute
manifest path with `--candidate`; its default mode always uses public stable
artifacts from `verification/stable-lock.json` and never a sibling checkout.

| Platform | Public product | Canonical artifact |
| --- | --- | --- |
| Android | `io.gitee.sandrox:levixel` | Maven publication containing the AAR, POM, Gradle metadata, sources, and Javadocs |
| iOS | `Levixel` | Checksum-pinned Swift Package that downloads the XCFramework ZIP |
| HarmonyOS | `@sandrox/levixel` | OHPM HAR |
| React Native | `@sandrox/levixel` | npm tarball containing thin Expo Modules bridges and the accepted Android/iOS native artifacts |
| UniApp | `Sandrox-Levixel` | DCloud UTS-plugin ZIP containing thin Android/iOS bridges, shared UniApp runtimes, accepted native artifacts, and the canonical JavaScript SDK |
| Web | `@sandrox/levixel-web` | ESM npm tarball containing the framework-independent browser runtime and public type declarations |

The raw Android AAR and HarmonyOS HAR are available for offline integration. Maven Central and OHPM remain the preferred channels because they carry package identity and version metadata.

Product publication workflows are intentionally manual. Publishing a GitHub Release must not cause unrelated products that remain on an earlier target version to rebuild, mirror, or publish automatically.

## Immutable Candidate Rule

1. Start from the release commit with a clean worktree.
2. Build each candidate once.
3. Run the artifact self-checks in this repository.
4. Install those exact files in artifact-only consumer hosts. Consumer hosts must not compile or copy Levixel source.
5. Complete the required Android, iOS, HarmonyOS, React Native, UniApp, and Web interaction verification for the targets being released.
6. Record an `accepted` receipt in `integrated-plugins` for the exact candidate
   id and artifact-set digest.
7. Create the canonical annotated tag on the candidate source commit, then run
   the local publication gate before uploading any file:

   ```sh
   ./scripts/verify-publish-candidate.rb \
     --candidate /absolute/path/to/candidate.json \
     --acceptance /absolute/path/to/accepted-receipt.json
   ```

   Publish only the paths printed by the gate.
8. Publish only the accepted files and their recorded checksums. Never rebuild after acceptance or reuse a public version for different bytes.

Every artifact-producing script rejects a version that already has a local or
canonical `origin` tag before invoking a compiler or touching its release path.
There is no overwrite mode for a tagged version. Additive public API changes use
a new SemVer minor version; fixes that do not add public API use a patch version.

Prepare the complete native candidate and release manifest with:

```sh
./scripts/prepare-native-release.sh
```

For a local pipeline rehearsal only:

```sh
./scripts/prepare-native-release.sh --allow-dirty --allow-unsigned
```

The formal candidate requires a clean worktree and Maven signing credentials.

## Documentation Boundary

User-facing landing pages and platform guides describe stable capabilities, installation, and compatibility without copying the current Levixel release number into prose. Exact versions belong in `plugin.yaml`, package manifests, changelogs, immutable release notes, artifact filenames, and generated publication material.

Before creating a tag, run:

```sh
./scripts/verify-documentation.sh
./scripts/verify-release-metadata.sh
./scripts/verify-release-readiness.sh
```

`verify-documentation.sh` remains usable during the `Unreleased` source phase.
After assigning the unused target version and dating its coordinated changelog
entries, run `verify-release-metadata.sh`. Only
`verify-release-readiness.sh` is the formal candidate gate: it requires an
unused stable version, checks `origin` directly,
and requires the current version and date to be the first coordinated changelog
entries.

Post-release documentation corrections are normal commits on the default branch. They must not move an already published tag, replace an accepted release asset, or rebuild a public version. A registry README embedded in an immutable artifact remains the historical copy shipped with that artifact; editable landing pages may link to the current guide.

The root README files are stable-installation guides. Do not show an unreleased
initializer, method, or option there while the latest tagged binary lacks it;
record it under `Unreleased` until the compatible artifact is accepted.

## Canonical Git Tag

Each coordinated Levixel release uses exactly one annotated Git tag named
`<version>` and one matching GitHub Release. Android, iOS, HarmonyOS, React
Native, UniApp, and Web all refer to that shared release identity; do not
create product-prefixed tags such as `levixel-v<version>` or
`levixel-react-native-v<version>`.

```sh
git tag -a "<version>" -m "Levixel <version>"
git push origin "<version>"
```

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

The retained PhotoView dependency is hosted by JitPack. Replacing or vendoring it requires a separate gesture regression pass and must not be folded into release packaging.

## iOS / Swift Package Manager

1. Build and verify `dist/native-ios/levixel-<version>.xcframework.zip` once.
2. Update the root `Package.swift` to the release URL and computed checksum.
3. Create the canonical `<version>` tag on the release commit.
4. Attach the accepted ZIP to the matching GitHub Release without rebuilding.
5. Resolve the tag in a clean iOS consumer and run the final smoke test.

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

Publish from an interactive terminal so OHPM can request the passphrase for an
encrypted private key. The following proxy-free command is the verified release
path for the public OHPM registry:

```sh
LEVIXEL_VERSION="<version>"
LEVIXEL_OHPM_PUBLISH_ID="<publish-id>"
LEVIXEL_OHPM_KEY_PATH="/absolute/path/to/private-key"
LEVIXEL_OHPM_BIN="/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm"

env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  -u http_proxy -u https_proxy -u all_proxy \
  NO_PROXY=ohpm.openharmony.cn \
  no_proxy=ohpm.openharmony.cn \
  "${LEVIXEL_OHPM_BIN}" publish \
  "dist/native-harmonyos/levixel-${LEVIXEL_VERSION}.har" \
  --publish_registry https://ohpm.openharmony.cn/ohpm/ \
  --publish_id "${LEVIXEL_OHPM_PUBLISH_ID}" \
  --key_path "${LEVIXEL_OHPM_KEY_PATH}"
```

Do not pass `--tag latest`; OHPM rejects `latest` as an explicit custom tag and
maintains the default tag itself. A successful upload prints the package name and
version, then reports that the submission is under review. Track that review at
<https://ohpm.openharmony.cn/#/cn/personalCenter/package>. Never paste the
private key or its passphrase into release logs, commits, or chat.

## React Native / npm

The npm product embeds the native artifacts recorded in `dist/native-release/levixel-native-<version>.json`. It must not compile copied viewer source or resolve an unpinned native core during consumer installation.

1. Package and inspect the npm candidate once:

   ```sh
   ./scripts/package-react-native.sh
   ./scripts/verify-react-native-package.sh
   ```

   The package command requires a clean worktree and installs a candidate only
   after its tarball, sidecar, native manifest, embedded binaries, source bytes,
   and adapter-facing iOS API pass verification. `--allow-dirty` is a local
   rehearsal only. `--replace` may replace a rejected untagged local candidate;
   the version guard cannot be bypassed after a tag exists.

2. Install the exact tarball in artifact-only Android and iOS React Native consumers. Verify transition, paging, zoom, pan, video, loading, retry, cached reopen, and return behavior.
3. Confirm the shared canonical `<version>` tag points to the accepted release
   commit. Do not create a React Native-specific tag.

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
./scripts/publish-react-native.sh --dry-run \
  --candidate /absolute/path/to/candidate.json \
  --acceptance /absolute/path/to/accepted-receipt.json
./scripts/publish-react-native.sh --publish \
  --candidate /absolute/path/to/candidate.json \
  --acceptance /absolute/path/to/accepted-receipt.json
```

## UniApp / DCloud UTS Plugin

The Marketplace product supports classic uni-app Vue pages and uni-app x Vapor on Android/iOS. Exact HBuilderX and platform minimums come from `uni_modules/Sandrox-Levixel/package.json` and `plugin.yaml`; do not duplicate them in this guide. **Only uni-app x Vapor is in scope; VDOM, nvue, HarmonyOS, mini apps, and Web are unsupported.** The package embeds the accepted Android AAR and iOS device framework, while UTS owns only context lookup, JSON/callback transport, and local-path conversion. DOM geometry and bounded preview warmup stay in the canonical JavaScript SDK; platform behavior stays in the shared UniApp runtimes.

Resolve the UniApp product version and `native-release-version` from `plugin.yaml`; do not duplicate either value in this guide. Packaging must verify and embed the exact AAR/XCFramework recorded by the resolved native release manifest. If an independently staged UniApp target intentionally uses a different product or native version, that relationship must be explicit in the manifest and release review. Build and accept one final ZIP only after its native release manifest exists, never rebuild it after device acceptance, and never reuse a published version for different bytes.

The manifest source root is `uni_modules/Sandrox-Levixel`; shared runtimes and the legacy bridges remain in `adapters/uniapp`. `uni_modules/Sandrox-Levixel/js_sdk/canonical.js` is a checked-in generated mirror of `adapters/uniapp/js_sdk/index.js`. Regenerate it with `./scripts/sync-uniapp-canonical-js.sh` whenever the canonical SDK changes, then review the diff. Never hand-edit the generated mirror or rely on packaging to repair drift.

1. Build the final device-acceptance candidate once:

   ```sh
   ./scripts/package-uniapp.sh
   ```

   Packaging fails before building if the worktree is dirty or if the generated canonical SDK, target/native version split, native release hashes, or declared source root has drifted. It builds into temporary storage and refuses to overwrite a different same-version ZIP, checksum sidecar, or Marketplace material. `--allow-dirty` is only a local rehearsal; `--replace` is allowed only after deliberately rejecting the previous candidate and requires repeating all acceptance. The result is `dist/uniapp/levixel-uniapp-<version>.zip`; record its SHA-256 before any device run.

2. Inspect the exact bytes and compile classic/x bridges with the declared HBuilderX minimum or newer, including official x SDK typechecks:

   ```sh
   ./scripts/verify-uniapp.sh
   DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT=/absolute/path/to/Android-uni-app-x-SDK \
   DCLOUD_UNIAPP_X_IOS_SDK_ROOT=/absolute/path/to/UniAppX-iOS \
     ./scripts/verify-uniapp-uts-compiler.sh
   ```

3. The Marketplace ZIP root must directly contain `package.json` and `utssdk/`; DCloud rejects an archive wrapped in a `Sandrox-Levixel/` directory. For artifact-only consumer verification, extract the same ZIP into separate classic and x Vapor hosts. Verify transition, paging, zoom, pan, video, loading, retry, cached reopen, close timing, source alignment, scroll offsets, rapid open/close, and source return behavior on Android and iOS devices. Use HBuilderX standard run/custom base/cloud packaging for Vapor; SDK typecheck is not an offline Vapor App build.
4. Complete the remaining contact, screenshot, and device fields in `dist/uniapp/levixel-uniapp-<version>-marketplace.md`.
5. Upload the accepted ZIP to the DCloud Marketplace without rebuilding. Publish only after the final version was explicitly chosen, both classic/x applicable matrices passed, and the ZIP checksum still matches the accepted candidate.
6. Import the public Marketplace version into a clean classic uni-app consumer and rerun the production build. DCloud may add a `name` field equal to `displayName` and reformat `package.json`; all other JSON values and every other payload file must still match the accepted ZIP.
7. Attach the exact accepted UTS ZIP and its existing SHA-256 sidecar to the matching canonical GitHub Release without rebuilding or re-zipping it. A coordinated release uses the one shared `<version>` tag defined above. DCloud remains the primary UniApp installation channel; the GitHub asset is the anonymous direct-download and offline mirror.
8. Run `Verify UniApp Release Assets` with the resolved UTS version and the SHA-256 recorded during device acceptance. The workflow derives the native version from the release-source target constraint, downloads those native assets from the corresponding immutable Release, and checks the public ZIP against both product provenance lines. It never rebuilds or alters the candidate.

For a user-managed upload of the already accepted UTS bytes:

```sh
LEVIXEL_UNIAPP_VERSION="<version>"

gh release upload "${LEVIXEL_UNIAPP_VERSION}" \
  "dist/uniapp/levixel-uniapp-${LEVIXEL_UNIAPP_VERSION}.zip" \
  "dist/uniapp/levixel-uniapp-${LEVIXEL_UNIAPP_VERSION}.zip.sha256" \
  --repo sandroxy/levixel \
  --clobber
```

GitHub Actions cannot receive a local file through `workflow_dispatch`, and the DCloud Marketplace requires an authenticated download and may normalize `package.json`. Therefore the release workflow verifies an already uploaded immutable candidate instead of silently rebuilding it or persisting a DCloud session.

The separately generated `levixel-uniapp-legacy-<version>.zip` is the compatibility artifact for App native-plugin/offline consumers. Build it from the resolved native cores and canonical JavaScript SDK, pass Android/iOS artifact-only smoke tests, and attach it to the matching Release. Every historical legacy ZIP remains immutable on its original Release; no legacy ZIP may replace the Marketplace ZIP.

Audit the legacy ZIP independently by running `Verify UniApp Release Assets` with `include_legacy` against the same release source. Do not present the legacy artifact as a Marketplace package, a uni-app x package, or the recommended path for new projects.

## Web / npm

Resolve the Web product version from its explicit target in `plugin.yaml`. For a coordinated release it matches the shared release identity; an independently staged version must remain explicit and must not relabel already published products.

The Web package is ESM-only, has no runtime dependencies, and publishes as `@sandrox/levixel-web`. Its accepted interaction matrix is macOS Chrome, macOS Safari, Android Chrome, and iOS Safari. Browsers outside that matrix, embedded WebViews, legacy bundles, UMD, and IIFE delivery are not claimed.

1. From the clean release commit, build and verify the candidate once:

   ```sh
   ./scripts/package-web.sh
   ./scripts/verify-web-package.sh
   ```

2. Install `dist/web/levixel-web-<version>.tgz` in artifact-only consumers. Complete the declared desktop/mobile matrix without importing `adapters/web/src` or rebuilding the tarball.
3. Record the accepted SHA-256 from `dist/web/levixel-web-<version>.tgz.sha256`.
4. Create the canonical `<version>` tag and GitHub Release only when the declared release scope is approved. Attach these exact files without repacking:

   - `dist/web/levixel-web-<version>.tgz`
   - `dist/web/levixel-web-<version>.tgz.sha256`

5. Run `Verify Web Release Assets` with the resolved version and accepted SHA-256. The workflow checks the public assets against the canonical tag, independently rebuilds only for source comparison, installs the accepted tarball, and reruns real-Chrome interaction coverage. It never modifies or republishes a rebuilt package.
6. Configure npm Trusted Publishing for:

   - Provider: GitHub Actions
   - Organization or user: `sandroxy`
   - Repository: `levixel`
   - Workflow filename: `publish-web-npm.yml`
   - Allowed action: `npm publish`

7. Run `Publish Web npm` with the same version and SHA-256. The workflow downloads, verifies, and publishes the exact GitHub Release tarball through OIDC. It fails if that npm version already exists.

The local `--allow-dirty` packaging option is only a pipeline rehearsal. A dirty-worktree artifact is not publishable until the identical bytes pass clean-commit verification. A differing candidate must use `--replace` explicitly and repeat all artifact-only acceptance; never rename or silently overwrite an accepted tarball.

## Provenance

`THIRD_PARTY_NOTICES.md` is mandatory release content. Levixel branding does not require Galeria names in runtime APIs, but the MIT notices remain attached to every artifact that carries derivative code. See [PROVENANCE.md](PROVENANCE.md) for the audited lineage and classification.
