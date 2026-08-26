# Levixel 共享转场图片视频查看器（UTS）

Levixel 为经典 uni-app 的 App 端提供原生图片/视频查看体验，包括共享转场、左右分页、双指缩放、缩放后平移、竖拖关闭、点按关闭和视频播放。UTS 代码只是桥接层；Android/iOS 均调用与 legacy UniApp 插件相同的平台 runtime，不在 UTS 中重写查看器、手势、加载或坐标语义。

## 支持范围

- HBuilderX 5.07 及以上。
- 经典 uni-app Vue 2 / Vue 3 的 App Vue 页面。
- Android 5.0（API 21）及以上。
- iOS 13.0 及以上，arm64 真机。
- 不支持 nvue、Web、小程序、HarmonyOS 或 uni-app x。

1.1.1 尚未完成 uni-app x 下的 SDK 编译、文件路径、坐标换算和双端真机验证，因此不声明支持。

插件携带原生 AAR/framework。调试和打包时请使用包含本插件的自定义调试基座、云打包或离线打包；普通基座不包含这些原生制品。

## 引入

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

`utssdk` 暴露的三个 JSON 接口只服务内部 transport，业务代码应使用上面的 canonical JS SDK。

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

- `id`：媒体唯一标识。
- `type`：`image` 或 `video`。
- `url`：原图或视频地址，必填。
- `thumbnailUrl`：图片缩略图，可选；图片未提供时使用 `url`。
- `posterUrl`：视频封面；视频需要共享转场时应提供，也可用 `thumbnailUrl`。
- `width`、`height`：媒体原始尺寸，可选但建议提供。
- `alt`：媒体说明，可选。

## 推荐接入

源元素的选择器和 DOM 顺序必须与 `items` 一致。先用 `prepareLevixelItem` 得到稳定的本地预览地址并渲染它；图片完成解码时调用 `warmupLevixelItem`。列表较大时请限制为 2–3 个准备任务并发。

```vue
<template>
  <view class="gallery">
    <image
      v-for="(item, index) in items"
      :key="item.id"
      class="levixel-source"
      :src="previewSources[item.id]"
      mode="aspectFill"
      @load="handleLoad(item, $event)"
      @click="openViewer(index)"
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
      items: [],
      previewSources: {},
      readyItems: {},
    }
  },
  methods: {
    async preparePreview(item) {
      const prepared = await prepareLevixelItem(item, { priority: true })
      if (prepared) {
        this.previewSources = {
          ...this.previewSources,
          [item.id]: prepared.src,
        }
      }
    },
    handleLoad(item, event) {
      this.readyItems = { ...this.readyItems, [item.id]: true }
      warmupLevixelItem(item, event).catch(() => {})
    },
    async openViewer(index) {
      const item = this.items[index]
      if (!this.readyItems[item.id])
        return

      await openLevixelFromSelector({
        items: this.items,
        index,
        theme: 'dark',
        sourceSelector: '.levixel-source',
        sourceStyles: this.items.map(() => ({
          objectFit: 'cover',
          cornerRadius: uni.upx2px(12),
        })),
      })
    },
  },
}
</script>
```

## UniApp 专属源图策略

`sourceVisibility` 默认且建议保持 `visible`。这是已经在 UniApp Android/iOS 真机逐帧验收的 WebView 交接策略，用来避免关闭转场最后阶段出现源图纹理闪烁。只有业务页面完整处理 `sourceVisibilityChange`，并在实际 WebView 宿主中重新验收后，才应显式改为 `hidden`。

## 事件与直接控制

```js
const remove = onLevixelEvent((event) => {
  // ready | indexChange | sourceVisibilityChange | dismiss
  console.log(event.type, event.payload)
})

await openLevixel({ items, index: 0, sourceVisibility: 'visible' })
await closeLevixel()
remove()
```

通常优先使用 `openLevixelFromSelector`，让 SDK 测量 DOM 源图并生成 canonical `sourceHints`。

## 权限、隐私与许可

- 插件不申请相机、相册、定位、麦克风等运行时权限。
- 插件不包含广告、统计或推广 SDK。
- 插件不向作者服务器上传数据；远程媒体请求只访问业务传入的 URL。
- 本地预览缓存仅用于展示与共享转场，并按 LRU/下次启动清理策略管理。
- 许可证为 MIT；`LICENSE`、`license.md` 与 `THIRD_PARTY_NOTICES.md` 随包提供。

源码与问题反馈：https://github.com/sandroxy/levixel
