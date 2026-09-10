# Levixel

[English](README-EN.md)

Levixel 是一套强调原生手感的共享转场图片与视频查看器，支持横向分页、双指缩放、缩放后平移、竖拖关闭与视频播放。

共享转场以列表中源媒体当前可见的位置、尺寸和圆角为起点，将内容连续展开到全屏；关闭时再返回当前媒体对应的源位置。即使内部需要在缩略图、加载态与原始媒体之间交接，用户看到的仍是一份连续、可直接操控的内容。

<p align="center">
  <img src="docs/assets/levixel-demo.gif" width="400" alt="Levixel 共享转场与分页回场演示">
</p>

交互取向参考 Google Photos 与 iPhone 系统“照片”App 中以媒体为中心的直接操控方式。上述产品仅作为交互参考；Levixel 与其不存在隶属或授权关系，也未使用上述产品的代码。本项目自身的开源衍生来源见[许可证与来源](#许可证与来源)。

## 能力

- 图片与视频混合分页浏览
- 以可见源为锚点的开场与回场共享转场
- 双指缩放、缩放后平移与双击复位
- 图片未放大时竖拖关闭，并支持点按关闭和系统返回
- 缩略图、加载态、原图与视频首帧之间的连续交接
- 图片与视频长按事件，可配置列表或网格操作抽屉
- 带媒体身份的会话与加载事件、失败提示及手动和程序重试
- 为 Android、iOS、HarmonyOS、React Native、UniApp 及受支持的现代 Web 浏览器提供正式发行包

## 支持平台与分发

| 平台 | 推荐渠道 | 接入说明 |
| --- | --- | --- |
| Android | [Maven Central](https://central.sonatype.com/artifact/io.gitee.sandrox/levixel) · `io.gitee.sandrox:levixel` | [Android 指南](native/android/README.md)，提供 AAR 离线镜像 |
| iOS | [Swift Package](https://github.com/sandroxy/levixel) | [iOS 指南](native/ios/README.md)，通过校验和验证的 XCFramework |
| HarmonyOS | [OHPM](https://ohpm.openharmony.cn/#/cn/detail/@sandrox%2Flevixel) · `@sandrox/levixel` | 原生 HAR，同时在 GitHub Releases 提供离线镜像 |
| React Native / Expo | [npm](https://www.npmjs.com/package/@sandrox/levixel) · `@sandrox/levixel` | React Native 组件与随包提供的 Android/iOS 原生运行时 |
| UniApp | [DCloud 插件市场](https://ext.dcloud.net.cn/plugin?id=29394) | 经典 uni-app 与 uni-app x Vapor 的 Android/iOS App |
| Web | [npm](https://www.npmjs.com/package/@sandrox/levixel-web) · `@sandrox/levixel-web` | 无框架依赖的 ESM 浏览器运行时 |

版本历史、校验和与离线制品见 [GitHub Releases](https://github.com/sandroxy/levixel/releases) 和 [CHANGELOG.md](CHANGELOG.md)。各包管理器页面是对应公开渠道可用版本的准确信息源；不同平台的具体能力与宿主要求以对应平台文档为准。

## Android

最低支持 Android API 21。

通过 Maven Central 安装，版本以对应渠道显示的最新稳定版本为准：

```kotlin
dependencies {
    implementation("io.gitee.sandrox:levixel:<version>")
}
```

仓库配置、打开查看器、动态列表源绑定、长按操作与事件控制见 [Android 接入说明](native/android/README.md)。

## iOS

最低支持 iOS 13.0。

在 Xcode 中选择 **File > Add Package Dependencies**，输入：

```text
https://github.com/sandroxy/levixel.git
```

依赖规则推荐选择 **Up to Next Major Version**，并以 [GitHub Releases](https://github.com/sandroxy/levixel/releases) 中显示的最新稳定版本作为最低版本；Xcode 会在同一主版本范围内解析兼容更新。需要完全锁定依赖时选择 **Exact Version**。随后把 `Levixel` 产品链接到 App target。

媒体数据、源图绑定、长按操作与会话控制见 [iOS 接入说明](native/ios/README.md)。Swift Package 会验证下载文件与包清单中的校验和一致。

## HarmonyOS

最低支持 HarmonyOS API 23，当前 HAR 面向 phone 设备。

通过 OHPM 安装当前公开版本：

```sh
ohpm install @sandrox/levixel
```

对应 GitHub Release 同时提供 HAR 与 SHA-256 文件，供离线或手动集成。

组件接口与完整示例见 [HarmonyOS 使用说明](native/harmonyos/levixel/README.md)。

## React Native / Expo

```sh
pnpm add @sandrox/levixel
npx expo prebuild
```

该包同时提供 React Native 集成层和所需的 Android/iOS 原生运行时，无需再单独接入原生核心。动态、分页或虚拟列表使用 `Levixel.Source itemId` 按稳定媒体身份绑定当前已挂载 cell；圆角源在 `Levixel.Source` 自身使用数字型 `borderRadius` 与 `overflow: 'hidden'`，同一份样式同时决定可见裁剪和原生转场几何。组件接口与宿主要求见 [React Native 适配器文档](adapters/react-native/README.md)。

## UniApp

推荐从 [DCloud 插件市场](https://ext.dcloud.net.cn/plugin?id=29394) 安装。市场 UTS 插件支持经典 uni-app Vue 2 / Vue 3 App 页面，以及 uni-app x Vapor 的 Android/iOS App；x 不支持 VDOM。两条路径使用同一套公共 JavaScript API 与平台运行时。动态列表可用 `initialItemId + sourceBindings` 绑定当前已挂载源；回场以源矩形和有效页面视口的真实交集为准，部分可见时共享转场，完全不可见时安全淡出。`sourceVisibility` 默认保持 `visible`，用于避免 WebView/Vapor 源图在关闭交接末帧闪烁。

完整兼容范围、加载态接入和示例见 [UniApp 使用说明](uni_modules/Sandrox-Levixel/readme.md)。对应版本的 GitHub Release 也提供 UTS ZIP 与校验和，供直接下载和离线归档。

选择 App 原生插件工作流的经典 uni-app Android/iOS 项目，可使用 GitHub Release 中单独提供的 `levixel-uniapp-legacy-<version>.zip`。它使用同版本的公共 SDK、平台运行时和原生核心，但不属于 DCloud UTS 市场包，也不支持 uni-app x。

## Web

```sh
pnpm add @sandrox/levixel-web
```

Web 包使用浏览器原生 DOM、Pointer Events、Web Animations API 与媒体元素实现共享转场、分页、缩放、平移、竖拖关闭和视频控制，并支持按稳定 ID 绑定稀疏虚拟列表源。它默认使用 `sourceVisibility: hidden`，不会改变 UniApp 专属的 `visible` 默认值。

已验证的浏览器范围包括 macOS Chrome、macOS Safari、Android Chrome 与 iOS Safari。API、浏览器边界和无障碍行为见 [Web 使用说明](adapters/web/README.md)。

## 源码与发布

本地构建、测试与 SDK 要求见 [DEVELOPMENT.md](DEVELOPMENT.md)。版本签名与各渠道发布流程见 [RELEASING.md](RELEASING.md)。

## 许可证与来源

Levixel 以 MIT License 发布，并包含来源可追溯的 MIT 许可衍生代码。相关来源、许可文本与保留声明见 [PROVENANCE.md](PROVENANCE.md)、[LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
