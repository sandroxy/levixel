# Levixel

[English](README-EN.md)

Levixel 是一套强调原生手感的共享转场图片与视频查看器，支持横向分页、双指缩放、缩放后平移、竖拖关闭与视频播放。

共享转场以列表中源媒体当前可见的位置、尺寸和圆角为起点，将内容连续展开到全屏；关闭时再返回当前媒体对应的源位置。即使内部需要在缩略图、加载态与原始媒体之间交接，用户看到的仍是一份连续、可直接操控的内容。

交互取向参考 Google Photos 与 iPhone 系统“照片”App 中以媒体为中心的直接操控方式。Levixel 是独立实现，与上述产品不存在隶属或授权关系。

## 能力

- 图片与视频混合分页浏览
- 以可见源为锚点的开场与回场共享转场
- 双指缩放、缩放后平移与双击复位
- 贴合状态竖拖关闭、点按关闭和系统返回
- 缩略图、加载态、原图与视频首帧之间的连续交接
- Android、iOS、HarmonyOS、React Native、UniApp 与现代 Web 的正式交付

## 支持平台与分发

| 平台 | 推荐渠道 | 接入说明 |
| --- | --- | --- |
| Android | [Maven Central `io.gitee.sandrox:levixel`](https://central.sonatype.com/artifact/io.gitee.sandrox/levixel) | 原生 AAR，同时在 GitHub Release 提供离线镜像 |
| iOS | Swift Package `https://github.com/sandroxy/levixel.git` | 校验和固定的二进制 XCFramework |
| HarmonyOS | OHPM `@sandrox/levixel` | 原生 HAR，同时在 GitHub Release 提供离线镜像 |
| React Native / Expo | [npm `@sandrox/levixel`](https://www.npmjs.com/package/@sandrox/levixel) | React Native 组件与已验收的 Android/iOS 原生制品 |
| UniApp | [DCloud 插件市场](https://ext.dcloud.net.cn/plugin?id=29394) | 经典 uni-app 与 uni-app x Vapor 的 Android/iOS App |
| Web | [npm `@sandrox/levixel-web`](https://www.npmjs.com/package/@sandrox/levixel-web) | 无框架依赖的 ESM 浏览器运行时 |

版本历史、校验和与离线制品见 [GitHub Releases](https://github.com/sandroxy/levixel/releases) 和 [CHANGELOG.md](CHANGELOG.md)。各包管理器页面是对应公开渠道可用版本的准确信息源；不同平台的具体能力与宿主要求以对应平台文档为准。

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

使用 Maven Central 页面显示的最新稳定版本：

```kotlin
dependencies {
    implementation("io.gitee.sandrox:levixel:<version>")
}
```

当前 Android 核心仍保留经过完整手势验收的 PhotoView 依赖，因此消费者需要保留 JitPack 仓库。

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

选择最新兼容的 `1.x` 版本，然后链接 `Levixel` 产品。

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

Swift Package 会验证下载的 XCFramework 与 `Package.swift` 中记录的 checksum 一致。

## HarmonyOS

通过 OHPM 安装当前公开版本：

```sh
ohpm install @sandrox/levixel
```

对应 GitHub Release 同时提供 HAR 与 SHA-256 文件，供离线或手动集成。公开镜像与 OHPM 制品必须保持字节级一致。

## React Native / Expo

```sh
pnpm add @sandrox/levixel
npx expo prebuild
```

该包包含 React Native 集成层与校验过的 Android/iOS 原生制品，不在消费者项目中复制或重新编译查看器核心。组件接口与宿主要求见 [React Native 适配器文档](adapters/react-native/README.md)。

## UniApp

推荐从 [DCloud 插件市场](https://ext.dcloud.net.cn/plugin?id=29394) 安装。市场 UTS 插件支持经典 uni-app Vue 2 / Vue 3 App 页面，以及 uni-app x Vapor 的 Android/iOS App；x 不支持 VDOM。两条路径使用同一套公共 JavaScript API 与平台运行时，`sourceVisibility` 默认保持 `visible`，以保留已经验收的源图交接手感。

完整兼容范围、加载态接入和示例见 [UniApp 使用说明](uni_modules/Sandrox-Levixel/readme.md)。匹配版本的 GitHub Release 也提供 UTS ZIP 与校验和，供直接下载和离线归档。

选择 App 原生插件工作流的经典 uni-app Android/iOS 项目，可使用 GitHub Release 中单独提供的 `levixel-uniapp-legacy-<version>.zip`。它使用同版本的公共 SDK、平台运行时和原生核心，但不属于 DCloud UTS 市场包，也不支持 uni-app x。

## Web

```sh
pnpm add @sandrox/levixel-web
```

Web 包使用浏览器原生 DOM、Pointer Events、Web Animations API 与媒体元素实现共享转场、分页、缩放、平移、竖拖关闭和视频控制。它默认使用 `sourceVisibility: hidden`，不会改变 UniApp 专属的 `visible` 默认值。

公开交互范围覆盖 macOS Chrome、macOS Safari、Android Chrome 与 iOS Safari。API、浏览器边界和无障碍行为见 [Web 使用说明](adapters/web/README.md)。

## 源码与发布

```text
levixel/
├── native/          # Android、iOS、HarmonyOS 原生核心
├── adapters/        # React Native、UniApp 与 Web 适配层
├── uni_modules/     # DCloud 市场 UTS 插件源目录
├── contract/        # 跨平台公共契约
├── packaging/       # 平台制品模板
├── scripts/         # 构建、制品检查与发布工具
├── schema/          # 插件清单 Schema
└── plugin.yaml      # 版本、能力与交付目标的机器可读清单
```

本地构建、测试与 SDK 要求见 [DEVELOPMENT.md](DEVELOPMENT.md)。不可变候选、签名与渠道发布规则见 [RELEASING.md](RELEASING.md)。

## 许可证与来源

Levixel 以 MIT License 发布。当前实现经过大量重构和跨平台打磨，但仍保留可追溯的 MIT 衍生代码来源。完整审计见 [PROVENANCE.md](PROVENANCE.md)、[LICENSE](LICENSE) 与 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
