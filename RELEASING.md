# Release Process

This document is for Levixel maintainers. Package installation and application
integration are documented in [README.md](README.md) and
[README-EN.md](README-EN.md).

Use the existing channel entry points below. GitHub uploads and workflow runs
can be managed in the browser; local `gh` commands are optional conveniences,
not prerequisites for that route. npm authentication uses the configured
Trusted Publishers; HarmonyOS uses the existing interactive OHPM installation.

## Artifact Graph

Levixel records every ecosystem product and its immutable artifact. Targets normally inherit the canonical manifest version; an independently staged target may explicitly declare its product version without relabeling already published artifacts on other platforms.

## Release state and candidate identity

The version in `plugin.yaml` is the current release target, not a declaration
that the version is already public. Published stability comes from the
immutable tag and public Release. Concrete local bytes are identified by the
candidate manifest, never by the version alone:

- platform `dist/` directories contain the only copies of the release files;
- `dist/candidate.json` records the current files using paths relative to
  `dist/`; a dirty or unsigned rehearsal uses the same manifest with an
  ineligible state;
- the candidate id binds the product version, source commit, and artifact-set
  SHA-256. Rebuilding a rejected still-unpublished version replaces the current
  manifest and invalidates previous results for those bytes. Published versions
  can never be rebuilt or replaced.

After all coordinated artifacts have passed their repository self-checks,
record the current set with:

```sh
./scripts/prepare-release-candidate.sh
```

This command does not copy the artifacts. It removes older versioned files only
from the selected output families, retaining the selected files and the latest
canonical Git tag's version. Unknown files and historical self-contained
candidate directories are not deleted. The tag is a local retention boundary,
not a claim that every registry has finished publishing. Existing self-contained
candidates remain readable; new runs no longer create candidate directories.

[`release-policy.json`](release-policy.json) is this product repository's
machine-readable release contract. Candidate creation and the publication gate
both require an exact match for the plugin id, source repository, qualification
fields, artifact roles, and automated consumer targets. Do not add
sibling products to that policy: a new plugin owns its own policy and can be
onboarded without changing Levixel's release gate.

The separate `integrated-plugins` repository must consume the printed absolute
manifest path with `--candidate`; its default mode always uses public stable
artifacts from `verification/stable-lock.json` and never a sibling checkout.
Every candidate-declared target runs in a Levixel-only consumer. Shared React
Native and classic UniApp catalog sources are used to generate ignored isolated
hosts, so another plugin's publication state can never block or influence a
Levixel acceptance receipt. The separately named combined-showcase smoke uses
only public stable artifacts and is not a Levixel publication gate.
The manifest declares automated consumer targets. From a clean verifier commit, run each target
through `verification/run-acceptance.rb`; direct `verify.sh all` output is useful
for diagnosis but is not per-target release evidence.

The verifier's `record-acceptance.rb --candidate /absolute/path/to/candidate.json`
summarizes those automated results for the exact artifact set. Its `accepted`
status means the automated checks passed; it does not certify manual interaction
coverage or authorize publication. No manual confirmation file or per-scenario
evidence is required.

The publisher decides whether to release after reviewing actual use and known
issues. Representative testing is sufficient unless a change or observed problem
calls for a targeted regression check. Disclose simulator-only coverage when
describing testing; do not claim that untested devices or scenarios passed.
Known release-blocking defects must be resolved before publishing.

| Platform | Public product | Publish through |
| --- | --- | --- |
| Android | `io.gitee.sandrox:levixel` | Central Portal, using the signed Maven Central bundle |
| iOS | `Levixel` | Canonical Git tag and GitHub XCFramework asset, consumed by SwiftPM |
| HarmonyOS | `@sandrox/levixel` | Existing OHPM CLI; mirror the approved HAR afterward |
| React Native | `@sandrox/levixel` | GitHub `Publish npm` workflow |
| UniApp | `Sandrox-Levixel` | HBuilderX, from the accepted UTS module in its generated consumer |
| Web | `@sandrox/levixel-web` | GitHub `Publish Web npm` workflow |

The raw Android AAR and HarmonyOS HAR are available for offline integration. Maven Central and OHPM remain the preferred channels because they carry package identity and version metadata.

Product publication workflows are intentionally manual. Publishing a GitHub Release must not cause unrelated products that remain on an earlier target version to rebuild, mirror, or publish automatically.

## Immutable Candidate Rule

