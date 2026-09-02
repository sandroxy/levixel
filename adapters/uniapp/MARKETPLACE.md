# DCloud 插件市场表单材料

本文件是由打包脚本渲染的发布表单，不是用户使用说明。版本、原生 provenance、兼容范围、更新日志和 SHA-256 必须来自机器清单、插件元数据与对应 changelog，禁止在模板中手写当前发布值。

## 基本信息

- 插件 ID：`Sandrox-Levixel`
- 插件名称：Levixel 共享转场图片视频查看器
- 插件类型：UTS API 插件
- 版本：`@VERSION@`
- 原生核心版本：`@NATIVE_VERSION@`
- 发行方式：免费，提供源码
- 开源协议：MIT
- 源码仓库：https://github.com/sandroxy/levixel
- 建议关键词：UTS、uni-app、uni-app x、图片预览、视频预览
- 分类：UTS插件 / API插件

一句话简介：

> 为经典 uni-app 与 uni-app x Vapor Android/iOS App 提供原生共享转场图片与视频浏览。

完整简介：

> Levixel 以列表中源媒体当前可见的位置、尺寸和圆角为起点，将内容连续展开到原生全屏查看器，并在关闭时返回对应源位置。支持图片与视频分页、双指缩放、缩放后平移、图片未放大时竖拖关闭、点按关闭和视频播放；动态分页与虚拟列表可按稳定媒体 ID 绑定当前已挂载源。

## 平台声明

- HBuilderX：`@HBUILDERX_MIN@` 及以上
- 经典 uni-app：Vue 2、Vue 3 的 App Vue 页面
- 经典 Android：API `@CLASSIC_ANDROID_MIN@` 及以上
- 经典 iOS：`@CLASSIC_IOS_MIN@` 及以上，仅 arm64 真机
- uni-app x：仅支持 Vapor，不支持 VDOM
- uni-app x Android：API `@X_ANDROID_MIN@` 及以上
- uni-app x iOS：`@X_IOS_MIN@` 及以上，仅 arm64 真机
- 不支持：nvue、UniApp Web、小程序、HarmonyOS、uni-app x VDOM

发布前必须确认对应候选已经完成 classic/x 编译、官方 uni-app x SDK typecheck、独立 ZIP 消费宿主和适用平台的 Android/iOS 真机验收。

## 隐私与权限

- 广告：无
- 运行时权限：无
- 数据采集：插件不采集、统计或向作者服务器上传个人信息
- 网络访问：仅按业务传入的 URL 请求远程图片、视频或封面
- 本地数据：预览缓存只用于展示和共享转场，采用 LRU 与下次启动清理策略
- 第三方 SDK：不包含广告、统计或推广 SDK；原生依赖及许可见包内 `THIRD_PARTY_NOTICES.md`

## 更新日志

@CHANGELOG@

## 上传文件

- 市场 ZIP：`dist/uniapp/levixel-uniapp-@VERSION@.zip`
- SHA-256：`@CHECKSUM@`
- 使用文档：ZIP 根目录的 `readme.md`
- 许可文件：ZIP 内 `LICENSE`、`license.md`、`THIRD_PARTY_NOTICES.md`

## 待人工核对

- 联系 QQ（可选，用于审核沟通）：`________________`
- classic Android 真机型号 / 系统 / 验收日期：`________________`
- classic iOS 真机型号 / 系统 / 验收日期：`________________`
- x Vapor Android 真机型号 / 系统 / 验收日期：`________________`
- x Vapor iOS 真机型号 / 系统 / 验收日期：`________________`
- 可选预览截图：使用不含 Probe、耗时等诊断面板的真实正式效果图，并满足市场当期尺寸与大小限制

真机验收矩阵：首次打开、重复打开、远程加载、失败重试、缓存重开、横向分页、缩放平移、竖拖关闭、点按关闭、系统返回、图片与视频切换、回到源位置、源图末帧交接、向前插入历史数据、向后追加分页数据、稀疏虚拟列表，以及自定义 cell 组件查询范围。
