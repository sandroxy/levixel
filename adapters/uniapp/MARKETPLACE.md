# DCloud 插件市场表单材料

由打包脚本生成，供 HBuilderX 发布表单参考。用户使用说明为包内 `readme.md`。

## 基本信息

- 插件 ID：`Sandrox-Levixel`
- 插件名称：Levixel 共享转场图片视频查看器
- 插件类型：UTS API 插件
- 版本：`@VERSION@`
- 原生核心版本：`@NATIVE_VERSION@`
- 发行方式：免费，提供源码
- 开源协议：MIT
- 源码仓库：https://github.com/sandroxy/levixel
- 关键词：@KEYWORDS@
- 分类：UTS插件 / API插件

一句话简介：

> @DESCRIPTION@

## 平台声明

- HBuilderX：`@HBUILDERX_MIN@` 及以上
- 经典 uni-app：Vue 2、Vue 3 的 App Vue 页面
- 经典 Android 市场声明：API `@CLASSIC_ANDROID_MIN@` 及以上
- 经典 iOS 市场声明：`@CLASSIC_IOS_MIN@` 及以上，仅 arm64 真机
- uni-app x：仅支持 Vapor，不支持 VDOM
- uni-app x Android：API `@X_ANDROID_MIN@` 及以上
- uni-app x iOS：`@X_IOS_MIN@` 及以上，仅 arm64 真机
- 不支持：nvue、UniApp Web、小程序、HarmonyOS、uni-app x VDOM

HBuilderX 表单要求 classic/x 共用最低系统声明；各宿主的实际运行要求见 `readme.md`。发布版本与各平台的“插件版本”字段分别按其含义填写，不因发布新版本而机械覆盖历史平台声明。

## 隐私与权限

- 广告：无
- 运行时权限：无
- 数据采集：插件不采集、统计或向作者服务器上传个人信息
- 网络访问：仅按业务传入的 URL 请求远程图片、视频或封面
- 本地数据：预览缓存只用于展示和共享转场，采用 LRU 与下次启动清理策略
- 第三方 SDK：不包含广告、统计或推广 SDK；原生依赖及许可见包内 `THIRD_PARTY_NOTICES.md`

## 更新日志

@CHANGELOG@

## 发布入口与文件

在 HBuilderX 打开消费此 ZIP 的现有生成工程，右键 `uni_modules/Sandrox-Levixel`，选择“发布到插件市场”。不要在网页上传 ZIP，也不要从源码工作区重新打包。确认当前发布版号及必填字段；版本正确不代表所有字段已经带出。

- 市场 ZIP：`dist/uniapp/levixel-uniapp-@VERSION@.zip`
- SHA-256：`@CHECKSUM@`
- 使用文档：ZIP 根目录的 `readme.md`
- 许可文件：ZIP 内 `LICENSE`、`license.md`、`THIRD_PARTY_NOTICES.md`

联系方式和可选截图按市场表单实际需要填写，不另填设备或逐场景验收表。HBuilderX 会回写发布元数据和更新日志日期；生成工程不是长期维护这些字段的来源。
