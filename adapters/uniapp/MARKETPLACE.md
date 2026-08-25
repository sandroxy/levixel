# DCloud 插件市场表单材料

以下内容对应 `Sandrox-Levixel` @VERSION@。上传前只需补齐联系人、截图和真机验收日期；不要扩大平台声明。

## 基本信息

- 插件 ID：`Sandrox-Levixel`
- 插件名称：Levixel 共享转场图片视频查看器
- 插件类型：UTS API 插件
- 版本：`@VERSION@`
- 发行方式：免费，提供源码
- 开源协议：MIT
- 源码仓库：https://github.com/sandroxy/levixel
- 建议关键词：UTS、uni-app、图片预览、视频预览、共享转场
- 建议分类：前端组件 / 媒体（提交时以市场当期分类名称为准）

一句话简介：

> 为经典 uni-app Android/iOS 提供原生共享转场图片与视频查看体验。

完整简介：

> Levixel 提供共享转场、横向分页、双指缩放、缩放后平移、竖拖关闭、点按关闭和视频播放。UTS 仅承担上下文、JSON 数据和回调转换；Android/iOS 复用同一套已验收的 UniApp 平台 runtime 与正式原生核心，不在 UTS 中重写查看器逻辑。

## 平台声明

- HBuilderX：5.07 及以上
- 经典 uni-app：Vue 2、Vue 3 的 App Vue 页面
- Android：API 21 及以上
- iOS：13.0 及以上，仅 arm64 真机
- 不支持：nvue、Web、小程序、HarmonyOS、uni-app x

不声明 uni-app x 的原因：高层共享转场依赖 WebView DOM selector 获取源节点几何；uni-app x 需要另一套原生节点几何协议。

## 隐私与权限

- 广告：无
- 运行时权限：无
- 数据采集：插件不采集、统计或向作者服务器上传个人信息
- 网络访问：仅按业务传入的 URL 请求远程图片、视频或封面
- 本地数据：预览缓存只用于展示和共享转场，采用 LRU 与下次启动清理策略
- 第三方 SDK：不包含广告、统计或推广 SDK；原生依赖及许可见包内 `THIRD_PARTY_NOTICES.md`

## 更新日志

> 新增经典 uni-app Android/iOS 的正式 UTS API 薄桥；两端复用既有 UniApp runtime 与 Levixel 原生核心；修复 iOS 横图首次打开处于放大状态及慢网 loading 期间缩放出现双层预览的问题；canonical JS SDK 和 `sourceVisibility: 'visible'` 默认策略保持不变。

## 上传文件

- 市场 ZIP：`dist/uniapp/levixel-uniapp-@VERSION@.zip`
- SHA-256：`@CHECKSUM@`
- 使用文档：ZIP 内 `Sandrox-Levixel/readme.md`
- 许可文件：ZIP 内 `LICENSE`、`license.md`、`THIRD_PARTY_NOTICES.md`

## 待人工补充

- 联系 QQ：`________________`
- Android 真机型号 / 系统 / 验收日期：`________________`
- iOS 真机型号 / 系统 / 验收日期：`________________`
- Android 截图：插件入口、图片查看、视频查看各 1 张
- iOS 截图：插件入口、图片查看、视频查看各 1 张

真机验收矩阵：首次打开、重复打开、远程加载、失败重试、缓存重开、横向分页、缩放平移、竖拖关闭、点按关闭、系统返回、图片与视频切换、回到 WebView 后源图无末帧闪烁。
