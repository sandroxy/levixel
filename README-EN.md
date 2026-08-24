# Levixel

[中文](README.md)

Levixel is a native-feeling image and video viewer with shared transitions, horizontal paging, pinch-to-zoom, panning while zoomed, drag-to-dismiss, and video playback.

This repository is Levixel's public product home, artifact release repository, and iOS Swift Package. Core source, cross-platform adapters, and release builds are maintained by a separate internal pipeline; public consumers integrate only the versioned artifacts published here.

## Published Packages

| Platform | Public artifact | Current version |
| --- | --- | --- |
| Android | Maven Central `io.gitee.sandrox:levixel` | `1.1.0` |
| iOS | Swift Package `https://github.com/sandroxy/levixel.git` | `1.1.0` |
| HarmonyOS | OHPM `@sandrox/levixel` | Preparing |
| React Native / UniApp / Web | npm and platform adapters | Preparing |

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
    implementation("io.gitee.sandrox:levixel:1.1.0")
}
```

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

Select `1.1.0` or a compatible `1.x` version, then link the `Levixel` product.

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

## License And Provenance

Levixel is released under the MIT License. The implementation has been substantially rewritten and polished across platforms, while retaining traceable MIT-licensed derivative lineage. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for complete attribution.
