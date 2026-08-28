# Levixel for UniApp

本文件面向 Levixel 维护者，记录 UniApp 的共享运行时、桥接边界、构建与验收规则。业务接入、媒体字段和可复制示例见 [UniApp 使用说明](../../uni_modules/Sandrox-Levixel/readme.md)。

Levixel 的 UniApp 交付包含两条薄桥，但只有一套平台 runtime 和一套 canonical JavaScript SDK：

- `levixel-uniapp-runtime` 与 `LevixelUniRuntime.framework` 持有两条桥共用的 UniApp 平台行为。
- legacy `UniModule` / ObjC 模块作为可选交付形式，服务选择 App 原生插件工作流的新老项目与离线集成。
- UTS Android/iOS 只负责上下文、JSON 字符串和回调转换，是 DCloud 插件市场与新项目的默认推荐方案。
- 两条桥都调用正式 Levixel AAR/framework；UTS 不实现转场、加载、手势或 `sourceHints` 语义。

正式 UTS 插件源目录是 `uni_modules/Sandrox-Levixel`；本目录保存共享 Android/iOS runtime、legacy bridge、唯一人工维护的 canonical JavaScript SDK 及其测试。`plugin.yaml` 的 `sourceRoot` 指向正式插件目录，不代表 runtime 被复制进 UTS 源码。

## uni-app x 支持范围

**uni-app x 仅支持 Vapor，不支持 VDOM。** 精确的 HBuilderX、经典 App 与 x App 平台下限由 `uni_modules/Sandrox-Levixel/package.json` 和 `plugin.yaml` 维护，并由用户文档与市场材料从元数据校验或生成。UniApp 交付只覆盖经典 Vue 2 / Vue 3 App Vue 和 uni-app x Vapor 的 Android/iOS；不支持 nvue、HarmonyOS、Web 或小程序。

每个候选版本都必须从 `plugin.yaml` 解析自身版本及 `native-release-version`，并嵌入对应原生发布清单记录的精确 AAR/XCFramework。classic/x 编译、官方 SDK typecheck、ZIP staging、共享转场、坐标、快速开关、视频与返回源图都属于正式验收矩阵；发布时必须始终使用同一候选 SHA-256 完成制品与真机闭环。

## UTS 安装与公共 SDK

将市场插件或候选 ZIP 安装到项目的 `uni_modules/Sandrox-Levixel`，然后从高层 SDK 引入：

```js
import {
  openLevixel,
  closeLevixel,
  onLevixelEvent,
  prepareLevixelItem,
  warmupLevixelItem,
  openLevixelFromSelector,
} from '@/uni_modules/Sandrox-Levixel/js_sdk/index.js'
```

每个渲染源元素必须与 `items` 使用相同的选择器和顺序。为获得确定的共享转场，应先准备每个媒体项，再把返回的本地 `src` 渲染到 HTML 图片中。该文件也会交给原生查看器，避免可点击源图仍等待第二次转场专用下载。批量准备应限制并发；示例宿主使用三个 worker，并传入 `priority: true`。

部分 UniApp runtime 会为不同 `getImageInfo` 请求复用同一个临时路径，因此 SDK 会把远程预览保存为各自独立的受管文件。经典分支沿用 `uni.saveFile`；x 分支使用 `uni.getFileSystemManager().saveFile` / `removeSavedFile`。保存失败时只保留可靠的宽高信息，不缓存、传递或清理该非自有临时路径；查看器仍可按正式媒体 URL 进入原生加载态，避免跨媒体复用临时路径造成错图。JS→UTS transport 会收集并去重 `url`、`thumbnailUrl`、`posterUrl` 中的本地路径，再通过一次批量调用解析；HTTP(S)、`data:` 和已经是 `file:` 的 URL 原样保留。Android 对代码包 `static/` 与 `uni_modules/<id>/static/` 资源使用 `UTSAndroid.getResourcePath`，其余本地路径使用 `convert2AbsFullPath`；iOS 使用 `UTSiOS.convert2AbsFullPath`。单项解析异常会回退原值，且 native `open` 始终只调用一次。

保存的预览采用 LRU 上限，异常终止遗留文件会在下次启动清理。Android CSS 像素通过显式 `rectScale` 转为原生窗口像素；不会为 HTML/Vapor 源图额外创建隐藏的原生图片视图。

```js
const prepared = await prepareLevixelItem(item, { priority: true })
if (prepared)
  previewSources[item.id] = prepared.src

// 在本地 image 的 load 回调中调用，记录源图已经完成解码。
warmupLevixelItem(item, loadEvent)

await openLevixelFromSelector({
  items,
  index,
  sourceSelector: '.levixel-source',
  sourceStyles: items.map(() => ({ objectFit: 'cover', cornerRadius: 6 })),
})
```

在 uni-app x App Vapor 中，可见源元素应使用与上例数值一致的 `border-radius: 6px`。当前 Vapor 的 `border-radius` 不支持 `rpx`；使用 `rpx` 会让源视图在转场期间失去圆角，而 native hint 仍按数值插值，形成短暂的直角闪变。经典 uni-app 的 CSS 处理不受此限制。

`sourceVisibility` 默认值必须保持 `visible`。WebView/Vapor 交接策略会让页面源图留在原生转场下方，以避免关闭末帧出现纹理闪烁。显式改为 `hidden` 前，宿主必须完整处理 `sourceVisibilityChange`，并重新执行适用平台的开关场与回源回归。

