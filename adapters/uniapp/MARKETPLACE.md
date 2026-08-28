# DCloud 插件市场表单材料

以下内容对应 `Sandrox-Levixel` @VERSION@ 的不可变候选制品。**当前禁止提交：uni-app x 双端真机验收尚未完成。** 验收必须使用下方 SHA-256 对应的同一 ZIP；通过后不得重新打包，只需核对联系人和真机记录。预览截图可选，不要扩大平台声明。

## 基本信息

- 插件 ID：`Sandrox-Levixel`
- 插件名称：Levixel 共享转场图片视频查看器
- 插件类型：UTS API 插件
- 版本：`@VERSION@`
- 原生核心 provenance：`@NATIVE_VERSION@`（打包时按 native release manifest 校验原始 AAR/XCFramework 字节）
- 发行方式：免费，提供源码
- 开源协议：MIT
- 源码仓库：https://github.com/sandroxy/levixel
- 建议关键词：UTS、uni-app、uni-app x、图片预览、视频预览
- 分类：UTS插件 / API插件

一句话简介：

> 为经典 uni-app Android/iOS 提供原生共享转场，并候选扩展至 uni-app x Vapor Android/iOS。

完整简介：

> Levixel 提供共享转场、横向分页、双指缩放、缩放后平移、竖拖关闭、点按关闭和视频播放。UTS 仅承担上下文、JSON 数据和回调转换；Android/iOS 复用同一套已验收的 UniApp 平台 runtime 与正式原生核心，不在 UTS 中重写查看器逻辑。

## 平台声明

- HBuilderX：5.24 及以上
- 经典 uni-app：Vue 2、Vue 3 的 App Vue 页面
- 经典 Android：API 21 及以上
- 经典 iOS：13.0 及以上，仅 arm64 真机
- uni-app x：**仅支持 uni-app x Vapor，要求 HBuilderX 5.24+；不支持 VDOM。**
- uni-app x Android：Android 6 / API 23 及以上
- uni-app x iOS：iOS 15 及以上，仅 arm64 真机
- 不支持：nvue、Web、小程序、HarmonyOS、uni-app x VDOM

uni-app x 当前为候选声明：本地编译与 SDK typecheck 完成后仍需双端真机验收，未完成前不可发布。

## 隐私与权限

- 广告：无
- 运行时权限：无
- 数据采集：插件不采集、统计或向作者服务器上传个人信息
- 网络访问：仅按业务传入的 URL 请求远程图片、视频或封面
- 本地数据：预览缓存只用于展示和共享转场，采用 LRU 与下次启动清理策略
- 第三方 SDK：不包含广告、统计或推广 SDK；原生依赖及许可见包内 `THIRD_PARTY_NOTICES.md`

## 更新日志

> 新增 uni-app x Vapor Android/iOS 候选支持；两端继续复用既有 UniApp runtime 与 Levixel 原生核心；x 分支增加 FileSystemManager 管理的预览保存/清理、失败时的非自有临时路径隔离，以及一次调用完成的 UTS 批量本地路径解析；canonical JS SDK、公开 API 与 `sourceVisibility: 'visible'` 默认策略保持不变。不支持 VDOM、nvue、Web、小程序或 HarmonyOS。

## 上传文件

- 市场 ZIP：`dist/uniapp/levixel-uniapp-@VERSION@.zip`
- SHA-256：`@CHECKSUM@`
- 使用文档：ZIP 根目录的 `readme.md`
- 许可文件：ZIP 内 `LICENSE`、`license.md`、`THIRD_PARTY_NOTICES.md`

## 待人工核对

- 联系 QQ（可选，用于审核沟通）：`________________`
- classic Android 真机型号 / 系统 / 验收日期：`________________`
- classic iOS 真机型号 / 系统 / 验收日期：`________________`
- x Vapor Android 6/API 23+ 真机型号 / 系统 / 验收日期：`________________`
- x Vapor iOS 15+ 真机型号 / 系统 / 验收日期：`________________`
- 可选预览截图：如提供，应使用不含 Probe、耗时等诊断面板的正式效果图，并满足市场当期尺寸与大小限制

真机验收矩阵：首次打开、重复打开、远程加载、失败重试、缓存重开、横向分页、缩放平移、竖拖关闭、点按关闭、系统返回、图片与视频切换、回到 WebView 后源图无末帧闪烁。
