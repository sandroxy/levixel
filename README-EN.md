# Levixel

[中文](README.md)

Levixel is a native-feeling image and video viewer with shared transitions, horizontal paging, pinch-to-zoom, panning while zoomed, drag-to-dismiss, and video playback.

This repository is the canonical source, public contract, packaging toolkit, and release home for Levixel. The Android, iOS, and HarmonyOS native cores, the React Native and UniApp adapters, and the Web source candidate are maintained here. Every release version maps to one verified, immutable artifact set.

## Published Packages

| Platform | Public artifact | Current version |
| --- | --- | --- |
| Android | Maven Central `io.gitee.sandrox:levixel` | `1.1.1` |
| iOS | Swift Package `https://github.com/sandroxy/levixel.git` | `1.1.1` |
| React Native / Expo | npm `@sandrox/levixel` | `1.1.1` |
| HarmonyOS | OHPM `@sandrox/levixel` | `1.1.1` |
| UniApp | [UTS Marketplace plugin](https://ext.dcloud.net.cn/plugin?id=29394) / [App native-plugin ZIP](https://github.com/sandroxy/levixel/releases) | `1.1.1` |

The Web runtime is undergoing pre-release interaction validation under `adapters/web`. It has not been published and is therefore not part of the 1.1.1 product table above.

## Source Layout

```text
levixel/
├── native/          # Android, iOS, and HarmonyOS native cores
├── adapters/        # React Native and UniApp adapters, plus the Web source candidate
├── uni_modules/     # DCloud Marketplace UTS plugin source
├── contract/        # Cross-platform public contract
├── packaging/       # Platform artifact templates
├── scripts/         # Build, artifact inspection, and release tools
├── schema/          # Plugin manifest schema
└── plugin.yaml      # Version, capability, and delivery manifest
```

Artifact-only consumer hosts install the final AAR, XCFramework, HAR, npm tarball, or UniApp ZIP. They never compile this source tree directly. The bytes accepted during hand verification are the same bytes released publicly.

## Android

Make Maven Central and JitPack available to dependency resolution:

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

Add the dependency:

```kotlin
dependencies {
    implementation("io.gitee.sandrox:levixel:1.1.1")
}
```

Maven Central is the canonical Android dependency channel. The matching GitHub Release also provides `levixel-1.1.1.aar` and its SHA-256 file for offline or manual integration. The AAR is byte-identical to the Maven Central artifact.

The Android core currently retains the fully validated `PhotoView 2.3.0` integration, so consumers must keep JitPack available for now.

Minimal viewer setup:

```java
LevixelMediaItem item = new LevixelMediaItem(
        "cover",
        LevixelMediaItem.MediaType.IMAGE,
        fullImageUrl,
        thumbnailUrl
);

List<LevixelMediaItem> items = Collections.singletonList(item);
LevixelSourceViewRegistry.register(
        LevixelSharedElementNames.forItem(item),
        sourceImageView
);

LevixelViewerOverlayView viewer = new LevixelViewerOverlayView(
        context,
        items,
        0,
        false,
        null,
        null
);
rootView.addView(viewer);
```

For complete system-bar transitions, use an edge-to-edge host and route system back events to `viewer.requestClose()`.

## iOS

In Xcode, choose **File > Add Package Dependencies** and enter:

```text
https://github.com/sandroxy/levixel.git
```

Select `1.1.1` or a compatible `1.x` version, then link the `Levixel` product.

```swift
import Levixel

let items: [LevixelMediaItem] = [
    .imageURL(fullImageURL, thumbnailURL: thumbnailURL, placeholder: imageView.image),
    .video(url: videoURL, poster: posterURL)
]

let dataSource = LevixelArrayDataSource(items: items)
imageView.setupLevixelViewer(
    dataSource: dataSource,
    initialIndex: 0,
    configuration: LevixelViewerConfiguration(theme: .dark),
    galleryId: "article-gallery"
)
```

The Swift Package references a checksum-pinned XCFramework. Xcode verifies the downloaded binary against the checksum in `Package.swift`.

## HarmonyOS

Install from OHPM:

```sh
ohpm install @sandrox/levixel@1.1.1
```

OHPM is the canonical HarmonyOS dependency channel. The matching GitHub Release also provides `levixel-1.1.1.har` and its SHA-256 file for offline or manual integration. The HAR is byte-identical to the published OHPM artifact.

## React Native / Expo

```sh
pnpm add @sandrox/levixel
npx expo prebuild
```

The npm package contains thin bridges and the verified Android/iOS native artifacts. It does not copy or rebuild the viewer core in the consuming application. See the [React Native adapter guide](adapters/react-native/README.md) for the component API.

## UniApp

The UniApp adapter provides a formal UTS API bridge for classic uni-app on Android and iOS while retaining the accepted App native-plugin bridge as an opt-in integration path. Both bridges reuse one platform runtime, the canonical JavaScript SDK, and the published native cores; `sourceVisibility` remains `visible` by default. This release does not claim uni-app x support. See the [UniApp adapter guide](adapters/uniapp/README.md) for the contract and packaging workflow.

The [DCloud Marketplace](https://ext.dcloud.net.cn/plugin?id=29394) is the recommended default channel for new projects. The matching [GitHub Release](https://github.com/sandroxy/levixel/releases) also provides the same `levixel-uniapp-<version>.zip` and its SHA-256 file for direct downloads, offline archives, and manual installation under `uni_modules/Sandrox-Levixel/`.

Classic uni-app Android/iOS projects that deliberately choose the App native-plugin workflow instead of UTS—whether newly integrated or existing—can download the separately accepted `levixel-uniapp-legacy-<version>.zip`. It is not an older viewer: it is an alternative bridge delivery that uses the same-version runtime, canonical JavaScript SDK, and native cores. Extract it under `nativeplugins/Sandrox-Levixel/` and use a custom debugging base or offline packaging. This ZIP is not the UTS Marketplace package and does not support uni-app x.

## Development And Releases

See [DEVELOPMENT.md](DEVELOPMENT.md) for local builds, artifact checks, and SDK prerequisites. See [RELEASING.md](RELEASING.md) for immutable artifact and publication rules.

## License And Provenance

Levixel is released under the MIT License. The implementation has been substantially rewritten and polished across platforms while retaining traceable MIT-licensed derivative lineage. See [PROVENANCE.md](PROVENANCE.md), [LICENSE](LICENSE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
