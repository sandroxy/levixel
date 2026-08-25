# Levixel For UniApp

Levixel 的 UniApp 交付包含两条薄桥，但只有一套平台 runtime 和一套 canonical JavaScript SDK：

- `levixel-uniapp-runtime` 与 `LevixelUniRuntime.framework` 持有已经验收的 UniApp 平台行为。
- legacy `UniModule` / ObjC 模块继续服务已有项目与离线集成。
- UTS Android/iOS 只负责上下文、JSON 字符串和回调转换，服务 DCloud 插件市场与新项目。
- 两条桥都调用正式 Levixel AAR/framework；UTS 不实现转场、加载、手势或 `sourceHints` 语义。

正式 UTS 插件源目录是 `uni_modules/Sandrox-Levixel`；本目录保存共享 Android/iOS runtime、legacy bridge、唯一人工维护的 canonical JavaScript SDK 及其测试。`plugin.yaml` 的 `sourceRoot` 指向正式插件目录，不代表 runtime 被复制进 UTS 源码。

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

第一版只支持经典 uni-app Vue 2 / Vue 3 的 Android/iOS App Vue 页面。高层共享转场依赖 WebView DOM selector，因此不声明 nvue 或 uni-app x 支持。

每个渲染源元素必须与 `items` 使用相同的选择器和顺序。为获得确定的共享转场，应先准备每个媒体项，再把返回的本地 `src` 渲染到 HTML 图片中。该文件也会交给原生查看器，避免可点击源图仍等待第二次转场专用下载。批量准备应限制并发；示例宿主使用三个 worker，并传入 `priority: true`。

部分 UniApp runtime 会为不同 `getImageInfo` 请求复用同一个临时路径，因此 SDK 会把远程预览下载到各自独立的受管文件。SDK 保留 DCloud 虚拟路径用于生命周期管理，并在传给原生桥之前解析为原生可读的 `file://` URL。保存的预览采用 LRU 上限，异常终止遗留文件会在下次启动清理。Android CSS 像素通过显式 `rectScale` 转为原生窗口像素；不会为 HTML 源图额外创建隐藏的原生图片视图。

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

`sourceVisibility` 默认值必须保持 `visible`。这是 UniApp 已验收的 WebView 交接策略：HTML 源图留在原生转场下方，以避免关闭末帧出现纹理闪烁。只有页面完整处理 `sourceVisibilityChange` 且在实际 WebView 宿主重新验收后，才应显式传 `hidden`。

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

主打包脚本不依赖 DCloud legacy SDK，只构建共享 runtime 并装入正式原生核心。第三条命令使用 HBuilderX 5.07 自带编译器生成 Kotlin/Swift，随后编译 Kotlin 并对 iOS 代码做 device SDK typecheck。

输出包括：

- `dist/uniapp/levixel-uniapp-<version>.zip`
- `dist/uniapp/levixel-uniapp-<version>.zip.sha256`
- `dist/uniapp/levixel-uniapp-<version>-marketplace.md`

市场 ZIP 的根目录就是插件根目录，直接包含 `package.json` 和 `utssdk/`，以符合 DCloud Web 发布器的格式校验。手动安装候选包时，应将 ZIP 内容解压到宿主工程的 `uni_modules/Sandrox-Levixel/`，不能在 ZIP 内或安装目录中额外套一层同名目录。随后用包含插件的自定义基座、云打包或离线包完成 Android/iOS 真机矩阵。

## 既有 App 原生插件

已有项目仍可使用 `nativeplugins/Sandrox-Levixel` 和原来的 SDK 路径。其候选包单独生成，不是插件市场上传物：

```sh
DCLOUD_ANDROID_UNIAPP_AAR=/absolute/path/to/uniapp-v8-release.aar \
DCLOUD_IOS_SDK_ROOT=/absolute/path/to/DCloud-iOS-SDK \
  ./scripts/package-uniapp-legacy.sh
./scripts/verify-uniapp-legacy.sh
```