1. Start from the release commit with a clean worktree.
2. Finalize packaged documentation, build each artifact once or explicitly reuse unchanged artifacts, then record the complete set.
3. Run the artifact self-checks in this repository.
4. Install those exact files in artifact-only consumer hosts. Consumer hosts must not compile or copy Levixel source.
5. Generate the automated result summary in `integrated-plugins` for the exact
   candidate id and artifact-set digest.
6. Review the actual interaction experience and known limitations with the
   publisher. Proceed only when the publisher chooses to release.
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

The formal candidate requires a clean worktree. Maven signing credentials are
required when building its signed Maven artifacts, not when verifying and
copying an existing signed set.

## Reusing unchanged candidate artifacts

Reuse is a per-artifact decision, not a platform exemption. It is limited to
candidates for the same still-unpublished version. Resolve and verify the
source candidate before preparing the next set; record the new manifest only
after that set is complete. Historical results never transfer to changed bytes.

[`native-reuse-policy.json`](native-reuse-policy.json) declares each native
artifact group, output directory, and repository-controlled source/package
inputs. Inspect a source candidate without changing any files:

```sh
ruby scripts/reuse-native-artifacts.rb \
  --candidate /absolute/path/to/source/candidate.json --plan
```

From a clean commit, select any unchanged groups printed by the plan:

```sh
./scripts/prepare-native-release.sh \
  --reuse-candidate /absolute/path/to/source/candidate.json \
  --reuse "<group-name>"
```

Repeat `--reuse` for additional groups. The command verifies the entire source
snapshot, source-commit ancestry, and the declared tracked inputs, including
file modes, added files, and deleted files. It retains selected artifacts and
sidecars in place, or copies them from an older self-contained candidate, without
repacking; unselected groups follow their normal build
commands. A selected group with changed or missing inputs fails explicitly.
Maven reuse also verifies the release-key signatures, internal checksums, and
agreement between the standalone AAR, Maven repository, and Central bundle.
There is no signing-key export for this operation. Reuse cannot be combined
with rehearsal flags or independent iOS artifact/URL overrides.

The new native manifest retains the source candidate and per-group input
digests under `buildProvenance.artifactReuse`. Candidate creation and the
publication gate check this provenance again. Its release commit identifies the
new coordinated set; it does not claim the reused binaries were rebuilt there.
The input digest describes tracked source/package inputs, not a claim that a
different compiler or SDK would reproduce identical bytes. Changes to build
dependencies require reviewing the declared scopes.

Run all package self-checks before snapshotting. An adapter archive can remain
unchanged only if its full existing bytes still pass those checks against the
new release inputs. Embedded documentation counts as package content; a
documentation-only repack is still a changed artifact.

Changing release metadata does not by itself require repeating manual testing.
Review changed behavior and package contents to decide whether additional
interaction checks are needed. Keep previous test results intact.
Automated consumer results must refer to the new candidate and current verifier
commit; generating them does not require another manual approval record.

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

Use a short, user-facing Release summary and link to the tag's changelog for
details. Editing that web summary does not require changing packaged files.
If only external publisher settings changed, re-run the failed workflow. After
fixing workflow code, start a new run from the updated branch while keeping the
release-version input and canonical tag unchanged.

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

Native preparation already creates the signed Central Portal bundle before the
candidate is recorded. Do not rerun bundling after acceptance or tagging.
Upload `dist/native-android/levixel-<version>-maven-central.zip` in user-managed
mode, set Deployment Name to `levixel-<version>`, and publish after portal
validation. The display name does not change the Maven coordinate. Use the
`Mirror Android AAR` workflow for the matching GitHub offline mirror.

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

The packaging script verifies the supplied SHA-256, embedded framework version, slices, privacy manifest, legal notices, and native-source digest before copying the ZIP byte-for-byte to its canonical release filename. For a formal clean release, the embedded digest must belong to the embedded source commit; that commit must be an ancestor of the release commit; and the same digest must still match every current iOS build input. This two-phase rule permits a later metadata-only release commit to add the accepted SwiftPM checksum without creating a commit/checksum cycle, but rejects dirty-source attribution and any intervening native-source change. The native release manifest records the binary's source commit and checksum.

## HarmonyOS / OHPM

