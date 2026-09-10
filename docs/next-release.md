# Levixel 1.4.0 维护者说明

本文件记录尚未发布的接口草案、实现约定和验证入口，供维护者推进各平台对齐。业务接入已发布包应从 [README](../README.md) 开始；发布状态以公开 tag 和 Release 为准。

跨平台约定不代表各端已经完成设备验收。源码检查与消费宿主的交互验证分别记录，发布流程见 [RELEASING.md](../RELEASING.md)。

## 本次范围

- 图片和视频长按事件，既可仅响应事件，也可配置内置操作抽屉。
- 抽屉由查看器持有：Android 使用 Material BottomSheetDialog，iOS 15 及以上使用 UIKit 系统 Sheet（iOS 13–14 使用自定义 UIKit 转场），HarmonyOS 使用原生 overlay sheet，Web 位于查看器的 Shadow DOM 内。接入方无需调整宿主页层级。
- 任意业务按钮、显式列表/网格布局、分组和超高内容滚动、图标和两行文字、禁用/危险操作样式、取消和安全区。抽屉使用独立浅色配色，画廊的 `theme` 继续控制媒体背景；原生 iOS/Android 内容底色为 `#DEDEDE`，网格按钮字号 12、列表和取消字号 16（iOS 为 pt，Android 为 sp），跟随系统字体缩放，系统抽屉负责形态和转场。
- 打开、切页、关闭、加载成功/失败和按钮选择事件；失败提示及手动重试。
- React Native 的 `ref.open(itemId)`、`ref.close()`、`ref.retry()`；不要求目标缩略图挂载。
- HarmonyOS 双指缩放、放大后平移及与翻页/竖拖关闭/长按之间的手势协调。

点按关闭仍采用原有行为。插件不实现下载、保存、分享、权限申请或任意业务内容插槽。

## 按钮配置

JavaScript 接口在 `openLevixel` / `openLevixelFromSelector` 的 options 中增加 `actions`、`actionLayout` 和 `actionListIcons`，React Native 在 `<Levixel>` 上提供同名 prop。

```ts
const actions = [
  { id: 'inspect', label: '查看详情', group: 'tools',
    onPress: context => showDetails(context.itemId) },
  { id: 'bookmark', label: '收藏', icon: iconUri, group: 'tools',
    onPress: context => bookmark(context.itemId) },
  { id: 'remove', label: '移除', group: 'manage', destructive: true,
    onPress: context => confirmRemoval(context.itemId) },
];
await openLevixel({ items, actions });
```

| 字段 | 含义 |
| --- | --- |
| `id` | 本次配置内唯一的非空字符串，业务自行命名 |
| `label` | 非空文字，显示最多两行，完整文字用于无障碍名称 |
| `icon?` | 图片 URI；列表可省略，网格每项必传。React Native 的静态资源需先解析成 URI |
| `group?` | 列表中的分组；网格中同组按钮位于同一横向滚动行。组与按钮按首次出现顺序排列；省略归入默认组 |
| `disabled?` | 默认 false，禁用项不触发业务回调 |
| `destructive?` | 默认 false，仅表示危险操作样式，不代替业务确认 |
| `onPress?` | 操作回调；JavaScript 接收操作上下文，原生接口接收事件对象。也可统一处理 `action` 事件 |

布局由接入方明确配置，与按钮数量无关：

| 打开配置 | 默认值 | 行为 |
| --- | --- | --- |
| `actionLayout` | `'list'` | `'list'` 为整行操作列表，`'grid'` 为图标网格；不会按数量自动切换 |
| `actionListIcons` | `false` | 仅控制列表图标；即使传了图标，默认也不显示或加载。设为 true 后显示已有图标，缺失项保留对齐空位 |

列表支持 1 个或多个无图标操作；网格也支持仅 1 个操作，但每项必须提供 `icon`，配置缺失会在打开前报错。网格始终显示图标，忽略列表图标开关。内容超高时纵向滚动，取消按钮保持可见。图标加载失败显示统一的中性占位，文字和点击能力仍保留，不根据标签生成首字图标。

```ts
// 操作数量不会改变列表布局，图标默认隐藏。
await openLevixel({ items, actions, actionLayout: 'list' });
// 单个操作也可以明确选择网格。
await openLevixel({ items, actionLayout: 'grid', actions: [
  { id: 'inspect', label: '查看详情', icon: iconUri, onPress: inspect },
] });
// 列表显示接入方提供的图标。
await openLevixel({ items, actions, actionListIcons: true });
```

