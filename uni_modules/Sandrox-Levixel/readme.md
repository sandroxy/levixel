# Levixel 共享转场图片视频查看器

Levixel 以列表中源媒体当前可见的位置、尺寸和圆角为转场起点，将同一内容连续展开到原生全屏查看器；关闭时再沿对应路径回到源位置。缩略图、加载状态与原始媒体在同一视觉链路中连续交接，让用户始终感知为同一份媒体在列表与全屏之间展开和归位。

交互取向参考 Google Photos 与 iPhone 系统“照片”App 中以媒体为中心的直接操控方式。上述产品仅作为交互参考；Levixel 与其不存在隶属或授权关系，也未使用上述产品的代码。本项目自身的开源衍生来源见随包提供的 `THIRD_PARTY_NOTICES.md`。

## 核心能力

- 图片与视频混合分页浏览
- 以可见源为锚点的开场与回场共享转场
- 双指缩放、缩放后平移与双击复位
- 图片未放大时竖拖关闭，并支持点按关闭和系统返回
- 缩略图未就绪时直接进入原生加载状态，加载完成后连续交接
- 经典 uni-app 与 uni-app x Vapor 使用同一套公共 JavaScript API

## 兼容范围

安装本插件请使用 HBuilderX 5.24 或更高版本。正式支持范围如下：

| 宿主 | 页面类型 | Android | iOS |
| --- | --- | --- | --- |
| 经典 uni-app | Vue 2 / Vue 3 App Vue | API 21+ | iOS 13.0+，arm64 真机 |
| uni-app x | 仅 Vapor | API 23+ | iOS 15.0+，arm64 真机 |

uni-app x 不支持 VDOM。本 UniApp 交付也不覆盖 nvue、Web、小程序或 HarmonyOS；Web 与 HarmonyOS 可使用 Levixel 的[对应平台包](https://github.com/sandroxy/levixel#支持平台与分发)。

## 安装与引入

新项目推荐直接从 DCloud 插件市场导入。也可以从 [GitHub Releases](https://github.com/sandroxy/levixel/releases) 下载匹配版本的 `levixel-uniapp-<version>.zip`，将 ZIP 根目录内容放入项目的 `uni_modules/Sandrox-Levixel/`。

业务代码只需要引入高层 SDK：

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

`utssdk` 下的接口属于插件内部实现，业务代码不应直接调用。

## 媒体数据

```js
const items = [
  {
    id: 'photo-1',
    type: 'image',
    url: 'https://example.com/photo.jpg',
    thumbnailUrl: 'https://example.com/photo-thumb.jpg',
    width: 1600,
    height: 1200,
    alt: '海岸',
  },
  {
    id: 'video-1',
    type: 'video',
    url: 'https://example.com/video.mp4',
    posterUrl: 'https://example.com/video-poster.jpg',
    width: 1920,
    height: 1080,
  },
]
```

- `id`：媒体稳定标识，必须非空且在同一次打开请求中唯一。
- `type`：`image` 或 `video`。
- `url`：原图或视频地址，必填。
- `thumbnailUrl`：图片缩略图，可选；图片未提供时使用 `url`。
- `posterUrl`：视频封面；视频需要共享转场时应提供，也可用 `thumbnailUrl`。
- `width`、`height`：媒体原始尺寸，可选但建议提供。
- `alt`：媒体说明，可选。

## 接入原则

1. 动态、分页和虚拟列表使用 `initialItemId` 与 `sourceBindings`，按稳定媒体 `id` 描述当前已挂载源；绑定数量和顺序不需要等于 `items`。
2. `prepareLevixelItem` 用于显式准备稳定的本地转场预览；`warmupLevixelItem` 只记录已经解码的源图尺寸。两者都**不是打开前置条件**。
3. 即使缩略图尚未显示，点击后也应调用 `openLevixelFromSelector`；查看器会进入无共享源转场的原生加载状态，不要在业务层因 `ready` 状态而拦截。
4. 大列表准备预览时应限制为 2–3 个并发任务，避免集中占用 JS 与网络资源。
5. 原图和视频由原生查看器在打开时按需加载；列表只需渲染缩略图或视频封面。

## 经典 uni-app 示例

```vue
<template>
  <view class="gallery">
    <image
      v-for="item in items"
      :key="item.id"
      :id="`levixel-source-${item.id}`"
      class="levixel-source"
      :src="sourceFor(item)"
      mode="aspectFill"
      @load="handleLoad(item, $event)"
      @click="openViewer(item)"
    />
  </view>
</template>

<script>
import {
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
} from '@/uni_modules/Sandrox-Levixel/js_sdk/index.js'

export default {
  data() {
    return {
      items: [
        {
          id: 'photo-1',
          type: 'image',
          url: 'https://example.com/photo.jpg',
          thumbnailUrl: 'https://example.com/photo-thumb.jpg',
        },
      ],
      previewSources: {},
    }
  },
  onReady() {
    this.items.slice(0, 3).forEach(item => this.preparePreview(item))
  },
  methods: {
    sourceFor(item) {
      return this.previewSources[item.id]
        || item.thumbnailUrl
        || item.posterUrl
        || item.url
    },
    async preparePreview(item) {
      const prepared = await prepareLevixelItem(item)
      if (prepared) {
        this.previewSources = {
          ...this.previewSources,
          [item.id]: prepared.src,
        }
      }
    },
    handleLoad(item, event) {
      warmupLevixelItem(item, event).catch(() => {})
    },
    async openViewer(selectedItem) {
      const snapshot = this.items.slice()
      await openLevixelFromSelector({
        items: snapshot,
        initialItemId: selectedItem.id,
        theme: 'dark',
        sourceBindings: snapshot.map(item => ({
          itemId: item.id,
          selector: `#levixel-source-${item.id}`,
          objectFit: 'cover',
          cornerRadius: uni.upx2px(12),
        })),
      })
    },
  },
}
</script>