1. Confirm the `@sandrox` scope and publisher access.
2. Build and inspect `dist/native-harmonyos/levixel-<version>.har` once.
3. Install that HAR in an artifact-only consumer and review the interaction experience. Dynamic host updates, stable-id returns, and absent-source fades are useful targeted checks. Simulator testing must not be described as physical-device testing.
4. Publish the accepted HAR to OHPM without rebuilding.
5. Install the public package in a clean consumer and run a smoke test.
6. Run the `Mirror HarmonyOS HAR` workflow for the approved version. It verifies the OHPM SHA-512 integrity and package metadata, then mirrors the exact HAR and SHA-256 file to the matching GitHub Release. It does not update the published native release manifest.

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

2. Install the exact tarball in artifact-only Android and iOS React Native consumers. Review representative interaction coverage and focus additional checks on changed behavior or observed risks. Transitions, loading/video behavior, and stable-id returns after list updates or cell reuse are suggested checks, not an exhaustive per-release checklist.
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

The Marketplace product supports classic uni-app Vue pages and uni-app x Vapor on Android/iOS. Exact HBuilderX and platform minimums come from `uni_modules/Sandrox-Levixel/package.json` and `plugin.yaml`; do not duplicate them in this guide. **For uni-app x, only Vapor is in scope; x VDOM is unsupported. nvue, HarmonyOS, mini apps, and Web are also unsupported.** The package embeds the accepted Android AAR and iOS device framework, while UTS owns only context lookup, JSON/callback transport, and local-path conversion. DOM geometry and bounded preview warmup stay in the canonical JavaScript SDK; platform behavior stays in the shared UniApp runtimes.

Resolve the UniApp product version and `native-release-version` from `plugin.yaml`; do not duplicate either value in this guide. Packaging must verify and embed the exact AAR/XCFramework recorded by the resolved native release manifest. If an independently staged UniApp target intentionally uses a different product or native version, that relationship must be explicit in the manifest and release review. Build and accept one final ZIP only after its native release manifest exists, never rebuild it after device acceptance, and never reuse a published version for different bytes.

The manifest source root is `uni_modules/Sandrox-Levixel`; shared runtimes and the legacy bridges remain in `adapters/uniapp`. `uni_modules/Sandrox-Levixel/js_sdk/canonical.js` is a checked-in generated mirror of `adapters/uniapp/js_sdk/index.js`. Regenerate it with `./scripts/sync-uniapp-canonical-js.sh` whenever the canonical SDK changes, then review the diff. Never hand-edit the generated mirror or rely on packaging to repair drift.

1. Build the final device-acceptance candidate once:

   ```sh
   ./scripts/package-uniapp.sh
   ```

   Packaging fails before building if the worktree is dirty or if the generated canonical SDK, target/native version split, native release hashes, or declared source root has drifted. It builds into temporary storage and refuses to overwrite a different same-version ZIP, checksum sidecar, or Marketplace material. `--allow-dirty` is only a local rehearsal; `--replace` is allowed only after deliberately rejecting the previous candidate. Changed package contents determine which interactions need additional testing. The result is `dist/uniapp/levixel-uniapp-<version>.zip` with a SHA-256 sidecar.

2. Inspect the exact bytes and compile classic/x bridges with the declared HBuilderX minimum or newer, including official x SDK typechecks:

   ```sh
   ./scripts/verify-uniapp.sh
   DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT=/absolute/path/to/Android-uni-app-x-SDK \
   DCLOUD_UNIAPP_X_IOS_SDK_ROOT=/absolute/path/to/UniAppX-iOS \
     ./scripts/verify-uniapp-uts-compiler.sh
   ```

3. The Marketplace ZIP root must directly contain `package.json` and `utssdk/`; DCloud rejects an archive wrapped in a `Sandrox-Levixel/` directory. Consume the same ZIP in classic and x Vapor hosts, and review representative Android/iOS interactions. Focus additional testing on changed areas such as source geometry, list updates, loading, or video. Use HBuilderX standard run/custom base/cloud packaging for Vapor; SDK typecheck is not an offline Vapor App build.
4. Use `dist/uniapp/levixel-uniapp-<version>-marketplace.md` as form reference; no separate device or per-scenario record is required.
5. In HBuilderX, open the existing generated consumer that installed the accepted ZIP, right-click `uni_modules/Sandrox-Levixel`, and choose **发布到插件市场**. Confirm the release version and required form fields. Do not upload the ZIP through the marketplace website or rebuild from the source checkout. HBuilderX's package metadata and changelog-date writeback is expected; executable files must remain unchanged.
6. Import the public Marketplace version into a clean classic uni-app consumer and rerun the production build. Compare its package identity, dependencies, native configuration, and executable payloads with the accepted ZIP. Report marketplace-managed descriptions, compatibility declarations and documentation changes for review instead of requiring an identical published ZIP archive.
7. Attach the exact accepted UTS ZIP and its existing SHA-256 sidecar to the matching canonical GitHub Release without rebuilding or re-zipping it. A coordinated release uses the one shared `<version>` tag defined above. DCloud remains the primary UniApp installation channel; the GitHub asset is the anonymous direct-download and offline mirror.
8. Run `Verify UniApp Release Assets` with the resolved UTS version and the SHA-256 recorded during device acceptance. The workflow derives the native version from the release-source target constraint, downloads those native assets from the corresponding immutable Release, and checks the public ZIP against both product provenance lines. It never rebuilds or alters the candidate.

