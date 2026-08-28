# Changelog

## 1.2.0（待真机验收）

- 候选支持 HBuilderX 5.24+ 的 App-Android 与 App-iOS，仅限 Vapor；x 宿主最低 Android 6 / API 23 与 iOS 15，不支持 VDOM、nvue、Web、小程序或 HarmonyOS。
- 继续复用 canonical JavaScript SDK 与既有 Android/iOS UniApp runtime；仅新增 FileSystemManager 预览所有权管理和一次调用完成的 UTS 批量本地路径薄桥。
- 预览保存失败时不再缓存可能被 runtime 复用的非自有临时路径，避免不同媒体错误共享同一缩略图。
- 在 UTS JavaScript 边界移除具名类型为未填写可选属性生成的 `null`；必填字段、未知字段与空字符串仍按 canonical 协议拒绝。
- 版本独立升级为 1.2.0，同时继续嵌入并校验已发布的 1.1.1 Android/iOS 原生核心；legacy 包和其他原生产品仍为 1.1.1。
- 已加入 classic/x 编译、官方 uni-app x SDK typecheck 与独立 ZIP 消费宿主；双端真机验收完成前仍不可发布。

## 1.1.1

- 首个可提交 DCloud 插件市场的正式 UTS 版本，支持经典 uni-app Vue 页面 App-Android 与 App-iOS。
- UTS 与 legacy 桥继续共用同一套 Android/iOS UniApp runtime，高层接口继续复用 canonical JavaScript SDK。
- 修复 iOS 横图首次打开处于放大状态，以及慢网 loading 期间缩放出现双层预览的问题。
- iOS 原图交接时保留用户相对缩放倍率与视觉中心；`sourceVisibility` 默认值继续保持 `visible`。
- Android 原生查看器行为保持不变。

## 1.1.0

- 新增面向 DCloud 插件市场与新项目的正式 UTS API 薄桥。
- Android 与 legacy UniModule 共用 `levixel-uniapp-runtime`；UTS 边界仅传 JSON 字符串。
- iOS 与 legacy DCloud 模块共用 `LevixelUniRuntime.framework`，保留已验收 presenter 的加载、source anchor、转场和关闭时序。
- 高层 SDK 继续复用 canonical JavaScript 实现，`sourceVisibility` 默认值保持 `visible`。
- 第一版仅声明经典 uni-app Vue 页面 App-Android/App-iOS 支持，不声明 uni-app x、nvue、Web 或小程序支持。
