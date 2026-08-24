# Levixel

[English](README-EN.md)

Levixel 是一套强调原生手感的图片与视频查看器，提供共享转场、横向分页、双指缩放、缩放后平移、竖拖关闭与视频播放能力。

这个仓库是 Levixel 的公共产品入口、制品发布仓库和 iOS Swift Package 仓库。核心源码、跨平台桥接层与制品构建由独立的内部流水线统一维护；公开消费者始终通过这里发布的版本化制品接入。

## 当前发布

| 平台 | 公开制品 | 当前版本 |
| --- | --- | --- |
| Android | Maven Central `io.gitee.sandrox:levixel` | `1.1.0` |
| iOS | Swift Package `https://github.com/sandroxy/levixel.git` | `1.1.0` |
| HarmonyOS | OHPM `@sandrox/levixel` | 准备中 |
| React Native / UniApp / Web | npm 与平台适配制品 | 准备中 |

## Android

在依赖仓库中加入 Maven Central 与 JitPack：

```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://jitpack.io")
    }
}
```

添加依赖：

```kotlin
dependencies {
    implementation("io.gitee.sandrox:levixel:1.1.0")
}
```

当前 Android 核心保留了已经完整验收的 `PhotoView 2.3.0`，因此消费者需要暂时保留 JitPack 仓库。

最小打开方式：

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

为获得完整的系统栏转场效果，宿主页面应采用 edge-to-edge，并将系统返回事件交给 `viewer.requestClose()`。

## iOS

在 Xcode 中选择 **File > Add Package Dependencies**，输入：

```text
https://github.com/sandroxy/levixel.git
```

选择 `1.1.0` 或兼容的 `1.x` 版本，然后链接 `Levixel` 产品。

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

Swift Package 使用校验和固定的 XCFramework；Xcode 会验证下载内容与 `Package.swift` 中的 checksum 一致。

## 许可证与来源

Levixel 以 MIT License 发布。当前实现经过了大量重构和跨平台打磨，但仍保留可追溯的 MIT 衍生代码来源。完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
