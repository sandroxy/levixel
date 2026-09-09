# Levixel 1.4.0 维护者说明

本文件记录尚未发布的接口草案、实现约定和验证入口，供维护者推进各平台对齐。业务接入已发布包应从 [README](../README.md) 开始；发布状态以公开 tag 和 Release 为准。

跨平台约定不代表各端已经完成设备验收。源码检查与消费宿主的交互验证分别记录，发布流程见 [RELEASING.md](../RELEASING.md)。

## 本次范围

- 图片和视频长按事件，既可仅响应事件，也可配置内置操作抽屉。
- 抽屉由查看器持有：Android 使用 Material BottomSheetDialog，iOS 15 及以上使用 UIKit 系统 Sheet（iOS 13–14 使用自定义 UIKit 转场）。接入方无需调整宿主页层级。
- 任意业务按钮、显式列表/网格布局、分组和超高内容滚动、图标和两行文字、禁用/危险操作样式、取消和安全区。抽屉使用独立浅色配色，画廊的 `theme` 继续控制媒体背景；原生 iOS/Android 内容底色为 `#DEDEDE`，网格按钮字号 12、列表和取消字号 16（iOS 为 pt，Android 为 sp），跟随系统字体缩放，系统抽屉负责形态和转场。
- 打开、切页、关闭、加载成功/失败和按钮选择事件；失败提示及手动重试。
- React Native 的 `ref.open(itemId)`、`ref.close()`、`ref.retry()`；不要求目标缩略图挂载。

点按关闭仍采用原有行为。插件不实现下载、保存、分享、权限申请或任意业务内容插槽。

## 按钮配置

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

数组长度不设业务上限。不传或传空数组时，长按只派发 `longPress`，不显示抽屉。图片/视频均可长按，视频控制按钮和失败重试按钮不会触发长按。拖动或多指操作会取消当前长按识别。

选择按钮先关闭抽屉，再通知业务；查看器继续保持打开。取消、点遮罩、Android 系统 Back 只关闭抽屉，下一次 Back 才关闭查看器。程序调用 `close` 会关闭整个查看器。回调可以自行保存、展示业务页面，或者调用 close；若同时配置 `onPress` 和监听 `action`，两者都会收到通知，业务应只选一处执行副作用。

每次打开复制媒体和按钮配置。回调的 `index` 属于打开时的媒体数组；异步业务请使用 `itemId` 与业务数据关联，勿用更新后的数组下标查找旧会话图片。更新配置需要下次打开才生效。

## 事件与重试

JavaScript 事件保持 `{ type, payload, time }` 结构。公共媒体上下文：`{ sessionId, galleryId, index, itemId, mediaType }`。`sessionId` 标识一次打开；`galleryId` 用于画廊/来源关联，未指定画廊时由原生查看器生成。原生 iOS 未提供稳定媒体 ID 的旧 data source 以打开时的下标字符串作为 `itemId`，动态列表应使用带 ID 的 data source。

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

相邻页预加载可能在打开完成之前派发媒体事件，应根据事件的媒体 ID 判断对应项，不能假定都是当前页。

失败后显示重试按钮；重试仅重载当前失败媒体，不创建新会话。加载中、无失败页或查看器已关闭时不重复发起请求。

- React Native：`await ref.current.retry()` → `boolean`；`await ref.current.close()` 在查看器关闭完成后返回。
- Android：`overlay.retry()` → `boolean`；`overlay.requestClose()`；宿主 Back 应调用 `overlay.handleBack()`。
- iOS：`session.retry()` → `Bool`（主线程）；`session.close()`，可传 completion 等待关闭完成。自动点击接入可从 `configuration.onSession` 接收 session。

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

## 主仓本地验证

```sh
./native/android/gradlew -p native/android :levixel:testDebugUnitTest :levixel:assembleDebug :levixel:lintDebug --console=plain
./scripts/test-native-ios-source.sh
./scripts/verify-react-native-contract.sh
./scripts/verify-react-native-ios-lifecycle.rb
```

Android 检查需要本机 Android SDK；iOS 检查需要 Xcode 与可用 iPhone 模拟器。LevixelTestHost 仅给测试提供真实 UIWindowScene，不进入插件发布产物。

## 消费宿主与发布衔接

主仓维护插件实现、接口和源码检查。`integrated-plugins` 维护业务示例及设备验证：Android/iOS/HarmonyOS、React Native 双端、经典 UniApp 与 Vapor 双端，以及桌面和移动浏览器。宿主应覆盖列表/网格、列表图标开关、空按钮、单按钮和多组滚动，并检查长按与缩放、翻页、关闭转场的协调。

开发联调结果不能代替正式产物验收。构建命令、SDK 约束和记录方式由 [DEVELOPMENT.md](../DEVELOPMENT.md) 及测试仓自身说明维护，本文件不保存临时宿主路径、个人设备状态或某次构建的完成记录。

发布时按 [Documentation Boundary](../RELEASING.md#documentation-boundary) 核对接口与对应产物，将本文件中经过确认的接口说明融入各公开指南的正常 API 章节，并保持中英文首页一致。公开指南不追加开发进度公告或待发布附录；仅删除“未发布”字样不算完成文档更新。

版本日期、正式候选、Swift Package URL/校验和、适配器产物和消费宿主验收按 [发布流程](../RELEASING.md) 执行。校验和必须来自实际产物，公开版本的 tag 和文件保持不变。