## iOS 事件订阅生命周期

DCloud iOS UTS 在当前最低版本内提供启动、前后台等 App hook，但没有与 classic uni-app JS runtime 销毁对应的可靠 hook。切后台、页面卸载或普通关闭都不等价于 runtime 销毁，因此桥接层不会在这些时机错误清理全局订阅。

iOS UTS 不再另存一份事件回调，而是把回调交给 `LevixelUniRuntime` 的单槽 relay。每次注册都在主线程串行替换并释放旧回调；open/close 不创建 listener，事件 JSON 也不经过 relay 改写。JS runtime 重建并重新注册时会替换旧槽位。没有重新注册信号时不会伪造 detach；这是 DCloud 当前生命周期边界，而不是页面 unload 或前后台事件可以安全推断的状态。

## 构建与校验 UTS 市场包

`adapters/uniapp/js_sdk/index.js` 是 canonical SDK 的唯一人工维护源。`uni_modules/Sandrox-Levixel/js_sdk/canonical.js` 是纳入源码树的受控生成文件；修改 canonical SDK 后运行：

```sh
./scripts/sync-uniapp-canonical-js.sh
```

不要直接编辑生成文件。打包、发布元数据检查和 ZIP 校验都会做字节级比较，漂移时直接失败。

```sh
./scripts/package-uniapp.sh
./scripts/verify-uniapp.sh
./scripts/verify-uniapp-uts-compiler.sh
```

主打包脚本不依赖 DCloud legacy SDK，只构建共享 runtime 并装入正式原生核心。正式候选要求干净工作区，并拒绝静默覆盖同版本的不同 ZIP、SHA-256 或市场材料；`--allow-dirty` 只用于本地流水线演练，明确放弃旧候选后才可加 `--replace`，且替换后必须重新完成全部制品验收。第三条命令要求使用插件元数据声明的 HBuilderX 最低版本或更高版本，分别以 classic 与 x 模式生成 Kotlin/Swift；classic 输出继续做原有编译检查，x 输出还必须对 DCloud 官方 Android/iOS uni-app x SDK typecheck。SDK 根目录通过 `DCLOUD_UNIAPP_X_ANDROID_SDK_ROOT` 与 `DCLOUD_UNIAPP_X_IOS_SDK_ROOT` 传入，仓库不保存机器绝对路径。

输出包括：

- `dist/uniapp/levixel-uniapp-<version>.zip`
- `dist/uniapp/levixel-uniapp-<version>.zip.sha256`
- `dist/uniapp/levixel-uniapp-<version>-marketplace.md`

市场表单材料由 `adapters/uniapp/MARKETPLACE.md`、插件 `package.json` 和对应版本的 `changelog.md` 自动渲染。模板只保存稳定表单结构，兼容下限、版本、原生 provenance、更新日志和 SHA-256 均不得重复手写到模板或发布手册。

市场 ZIP 的根目录就是插件根目录，直接包含 `package.json` 和 `utssdk/`，以符合 DCloud Web 发布器的格式校验。手动安装候选包时，应将 ZIP 内容解压到宿主工程的 `uni_modules/Sandrox-Levixel/`，不能在 ZIP 内或安装目录中额外套一层同名目录。随后用包含插件的自定义基座、云打包或离线包完成 Android/iOS 真机矩阵。只有从干净 release commit 生成、完成制品校验且保持验收 SHA-256 不变的 ZIP 才能上传市场或附加到公开 Release。

正式版本还可以把同一份已验收 ZIP 及其 SHA-256 文件附加到对应 GitHub Release，作为无需登录的直接下载镜像。该镜像必须复用上传 DCloud 的原文件，不能从 `master` 或 release tag 重新构建。DCloud 市场仍是新项目的首选安装渠道。

## App 原生插件版（可选）

不希望采用 UTS、而选择 App 原生插件工作流的经典 uni-app Android/iOS 项目，无论是新接入还是已有项目，都可从对应 [GitHub Release](https://github.com/sandroxy/levixel/releases) 下载 `levixel-uniapp-legacy-<version>.zip`。该包不是旧查看器：它使用与 UTS 包同版本的平台 runtime、canonical JavaScript SDK 和原生核心，只是桥接与集成形式不同。

解压后应得到 `nativeplugins/Sandrox-Levixel/`，并使用包内原有的 SDK 路径。该交付需要自定义调试基座或离线打包，不支持 uni-app x，也不能作为当前 DCloud 插件市场的 UTS 包上传。UTS 仍是新项目的默认推荐方案，但不是唯一可用方案。

维护者需要重新生成候选包时，使用：

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
DCLOUD_IOS_SDK_ROOT=/absolute/path/to/DCloud-iOS-SDK \
  ./scripts/package-uniapp-legacy.sh
./scripts/verify-uniapp-legacy.sh
```

只有精确的 legacy ZIP 分别通过 Android/iOS 离线宿主烟测后，才可把 ZIP 与 SHA-256 文件附加到对应 GitHub Release。公开包不得包含构建 bridge 时使用的 DCloud Android AAR 或 iOS SDK；消费者仍应通过自己的 HBuilderX/离线 SDK 环境完成集成。
