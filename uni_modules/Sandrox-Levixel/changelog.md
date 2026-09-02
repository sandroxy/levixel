# Changelog

## 1.3.0

- 修复 UniApp iOS 合成源锚点因透明父视图被注册表拒绝、导致关闭时退化为淡出的问题，恢复按当前媒体位置执行的共享回场。
- `warmupLevixelItem` 仅记录已解码源图尺寸，不再隐式下载或落盘；点击等待采用短预算，受管预览同时限制单文件大小、总字节数、条目数和空闲时间。
- 修复 Android 长视频拖动进度条后重复触发画面交接、导致封面瞬间闪现的问题；页面重新激活及取消返回手势也不会重复播放封面交接动画。
- 同一次打开请求中的媒体 `id` 必须唯一，Android/iOS 原生运行时与公共 JavaScript 选择器入口会一致拒绝重复值。
- iOS 共享转场改用稳定媒体 `id` 匹配回场源，列表插入、删除或重排后不再依赖旧下标。

## 1.2.0

- 正式支持 HBuilderX 5.24+ 的 App-Android 与 App-iOS uni-app x，仅限 Vapor；x 宿主最低 Android 6 / API 23 与 iOS 15，不支持 VDOM、nvue、Web、小程序或 HarmonyOS。
- 经典 uni-app 与 uni-app x 继续使用同一套公共 JavaScript API 和 Android/iOS UniApp 运行时，并改进本地预览所有权与路径解析。
- 预览保存失败时不再缓存可能被 runtime 复用的非自有临时路径，避免不同媒体错误共享同一缩略图。
- 移除 UTS 为未填写可选属性生成的 `null`；缺失必填字段、未知字段与空字符串仍会被严格拒绝。
- 与 Android/iOS 原生核心及可选 legacy 包统一升级为 1.2.0；原生查看器交互保持 1.1.1 的既有行为。
- 修正 Vapor 可见源图圆角与 native hint 的单位和值，避免 iOS 开关场期间缩略图短暂闪为直角。

## 1.1.1

- 首个可提交 DCloud 插件市场的正式 UTS 版本，支持经典 uni-app Vue 页面 App-Android 与 App-iOS。
- UTS 与 App 原生插件版继续共用同一套 Android/iOS UniApp 运行时和高层 JavaScript API。
- 修复 iOS 横图首次打开处于放大状态，以及慢网 loading 期间缩放出现双层预览的问题。
- iOS 原图交接时保留用户相对缩放倍率与视觉中心；`sourceVisibility` 默认值继续保持 `visible`。
- Android 原生查看器行为保持不变。

## 1.1.0

- 新增面向 DCloud 插件市场与新项目的正式 UTS API 薄桥。
- Android 与 legacy UniModule 共用 `levixel-uniapp-runtime`；UTS 边界仅传 JSON 字符串。
- iOS 与 App 原生插件版共用 `LevixelUniRuntime.framework`，保留既有的加载、源图锚点、转场和关闭时序。
- 高层 SDK 继续共用同一份 JavaScript 实现，`sourceVisibility` 默认值保持 `visible`。
- 第一版仅声明经典 uni-app Vue 页面 App-Android/App-iOS 支持，不声明 uni-app x、nvue、Web 或小程序支持。