数组长度不设业务上限。不传或传空数组时，长按只派发 `longPress`，不显示抽屉。图片/视频均可长按，视频控制按钮和失败重试按钮不会触发长按。拖动或多指操作会取消当前长按识别。

选择按钮先关闭抽屉，再通知业务；查看器继续保持打开。取消、点遮罩、系统 Back/Web Escape 只关闭抽屉，下一次 Back/Escape 才关闭查看器。程序调用 `close` 会关闭整个查看器。回调可以自行保存、展示业务页面，或者调用 close；若同时配置 `onPress` 和监听 `action`，两者都会收到通知，业务应只选一处执行副作用。

每次打开复制媒体和按钮配置。回调的 `index` 属于打开时的媒体数组；异步业务请使用 `itemId` 与业务数据关联，勿用更新后的数组下标查找旧会话图片。更新配置需要下次打开才生效。

## 事件与重试

JavaScript 事件保持 `{ type, payload, time }` 结构。公共媒体上下文：`{ sessionId, galleryId, index, itemId, mediaType }`。`sessionId` 标识一次打开；`galleryId` 用于画廊/来源关联，各平台未指定画廊时可自动生成。原生 iOS 未提供稳定媒体 ID 的旧 data source 以打开时的下标字符串作为 `itemId`，动态列表应使用带 ID 的 data source。

| 事件 | 时机 / 附加字段 |
| --- | --- |
| `opened` | 打开转场完成，查看器可交互 |
| `longPress` | 长按被识别，自动展示抽屉之前 |
| `indexChange` | 当前页变化；保留 `currentIndex`，新增媒体上下文 |
| `mediaLoad` | 图片解码完成或视频首帧就绪，缩略图/占位图不算成功 |
| `mediaError` | 加载失败，附加 `code: 'LOAD_FAILED'` 和 `message` |
| `action` | 抽屉已移除，附加 `actionId` |
| `dismiss` | 会话结束，包含最后当前页上下文；被后续 open 替换也会结束旧会话 |

Android/iOS 保留打开时的首次 `indexChange` 通知（在 `opened` 前）。

`ready`（Web/UniApp 的事件通道就绪）和既有来源显隐事件保留。`ready` 不表示查看器已打开。相邻页预加载可能在 `opened` 之前或当前页事件之间派发媒体事件，必须根据事件的 `itemId` 判断对应媒体，不能假定都是当前页。未真正打开就被取消的请求会结束其 Promise，不承诺派发 `opened`。

失败后显示重试按钮；重试仅重载当前失败媒体，不创建新会话。加载中、无失败页或查看器已关闭时不重复发起请求。

- Web/UniApp：`await retryLevixel()` → `{ retried: boolean }`。
- React Native：`await ref.current.retry()` → `boolean`；`await ref.current.close()` 在查看器关闭完成后返回。
- Android：`overlay.retry()` → `boolean`；`overlay.requestClose()`；宿主 Back 应调用 `overlay.handleBack()`。
- iOS：`session.retry()` → `Bool`（主线程）；`session.close()`，可传 completion 等待关闭完成。自动点击接入可从 `configuration.onSession` 接收 session。
- HarmonyOS：`controller.retry()` → `boolean`、`controller.close()`、`controller.handleBack()`；宿主 `onBackPress()` 返回 `controller.handleBack()`。

## Android / iOS

Android 的新构造重载在 `galleryId` 后接受 `List<LevixelAction>`（完整重载包含 `sourceHints`）。需要选择布局时，随后传入 `LevixelActionLayout.LIST` / `.GRID` 和 `boolean actionListIcons`；旧重载默认列表且不显示列表图标。每项可带 `LevixelAction.Callback`；`Listener.onViewerEvent(LevixelViewerEvent)` 接收事件，`event.payload` 是不可修改的上下文 Map。旧构造函数和 listener 继续可用。

iOS 通过 `LevixelViewerConfiguration.actions` / `.actionLayout`（`.list` / `.grid`，默认 `.list`）/ `.actionListIcons`（默认 false）/ `.onEvent` / `.onSession` 配置。`LevixelAction` 原生回调接收 `LevixelViewerEvent`，媒体上下文为 `event.context`，序列化值为 `event.dictionary`。原有 `onIndexChange` / `onDismiss` 保留。

## React Native 接入