For a user-managed upload of the already accepted UTS bytes:

```sh
LEVIXEL_UNIAPP_VERSION="<version>"

gh release upload "${LEVIXEL_UNIAPP_VERSION}" \
  "dist/uniapp/levixel-uniapp-${LEVIXEL_UNIAPP_VERSION}.zip" \
  "dist/uniapp/levixel-uniapp-${LEVIXEL_UNIAPP_VERSION}.zip.sha256" \
  --repo sandroxy/levixel
```

The upload must fail if either asset name already exists. Verify or remove an
unpublished draft mistake explicitly; never replace an asset on a published
Release.

GitHub Actions cannot receive a local file through `workflow_dispatch`, and the DCloud Marketplace requires an authenticated download and may normalize `package.json`. Therefore the release workflow verifies an already uploaded immutable candidate instead of silently rebuilding it or persisting a DCloud session.

Maintain publication metadata in the tracked module, not in generated consumers.
HBuilderX's compatibility form uses integer iOS choices and requires common
classic/x system minima; the native configs still declare each runtime's actual
requirements. Platform `extVersion` declarations are separate from the current
package version. Preserve their intended meaning when updating the release.
The market README is supplied by `readme.md`; it does not need a second manual
copy. For later presentation-only corrections, use HBuilderX's **修改插件基本信息**.

The separately generated `levixel-uniapp-legacy-<version>.zip` is the compatibility artifact for App native-plugin/offline consumers. Build it from the resolved native cores and canonical JavaScript SDK, then run the independent `uniapp-legacy` target in `integrated-plugins`. That target consumes only the ZIP, validates the Android and iOS payloads, and generates an isolated classic uni-app host for Android and iOS packaging. Review the Android/iOS interaction experience, then attach the accepted ZIP to the matching Release. Every historical legacy ZIP remains immutable on its original Release; no legacy ZIP may replace the Marketplace ZIP.

Audit the legacy ZIP independently by running `Verify UniApp Release Assets` with `include_legacy` against the same release source. Do not present the legacy artifact as a Marketplace package, a uni-app x package, or the recommended path for new projects.

## Web / npm

Resolve the Web product version from its explicit target in `plugin.yaml`. For a coordinated release it matches the shared release identity; an independently staged version must remain explicit and must not relabel already published products.

The Web package is ESM-only, has no runtime dependencies, and publishes as `@sandrox/levixel-web`. Its supported browser matrix is macOS Chrome, macOS Safari, Android Chrome, and iOS Safari. Browsers outside that matrix, embedded WebViews, legacy bundles, UMD, and IIFE delivery are not claimed.

1. From the clean release commit, build and verify the candidate once:

   ```sh
   ./scripts/package-web.sh
   ./scripts/verify-web-package.sh
   ```

2. Install `dist/web/levixel-web-<version>.tgz` in artifact-only consumers. Review representative desktop/mobile coverage without importing `adapters/web/src` or rebuilding the tarball. Suggested risk checks include list updates, sparse bindings, source removal, and node reuse. Record the actual browsers tested and any accepted coverage limitations.
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

The local `--allow-dirty` packaging option is only a pipeline rehearsal. A dirty-worktree artifact is not publishable until the identical bytes pass clean-commit verification. A differing candidate must use `--replace` explicitly and pass automated artifact-only checks; additional manual testing depends on changed behavior and known risks. Never rename or silently overwrite an accepted tarball.

## Provenance

`THIRD_PARTY_NOTICES.md` is mandatory release content. Levixel branding does not require Galeria names in runtime APIs, but the MIT notices remain attached to every artifact that carries derivative code. See [PROVENANCE.md](PROVENANCE.md) for the audited lineage and classification.
