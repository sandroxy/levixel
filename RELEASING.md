# Release Process

## Artifact Graph

Levixel has one canonical version and ecosystem-specific products:

| Platform | Public product | Canonical artifact |
| --- | --- | --- |
| Android | `io.gitee.sandrox:levixel:1.1.0` | Maven publication containing the AAR, POM, Gradle metadata, sources, and Javadocs |
| iOS | `Levixel` | Checksum-pinned Swift Package that downloads the XCFramework ZIP |
| HarmonyOS | `@sandrox/levixel@1.1.0` | OHPM HAR |
| React Native | `@sandrox/levixel@1.1.0` | npm tarball containing thin Expo Modules bridges and the verified Android/iOS native artifacts |
| UniApp | `Sandrox-Levixel@1.1.0` | DCloud native-plugin ZIP containing thin Android/iOS bridges, the verified native artifacts, and the JavaScript SDK |

The raw Android AAR remains an internal adapter input. It is not the preferred
public Android installation format because an AAR alone cannot declare its
identity, version, or transitive dependencies.

## One-Build Rule

1. Start from the release commit with a clean worktree.
2. Set Android signing variables when preparing a Maven Central candidate:

   ```sh
   export LEVIXEL_SIGNING_KEY="$(cat private-key.asc)"
   export LEVIXEL_SIGNING_PASSWORD="..."
   ```

   `LEVIXEL_SIGNING_KEY` contains the ASCII-armored private key. The Gradle
   signing plugin uses it in memory; no secret is stored in the repository.

3. Run:

   ```sh
   ./scripts/prepare-native-release.sh
   ```

   For a local pipeline rehearsal only:

   ```sh
   ./scripts/prepare-native-release.sh --allow-dirty --allow-unsigned
   ```

4. Manually verify transition and gesture behavior in all three shared native
   test hosts without rebuilding the plugin.
5. Publish only files listed in
   `dist/native-release/levixel-native-1.1.0.json`.

## Android / Maven Central

External prerequisites:

- A Central Publisher Portal account.
- A verified namespace that permits `io.gitee.sandrox`.
- A public signing key and the matching private key supplied through the two
  environment variables above.

The canonical release-signing key is published through the key servers
supported by Maven Central. Its full fingerprint is:

```text
B7D159C354B9EF7318D3544200BE5C219A0DD690
```

`prepare-maven-central-bundle.sh` rejects missing signatures, signatures made
by any other key, and incomplete checksum sets before producing an upload.

After the signed native candidate has passed the Android host, create the
Central Portal upload without rebuilding:

```sh
./scripts/prepare-maven-central-bundle.sh
```

Upload `dist/native-android/levixel-1.1.0-maven-central.zip` to the Central
Publisher Portal in user-managed mode. Publish it only after portal validation.

The retained `PhotoView 2.3.0` dependency is hosted by JitPack, so Android
consumers currently need both Maven Central and JitPack. Replacing or vendoring
that dependency requires a separate gesture regression pass and must not be
folded into release packaging work.

## iOS / Swift Package Manager

1. Create the source tag `levixel-v1.1.0` on the canonical release commit.
2. Push the generated Swift Package contents to the public product repository
   at `https://github.com/sandroxy/levixel`.
3. Tag the public product repository `1.1.0`.
4. Create the matching public GitHub release and attach
   `dist/native-ios/levixel-1.1.0.xcframework.zip` without rebuilding.
5. Confirm the release asset is anonymously downloadable and matches the
   checksum pinned in `Package.swift`.
6. Resolve the public package in a clean iOS consumer and run one final smoke
   test.

The generated package manifest points to the canonical GitHub release URL and
contains the checksum computed from the verified XCFramework ZIP. Override the
URL before packaging only when the permanent binary host changes:

```sh
LEVIXEL_IOS_BINARY_URL=https://example.com/levixel-1.1.0.xcframework.zip \
  ./scripts/package-native-ios.sh
```

## HarmonyOS / OHPM

1. Confirm the `@sandrox` OHPM scope and package name are available to the
   publisher account.
2. Authenticate `ohpm` with the publisher ID.
3. Publish `dist/native-harmonyos/levixel-1.1.0.har` without rebuilding.
4. Install `@sandrox/levixel@1.1.0` into a clean HarmonyOS consumer and run a
   final smoke test.

## React Native / npm

The npm product embeds the exact Android AAR and iOS XCFramework recorded in
`dist/native-release/levixel-native-1.1.0.json`. It must not compile copied
native viewer source or resolve an unpinned native core during consumer install.

1. Package the npm candidate once:

   ```sh
   ./scripts/package-react-native.sh
   ```

2. Update the shared host lockfile to the candidate tarball, then verify
   Android and iOS transition, paging, zoom, pan, video, loading, and return
   behavior:

   ```sh
   ./scripts/verify-react-native.sh android
   ./scripts/verify-react-native.sh ios
   ```

   The verification script uses a frozen lockfile and never rebuilds the
   tarball.
3. Commit the source and host lockfile that produced the accepted candidate,
   then create the canonical tag on that commit:

   ```sh
   git tag -a levixel-react-native-v1.1.0 -m "Levixel React Native 1.1.0"
   ```

4. Check the exact accepted archive and npm publication metadata:

   ```sh
   ./scripts/publish-react-native.sh --dry-run
   ```

5. Authenticate with the public npm registry and publish the same archive
   bytes, without rerunning `package-react-native.sh`:

   ```sh
   npm login --scope=@sandrox --registry=https://registry.npmjs.org/
   ./scripts/publish-react-native.sh --publish
   ```

6. Install `@sandrox/levixel@1.1.0` from npm in a clean consumer and run the
   final Android/iOS smoke test. Public npm versions are immutable; never reuse
   `1.1.0` for different bytes.

## UniApp / DCloud Native Plugin

The UniApp product embeds the exact Android AAR and iOS device framework from
the `1.1.0` native release. Its bridges own only DCloud lifecycle, DOM source
geometry conversion, bounded preview warmup, and event/error transport.

1. Build the candidate once with the matching DCloud SDK:

   ```sh
   DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
     ./scripts/package-uniapp.sh
   ```

2. Verify and stage the exact candidate without rebuilding:

   ```sh
   ./scripts/verify-uniapp.sh
   ```

3. Open `uniapp-plugins-test` in HBuilderX, build a custom base or offline
   package for AppID `__UNI__A92914D`, and verify Android and iOS transition,
   paging, zoom, pan, video, loading, retry, cached reopen, and return behavior.
4. Publish `dist/uniapp/sandrox-levixel-uniapp-1.1.0.zip` unchanged. Never
   rebuild after hand verification or reuse `1.1.0` for different bytes.

## Provenance

`THIRD_PARTY_NOTICES.md` is mandatory release content. Levixel branding does
not require Galeria names in runtime APIs, but the MIT notices remain attached
to every artifact that carries the derivative core. See `PROVENANCE.md` for the
audited lineage and classification.