<style>
.levixel-source {
  width: 200rpx;
  height: 200rpx;
  border-radius: 12rpx;
}
</style>
```

## uni-app x Vapor 示例

Vapor 页面使用 Composition API / `script setup`。公共 SDK 与经典 uni-app 相同，不需要在业务层复制协议或实现平台分支。

```vue
<template>
  <view class="gallery">
    <image
      v-for="item in items"
      :key="item.id"
      :id="`levixel-source-${item.id}`"
      class="levixel-source"
      :src="previewSources.get(item.id) || item.thumbnailUrl || item.posterUrl || item.url"
      mode="aspectFill"
      @load="handleLoad(item, $event)"
      @click="openViewer(item)"
    />
  </view>
</template>

<script setup lang="uts">
import { ref } from 'vue'
import {
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
} from '@/uni_modules/Sandrox-Levixel/js_sdk/index.js'

type DemoMediaItem = {
  id: string
  type: 'image' | 'video'
  url: string
  thumbnailUrl?: string
  posterUrl?: string
}

const items = ref<DemoMediaItem[]>([
  {
    id: 'photo-1',
    type: 'image',
    url: 'https://example.com/photo.jpg',
    thumbnailUrl: 'https://example.com/photo-thumb.jpg',
  },
])
const previewSources = ref<Map<string, string>>(new Map<string, string>())

async function preparePreview(item: DemoMediaItem) {
  const prepared = await prepareLevixelItem(item)
  if (prepared != null)
    previewSources.value.set(item.id, prepared.src)
}

function handleLoad(item: DemoMediaItem, event: UniImageLoadEvent) {
  warmupLevixelItem(item, event).catch(() => {})
}

async function openViewer(selectedItem: DemoMediaItem) {
  const snapshot = items.value.slice()
  await openLevixelFromSelector({
    items: snapshot,
    initialItemId: selectedItem.id,
    theme: 'dark',
    sourceBindings: snapshot.map(item => ({
      itemId: item.id,
      selector: `#levixel-source-${item.id}`,
      objectFit: 'cover',
      cornerRadius: 6,
    })),
  })
}

items.value.slice(0, 3).forEach(item => preparePreview(item))
</script>

<style>
.levixel-source {
  width: 100px;
  height: 100px;
  border-radius: 6px;
}
</style>
```

在受支持的 App Vapor 页面中，`border-radius` 应使用 `px`，并与对应绑定项的 `cornerRadius` 数值保持一致。上例可见源为 `6px`，因此传给 Levixel 的值也是 `6`；这样开关场期间源图与原生转场快照会使用相同轮廓。

## 动态、分页与虚拟列表

调用时的 `items` 是该次全屏查看会话的媒体快照。聊天记录向前插入、瀑布流向后追加或列表重排后，下一次打开传入最新已加载数组即可；Levixel 不会在已经打开的查看器内部代替业务请求下一页。

`sourceBindings` 应包含当前实际挂载的源，不要按点击下标截取固定数量来猜测可视范围。例如已加载 100 项而虚拟列表只挂载 8 个 cell，就传这 8 项的 `{ itemId, selector }`；普通非虚拟列表可传当前已加载并挂载的全部源。SDK 会按 `itemId` 将它们放回正确位置，原生运行时再按源矩形与有效页面视口是否存在正面积交集决定回场：哪怕只露出一小部分也使用共享转场，完全位于视口外或已经卸载才安全淡出。绑定顺序可与 `items` 不同，但每个 `itemId` 必须存在于本次 `items`，每个选择器在自身查询范围内必须唯一且最多命中一个元素。

```js
const snapshot = loadedItems.slice()
const mountedSnapshot = mountedItems.slice()