`<Levixel>` 通过 `actions`、`actionLayout`、`actionListIcons` 和 `onEvent` 接入相同的原生抽屉。`LevixelRef` 提供 `open(itemId)`、`close()` 和 `retry()`；目标缩略图未挂载时也可以打开。

```tsx
import { useRef, type ReactNode } from 'react';
import { Button } from 'react-native';
import { Levixel, type LevixelMediaItem, type LevixelRef } from '@sandrox/levixel';

export function Gallery({ items, children }: {
  items: readonly LevixelMediaItem[];
  children: ReactNode;
}) {
  const viewer = useRef<LevixelRef>(null);
  return (
    <Levixel
      ref={viewer}
      items={items}
      actionLayout="list"
      actions={[
        { id: 'inspect', label: '查看详情', group: 'tools',
          onPress: context => console.log(context.itemId) },
      ]}
      onEvent={event => console.log(event.type, event.payload.itemId)}
    >
      <Button title="打开首项" disabled={items.length === 0} onPress={() => {
        if (items.length > 0) void viewer.current?.open(items[0].id);
      }} />
      {children}
    </Levixel>
  );
}
```

`children` 是宿主已有的媒体列表；源绑定方式沿用 [React Native 接入说明](../adapters/react-native/README.md)。需要图标时传 URI，打包静态图片先使用 `Image.resolveAssetSource(...).uri` 解析。列表和网格遵循上方公共配置，不根据操作数量切换。

每次打开保存媒体、按钮配置与按钮回调；组件重渲染不会把旧会话的按钮回调替换成新配置。`onEvent` 和既有 `onIndexChange` 使用当前 props。`open()` 完成表示原生打开请求已创建，转场完成以 `opened` 事件为准；`close()` 在关闭完成后返回。组件卸载会清理查看器，连续打开和延迟到达的关闭通知按各自会话处理。

需要在宿主呈现其他原生界面时，可先 `await viewer.current?.close()`。`await viewer.current?.retry()` 返回是否重新发起当前失败媒体的请求；未挂载 ref 时可选链结果为 `undefined`。

点击来源会经过 RN 事件和打开调用，动画开始后由原生执行；新增事件不参与逐帧动画。接入方应避免阻塞 JavaScript 线程，以免延后点击响应和业务回调。

## Web 接入

从 `@sandrox/levixel-web` 引入 `openLevixel` / `openLevixelFromSelector`、`onLevixelEvent`、`closeLevixel` 和新增的 `retryLevixel`。两个打开入口均接受上方按钮配置，选择器和稳定 ID 绑定沿用 [Web 接入说明](../adapters/web/README.md)。

```ts
import {
  onLevixelEvent,
  openLevixel,
  retryLevixel,
} from '@sandrox/levixel-web';

const removeListener = onLevixelEvent(event => {
  console.log(event.type, event.payload);
});
await openLevixel({ items, actions, actionLayout: 'list' });

// 在宿主的重试操作中调用；没有当前失败媒体时返回 false。
const { retried } = await retryLevixel();
// 宿主不再需要事件时，调用 removeListener() 取消订阅。
```

抽屉位于查看器的 Shadow DOM 内，支持键盘访问。Escape 优先关闭抽屉，`closeLevixel()` 关闭整个查看器；插件不接管浏览器历史。查看器媒体禁用浏览器图片长按菜单与选取，避免 iOS Safari 的系统菜单盖住操作抽屉。这些限制只作用于查看器，宿主页保持原有行为。

Web 抽屉沿用原生定版的 `#DEDEDE` 内容底色、60px 图标底板、30px 图标、12px 网格文字和 16px 列表/取消文字，顶部及底部留白分别为 32px、16px，并额外计入浏览器安全区。列表顶部留白为 8px。Web Animations 负责展开与收起，遵循减少动态效果设置；选择操作在收起完成后通知业务，收起途中替换或关闭会话会取消尚未派发的操作。重复调用关闭均等待查看器完成关闭。

Tab 切换焦点时，仅滚动抽屉内部以保持目标按钮可见，不移动底层媒体。视频完成首帧状态处理后再派发 `mediaLoad`，接入方可在事件中立即关闭或替换会话。

重新打开会结束旧会话并派发带上下文的 `dismiss`。`ready`、`opened`、预加载事件和回调快照均遵循上方事件约定。

## UniApp 接入

