# Changelog

## 1.1.0

- 新增面向 DCloud 插件市场与新项目的正式 UTS API 薄桥。
- Android 与 legacy UniModule 共用 `levixel-uniapp-runtime`；UTS 边界仅传 JSON 字符串。
- iOS 与 legacy DCloud 模块共用 `LevixelUniRuntime.framework`，保留已验收 presenter 的加载、source anchor、转场和关闭时序。
- 高层 SDK 继续复用 canonical JavaScript 实现，`sourceVisibility` 默认值保持 `visible`。
- 第一版仅声明经典 uni-app Vue 页面 App-Android/App-iOS 支持，不声明 uni-app x、nvue、Web 或小程序支持。
