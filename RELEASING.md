# Public Release Contract

This repository owns Levixel's public product page, release assets, issue
tracking, Swift Package, and npm trusted-publishing workflow. The canonical
build pipeline lives separately and must finish source-level and device-level
verification before any candidate reaches this repository.

## Release Assets

The release tagged `X.Y.Z` may contain these accepted artifacts:

- `levixel-X.Y.Z.xcframework.zip`
- `levixel-react-native-X.Y.Z.tgz`
- `levixel-react-native-X.Y.Z.tgz.sha256`
- `levixel-native-X.Y.Z.json`
- HarmonyOS and UniApp artifacts with matching checksum sidecars

Artifacts are built once. Uploading, public verification, registry publishing,
and consumer smoke tests must never rebuild or modify accepted bytes.

## npm

`@sandrox/levixel` is published by `.github/workflows/publish-npm.yml` through
npm Trusted Publishing. The workflow downloads the exact package attached to
the matching release, verifies its checksum and metadata, compares its embedded
Android and iOS cores with the public native artifacts, and then publishes it
through OIDC.

For the already-created `1.1.0` release, attach the accepted npm package,
checksum sidecar, and native manifest, then run the workflow manually with
`version` set to `1.1.0`. Future releases may trigger the same workflow when the
fully populated release is published.