经典 uni-app 与 uni-app x Vapor 从 `@/uni_modules/Sandrox-Levixel/js_sdk/index.js` 引入新增的 `retryLevixel`，原有打开、关闭和事件入口不变。`openLevixel` 与 `openLevixelFromSelector` 均接受 `actions`、`actionLayout`、`actionListIcons`，示例使用上方公共 JavaScript 配置。媒体字段、选择器和组件查询范围沿用 [UniApp 接入说明](../uni_modules/Sandrox-Levixel/readme.md)。

`onLevixelEvent` 增加 `opened`、`longPress`、`mediaLoad`、`mediaError` 和 `action`。`dismiss` 包含会话媒体上下文，替换旧会话同样通知。原图失败不会把缩略图当作加载成功，视频以首帧就绪为成功；`ready` 仅表示事件通道就绪。

`await retryLevixel()` 返回 `{ retried: boolean }`。系统返回优先关闭抽屉，`closeLevixel()` 关闭整个查看器，并在退场完成后返回 `{ closed: true }`。需要展示宿主业务弹窗时，可在按钮回调中先等待查看器关闭。按钮回调与 `action` 事件均会通知，同一次业务操作只在一处执行。

关闭或发起新的打开请求，会使仍在测量来源、解析本地路径的旧请求以 `CANCELLED` 结束，避免页面退出后又打开查看器。

## HarmonyOS 接入

`LevixelViewer` / `LevixelGallery` 增加 `actions: LevixelAction[]`、`actionLayout`、`actionListIcons`、`theme: 'dark' | 'light'`、`onEvent`。按钮字段和布局沿用上方公共约定；原生按钮回调接收 `LevixelViewerEvent`，媒体上下文为 `event.payload`。

`controller.close()` 关闭查看器，`controller.retry()` 返回是否重试当前失败媒体。宿主的 `onBackPress()` 返回 `controller.handleBack()`，使返回键优先关闭抽屉。`controller.onEvent(listener)` 返回取消订阅函数；与组件 `onEvent`、按钮回调同时使用时，应避免重复执行业务。控制器和源组件的组织方式沿用 [HarmonyOS 接入说明](../native/harmonyos/levixel/README.md)。

图片支持双指缩放、双击放大/复位和有边界的平移；回到适应屏幕大小后恢复翻页与竖拖关闭。宿主列表变化时，源映射和操作回调保持对应打开会话的媒体身份。

## 主仓本地验证

```sh
./native/android/gradlew -p native/android :levixel:testDebugUnitTest :levixel:assembleDebug :levixel:lintDebug --console=plain
./scripts/test-native-ios-source.sh
node --test adapters/uniapp/js_sdk/index.test.mjs
./scripts/sync-uniapp-canonical-js.sh --check
./scripts/verify-react-native-contract.sh
./scripts/verify-react-native-ios-lifecycle.rb
npm --prefix adapters/web run verify
```

Android 检查需要本机 Android SDK；iOS 检查需要 Xcode 与可用 iPhone 模拟器。LevixelTestHost 仅给测试提供真实 UIWindowScene，不进入插件发布产物。

Web 检查需要已安装的 Web 开发依赖和本机 Chrome。Web 演示的启动、局域网访问和浏览器配置见 [Development / Web](../DEVELOPMENT.md#web)。

## 消费宿主与发布衔接

主仓维护插件实现、接口和源码检查。`integrated-plugins` 维护业务示例及设备验证：Android/iOS/HarmonyOS、React Native 双端、经典 UniApp 与 Vapor 双端，以及桌面和移动浏览器。宿主应覆盖列表/网格、列表图标开关、空按钮、单按钮和多组滚动，并检查长按与缩放、翻页、关闭转场的协调。

开发联调结果不能代替正式产物验收。构建命令、SDK 约束和记录方式由 [DEVELOPMENT.md](../DEVELOPMENT.md) 及测试仓自身说明维护，本文件不保存临时宿主路径、个人设备状态或某次构建的完成记录。

发布时按 [Documentation Boundary](../RELEASING.md#documentation-boundary) 核对接口与对应产物，将本文件中经过确认的接口说明融入各公开指南的正常 API 章节，并保持中英文首页一致。公开指南不追加开发进度公告或待发布附录；仅删除“未发布”字样不算完成文档更新。

版本日期、正式候选、Swift Package URL/校验和、适配器产物和消费宿主验收按 [发布流程](../RELEASING.md) 执行。校验和必须来自实际产物，公开版本的 tag 和文件保持不变。
