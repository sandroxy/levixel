# Levixel

[English](README-EN.md)

Levixel 是一套强调原生手感的图片与视频查看器，提供共享转场、横向分页、双指缩放、缩放后平移、竖拖关闭与视频播放能力。

本仓库是 Levixel 的规范源码、公共契约、打包工具与公开发布入口。Android、iOS、HarmonyOS 原生核心以及 React Native、UniApp 适配器都在这里维护；每个发布版本对应一组经过校验且不可变的制品。

## 当前发布

| 平台 | 公开制品 | 当前版本 |
| --- | --- | --- |
| Android | Maven Central `io.gitee.sandrox:levixel` | `1.1.0` |
| iOS | Swift Package `https://github.com/sandroxy/levixel.git` | `1.1.0` |
| React Native / Expo | npm `@sandrox/levixel` | `1.1.0` |
| HarmonyOS | OHPM `@sandrox/levixel` | 发布准备中 |
| UniApp | `Sandrox-Levixel` 原生插件包 | 发布准备中 |

## 源码结构

```text
levixel/
├── native/          # Android、iOS、HarmonyOS 原生核心
├── adapters/        # React Native 与 UniApp 薄桥接层
├── contract/        # 跨平台公共契约
├── packaging/       # 平台制品模板
├── scripts/         # 构建、制品检查与发布工具
├── schema/          # 插件清单 Schema
└── plugin.yaml      # 版本、能力与交付目标清单
```

测试宿主只消费最终 AAR、XCFramework、HAR、npm tarball 或 UniApp ZIP，不直接编译本仓库源码。通过人工验收后发布的是同一份制品，不会重新构建一个未经验证的副本。

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

Maven Central 是 Android 的标准依赖渠道。对应 GitHub Release 同时提供 `levixel-1.1.0.aar` 及其 SHA-256 文件，仅用于离线或手动集成；该 AAR 与 Maven Central 制品字节级一致。

当前 Android 核心保留了完整验收的 `PhotoView 2.3.0`，因此消费者暂时需要保留 JitPack 仓库。

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

## React Native / Expo

```sh
pnpm add @sandrox/levixel
npx expo prebuild
```

该 npm 包只包含薄桥接层与校验过的 Android/iOS 原生制品，不在消费者项目中复制或重新编译查看器核心。完整组件接口见 [React Native 适配器文档](adapters/react-native/README.md)。

## UniApp

UniApp 适配器支持 Android 与 iOS，包含严格 JavaScript SDK、DOM 源图几何转换与原生制品桥接。当前源码与打包流程已收录，公共分发渠道仍在准备；接入协议见 [UniApp 适配器文档](adapters/uniapp/README.md)。

## 开发与发布

本地构建、制品自检与所需 SDK 见 [DEVELOPMENT.md](DEVELOPMENT.md)。不可变制品和版本发布流程见 [RELEASING.md](RELEASING.md)。

## 许可证与来源

Levixel 以 MIT License 发布。当前实现经过大量重构和跨平台打磨，但仍保留可追溯的 MIT 衍生代码来源。完整审计见 [PROVENANCE.md](PROVENANCE.md)、[LICENSE](LICENSE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
