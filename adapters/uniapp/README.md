# UniApp implementation

本文件面向 Levixel 维护者，说明共享运行时与桥接边界。业务接入、媒体字段、按钮、事件及经典/x 示例由 [UniApp 使用说明](../../uni_modules/Sandrox-Levixel/readme.md) 统一维护；构建命令与 SDK 要求见 [DEVELOPMENT.md](../../DEVELOPMENT.md#uniapp)，制品生成、校验和发布见 [RELEASING.md](../../RELEASING.md#uniapp--dcloud-uts-plugin)。

## 代码归属

- `uni_modules/Sandrox-Levixel` 保存市场 UTS 插件入口和公共接入文档。
- `levixel-uniapp-runtime` 与 `LevixelUniRuntime.framework` 持有 UTS 和 legacy 两条桥共用的平台行为，调用 Levixel 原生核心。
- legacy `UniModule` / ObjC 模块服务 App 原生插件工作流和离线集成。
- UTS 只负责上下文、JSON 字符串、回调与本地路径转换；转场、加载、手势和源几何由共享 runtime 与原生核心处理。
- `adapters/uniapp/js_sdk/index.js` 是唯一人工维护的 canonical SDK。`uni_modules/Sandrox-Levixel/js_sdk/canonical.js` 是受控生成副本；修改后运行 `scripts/sync-uniapp-canonical-js.sh`，不要直接编辑副本。

兼容范围和平台下限以插件元数据为准。构建工具应据此校验公共指南，避免在维护说明中另存一份数值。

## 来源、预览与路径

SDK 按稳定媒体 ID 将稀疏、乱序源绑定转换为与打开快照等长的 `sourceHints`。平台运行时以源矩形与有效页面视口的真实交集判断回场；完全不可见或已卸载的源使用淡出，不回到同下标的其他媒体。

一些 UniApp runtime 会复用 `getImageInfo` 临时路径。远程预览因此保存为各自独立的受管文件：经典分支使用 `uni.saveFile`，x 使用 `uni.getFileSystemManager().saveFile` / `removeSavedFile`。保存失败只保留尺寸，不缓存、传递或清理非自有路径。受管预览按 LRU、单文件与总大小、条目数、空闲时间和下次启动清理管理。

JS→UTS transport 去重媒体及按钮图标的本地路径后批量解析。Android 代码包 `static/` 与 `uni_modules/<id>/static/` 使用 `UTSAndroid.getResourcePath`，其余本地路径使用 `convert2AbsFullPath`；iOS 使用 `UTSiOS.convert2AbsFullPath`。远程 URL 原样保留。关闭或更新的打开请求取消旧测量与解析结果，避免延迟结果重新打开查看器。

Android 将 CSS 像素通过 `rectScale` 转为原生窗口像素。iOS 使用不可见的合成源锚点；页面源保持在原生转场下方，不另绘一份覆盖页面的源图。默认 `sourceVisibility: visible` 的交接行为由公共指南说明。

## 会话与事件

每次打开持有媒体和按钮回调快照。公共事件带有会话与媒体身份；适配层只传输事件，不依据宿主更新后的数组重新解释旧会话下标。关闭 Promise 在原生退场完成后结束，重试保留原会话。

iOS UTS 的事件回调保存在 `LevixelUniRuntime` 单槽 relay 中，注册时在主线程替换并释放旧回调。open/close 不创建 listener，relay 不改写 JSON。页面卸载与切后台不等价于 JS runtime 销毁，不能据此清理全局订阅；runtime 重建后重新注册会替换旧槽位。

## 交付边界

UTS 和 legacy 制品都使用发布清单指定的原生核心。前者面向经典 uni-app 与 uni-app x Vapor，后者面向经典 App 原生插件工作流；不得在制品中重新嵌入另一套查看器源码，也不得分发用于编译桥接的 DCloud SDK。

市场表单材料由 [MARKETPLACE.md](MARKETPLACE.md)、插件元数据和更新日志生成。该模板只维护表单结构，兼容数值、版本、校验和和更新内容均由生成工具填入。公开使用文档由 `readme.md` 提供，不维护第二份手工副本。