await openLevixelFromSelector({
  items: snapshot,
  initialItemId: clickedItem.id,
  sourceBindings: mountedSnapshot.map(item => ({
    itemId: item.id,
    selector: `#levixel-source-${item.id}`,
    objectFit: 'cover',
    cornerRadius: 6,
  })),
})
```

示例媒体 ID 可直接用于 CSS 选择器。若业务 ID 可能包含空格、引号等 CSS 特殊字符，应另外为源元素分配无碰撞的唯一 DOM token，并把对应选择器写入绑定；不要通过会产生碰撞的字符替换来“清洗”媒体 ID。

选择器默认查询当前页面。若整个画廊位于一个自定义组件内，可在顶层传 `queryContext: componentInstance`；若虚拟列表的每个源分别位于不同 cell 组件内，则在各自 binding 中传对应的 `queryContext`。不同组件范围可以复用相同的局部选择器：

```js
sourceBindings: mountedCells.map(cell => ({
  itemId: cell.item.id,
  selector: '.levixel-source',
  queryContext: cell.componentInstance,
  objectFit: 'cover',
  cornerRadius: 6,
}))
```

`queryContext` 应传 Vue 组件公开实例；选项式 API 可使用当前组件的 `this`，组合式 API / uni-app x 可使用 `getCurrentInstance()!.proxy!`。错误的上下文会直接报错，不会退回页面范围误测其他同名元素。

固定且完整渲染的简单画廊也可以使用 `index + sourceSelector + sourceStyles`；位于自定义组件时同样可在顶层提供 `queryContext`。该模式要求选择器结果数量和顺序与 `items` 完全一致。`index` 与 `initialItemId` 是互斥的初始媒体定位方式，`sourceSelector`/`sourceStyles` 与 `sourceBindings` 是互斥的源映射方式；这两组选择彼此独立，组内冲突会直接报错。动态列表仍推荐使用 `initialItemId + sourceBindings`，避免宿主数组变化后继续解释旧下标。

## 加载与源图交接

`prepareLevixelItem` 会发起明确的预览准备任务，并将成功结果保存为 Levixel 自有的稳定本地文件。只应为当前可见或即将进入视口的少量媒体预取；大列表不要一次准备全部项目。

`warmupLevixelItem` 在图片完成解码后记录可用尺寸，不会再次下载或保存媒体。点击打开只会短暂等待已经在途的选中项准备任务；未及时就绪时立即交给原生查看器显示加载状态，不会为了共享转场长时间阻塞用户操作。

受管预览同时受单文件大小、缓存总字节数、条目数和空闲时间约束；淘汰项会立即删除，上次运行意外遗留的文件会在下次初始化时清理。准备失败或缩略图尚未加载时，查看器仍会按媒体 URL 正常打开。

`sourceVisibility` 默认且建议保持 `visible`。经典 uni-app 与 x Vapor 均使用该源图交接策略，避免关闭转场最后阶段出现源图纹理闪烁。只有页面完整处理 `sourceVisibilityChange`，并确认所有目标平台的开关场交接都符合预期时，才应显式传入 `hidden`；否则源位置可能在关闭末帧短暂留空或闪烁。

## 事件与直接控制

```js
const remove = onLevixelEvent((event) => {
  // ready | indexChange | sourceVisibilityChange | dismiss
  console.log(event.type, event.payload)
})

await openLevixel({ items, index: 0 })
await closeLevixel()
remove()
```

打开结果包含会话内 `index` 与稳定 `itemId`；`indexChange` 和 `sourceVisibilityChange` 的 payload 同时包含这两项。宿主列表可能在查看器打开期间变化时，应使用 `itemId` 识别媒体，只把 index 当作本次打开快照内的位置。

通常优先使用 `openLevixelFromSelector`，让 SDK 测量当前可见源并生成共享转场所需的 `sourceHints`。只有宿主已经拥有可靠的源图几何时，才需要直接调用 `openLevixel` 并自行传入 `sourceHints`。

## App 原生插件版

选择 App 原生插件工作流的经典 uni-app Android/iOS 项目，可以从对应 [GitHub Release](https://github.com/sandroxy/levixel/releases) 下载 `levixel-uniapp-legacy-<version>.zip`。

该包不是另一套查看器：它使用同版本的公共 SDK、UniApp 平台运行时和原生核心，只是桥接及打包形式不同。它需要自定义调试基座或离线打包，不属于 DCloud UTS 市场包，也不支持 uni-app x。

## 权限、隐私与许可

- 插件不申请相机、相册、定位、麦克风等运行时权限。
- 插件不包含广告、统计或推广 SDK。
- 插件不向作者服务器上传数据；远程媒体请求只访问业务传入的 URL。
- 本地预览缓存仅用于展示与共享转场，并按 LRU 和下次启动清理策略管理。
- 许可证为 MIT；`LICENSE`、`license.md` 与 `THIRD_PARTY_NOTICES.md` 随包提供。

源码、版本历史与问题反馈见 [Levixel GitHub 仓库](https://github.com/sandroxy/levixel)。
