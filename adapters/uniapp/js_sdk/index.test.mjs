import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const registryKey = '__sandrox_levixel_saved_previews_v1__'
let measuredRects = []
let nativeOpenOptions
let nativeEventCallback
let activeImageInfoRequests = 0
let maxActiveImageInfoRequests = 0
let sharedPreviewOwner = ''
let activePreviewDownloads = 0
let maxActivePreviewDownloads = 0
let heldPreviewDownload
let holdNextPreviewDownload = false
const imageInfoRequests = []
const previewDownloadRequests = []
const downloadedPreviews = []
const savedPreviews = []
const removedSavedFiles = []
const convertedLocalPaths = []
const forcedDownloadFailures = new Set()
const forcedSaveFailures = new Set()
const storage = new Map([[registryKey, ['/_doc/uniapp_save/stale.preview']]])

globalThis.plus = {
  downloader: {
    createDownload(url, options, callback) {
      return {
        start() {
          const request = { url, options, callback }
          previewDownloadRequests.push(url)
          activePreviewDownloads += 1
          maxActivePreviewDownloads = Math.max(maxActivePreviewDownloads, activePreviewDownloads)
          if (holdNextPreviewDownload) {
            holdNextPreviewDownload = false
            heldPreviewDownload = request
            return
          }
          queueMicrotask(() => completePreviewDownload(request))
        },
      }
    },
  },
  io: {
    convertLocalFileSystemURL(path) {
      assert.ok(path.startsWith('_doc/'))
      convertedLocalPaths.push(path)
      return `/native/${path}`
    },
  },
}

const nativePlugin = {
  open(options, callback) {
    nativeOpenOptions = options
    callback({ ok: true, data: { index: options.index ?? 0, count: options.items.length } })
  },
  close(_options, callback) {
    callback({ ok: true, data: { closed: true } })
  },
  onEvent(callback) {
    nativeEventCallback = callback
  },
}

function dimensionsForURL(url) {
  return url.includes('poster') || url.includes('video')
    ? { width: 800, height: 450 }
    : { width: 400, height: 600 }
}

function completeImageInfoRequest(request) {
  sharedPreviewOwner = request.src
  activeImageInfoRequests -= 1
  request.success({
    ...dimensionsForURL(request.src),
    path: 'file:///cache/shared-preview.tmp',
  })
}

function completePreviewDownload(request) {
  activePreviewDownloads -= 1
  const filename = request.options.filename
  if (forcedDownloadFailures.has(request.url)) {
    request.callback({ filename }, 500)
    return
  }
  downloadedPreviews.push({ owner: request.url, savedFilePath: filename })
  request.callback({ filename }, 200)
}

globalThis.uni = {
  requireNativePlugin(name) {
    assert.equal(name, 'Levixel')
    return nativePlugin
  },
  getImageInfo({ src, success }) {
    imageInfoRequests.push(src)
    activeImageInfoRequests += 1
    maxActiveImageInfoRequests = Math.max(maxActiveImageInfoRequests, activeImageInfoRequests)
    const request = { src, success }
    queueMicrotask(() => completeImageInfoRequest(request))
  },
  saveFile({ tempFilePath, success, fail }) {
    assert.equal(tempFilePath, 'file:///cache/shared-preview.tmp')
    const owner = sharedPreviewOwner
    sharedPreviewOwner = ''
    queueMicrotask(() => {
      if (forcedSaveFailures.has(owner)) {
        fail({ errMsg: 'saveFile:fail test failure' })
        return
      }
      const savedFilePath = `/_doc/uniapp_save/${encodeURIComponent(owner)}-${savedPreviews.length + 1}.preview`
      savedPreviews.push({ owner, savedFilePath })
      success({ savedFilePath })
    })
  },
  removeSavedFile({ filePath }) {
    removedSavedFiles.push(filePath)
  },
  getStorageSync(key) {
    return storage.get(key)
  },
  setStorageSync(key, value) {
    storage.set(key, value)
  },
  getSystemInfoSync() {
    return { platform: 'android', pixelRatio: 3 }
  },
  createSelectorQuery() {
    return {
      selectAll(selector) {
        assert.equal(selector, '.source')
        return this
      },
      boundingClientRect(callback) {
        this.rectCallback = callback
        return this
      },
      exec() {
        this.rectCallback(measuredRects)
      },
    }
  },
}

const sdkSource = await readFile(
  process.env.LEVIXEL_UNIAPP_SDK_PATH || new URL('./index.js', import.meta.url),
  'utf8',
)
const sdk = await import(`data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}`)

const items = [
  {
    id: 'image-1',
    type: 'image',
    url: 'https://example.com/full.jpg',
    thumbnailUrl: 'https://example.com/thumb.jpg',
    width: 1600,
    height: 2400,
  },
  {
    id: 'video-1',
    type: 'video',
    url: 'https://example.com/video.mp4',
    posterUrl: 'https://example.com/poster.jpg',
    width: 16,
    height: 9,
  },
]

measuredRects = [
  { left: 12, top: 40, width: 120, height: 180 },
  { left: 144, top: 40, width: 180, height: 120 },
]

await Promise.all([
  sdk.warmupLevixelItem(items[0], { detail: { width: 400, height: 600 } }),
  sdk.warmupLevixelItem(items[1], { detail: { width: 800, height: 450 } }),
])
assert.deepEqual(imageInfoRequests, [])
assert.deepEqual(previewDownloadRequests, [
  'https://example.com/thumb.jpg',
  'https://example.com/poster.jpg',
])
assert.equal(maxActiveImageInfoRequests, 0)
assert.equal(maxActivePreviewDownloads, 1)
assert.ok(removedSavedFiles.includes('/_doc/uniapp_save/stale.preview'))
assert.equal(downloadedPreviews[0].owner, 'https://example.com/thumb.jpg')
assert.equal(downloadedPreviews[1].owner, 'https://example.com/poster.jpg')
assert.notEqual(downloadedPreviews[0].savedFilePath, downloadedPreviews[1].savedFilePath)
assert.deepEqual(convertedLocalPaths.slice(0, 2), downloadedPreviews.slice(0, 2).map(({ savedFilePath }) => savedFilePath))

const result = await sdk.openLevixelFromSelector({
  items,
  index: 1,
  sourceSelector: '.source',
  sourceStyles: [
    { objectFit: 'cover', cornerRadius: 6 },
    { objectFit: 'contain', cornerRadius: 0 },
  ],
})

assert.deepEqual(result, { index: 1, count: 2 })
assert.equal(imageInfoRequests.length, 0)
assert.equal(nativeOpenOptions.items[0].thumbnailUrl, `file:///native/${downloadedPreviews[0].savedFilePath}`)
assert.equal(nativeOpenOptions.items[1].posterUrl, `file:///native/${downloadedPreviews[1].savedFilePath}`)
assert.deepEqual(nativeOpenOptions.sourceHints[0], {
  rect: measuredRects[0],
  imageSize: { width: 400, height: 600 },
  objectFit: 'cover',
  coordinateSpace: 'viewport',
  rectScale: 3,
  cornerRadius: 6,
})
assert.equal(nativeOpenOptions.sourceHints[1].objectFit, 'contain')
assert.deepEqual(nativeOpenOptions.sourceHints[1].imageSize, { width: 800, height: 450 })
assert.equal(nativeOpenOptions.sourceVisibility, 'visible')

await assert.rejects(
  sdk.openLevixelFromSelector({ items, sourceSelector: '.source', galleryId: 'old-contract' }),
  /galleryId is not part of the Levixel SDK contract/,
)

measuredRects = [measuredRects[0]]
await sdk.openLevixelFromSelector({ items, sourceSelector: '.source' })
assert.deepEqual(nativeOpenOptions.sourceHints, [null, null])

let receivedEvent
const removeListener = sdk.onLevixelEvent((event) => {
  receivedEvent = event
})
nativeEventCallback({ type: 'dismiss', payload: {}, time: 1 })
assert.deepEqual(receivedEvent, { type: 'dismiss', payload: {}, time: 1 })
removeListener()

const priorityItems = ['a', 'b', 'c'].map(id => ({
  id: `priority-${id}`,
  type: 'image',
  url: `https://example.com/priority-${id}.jpg`,
}))
const priorityRequestStart = previewDownloadRequests.length
holdNextPreviewDownload = true
const priorityWarmups = priorityItems.map(item => sdk.warmupLevixelItem(item, {
  detail: { width: 400, height: 600 },
}))
measuredRects = priorityItems.map((_, index) => ({
  left: index * 100,
  top: 20,
  width: 90,
  height: 120,
}))
const priorityOpen = sdk.openLevixelFromSelector({
  items: priorityItems,
  index: 2,
  sourceSelector: '.source',
})
await priorityOpen
assert.ok(heldPreviewDownload)
completePreviewDownload(heldPreviewDownload)
heldPreviewDownload = undefined
await Promise.all(priorityWarmups)
assert.deepEqual(previewDownloadRequests.slice(priorityRequestStart), [
  'https://example.com/priority-a.jpg',
  'https://example.com/priority-c.jpg',
  'https://example.com/priority-b.jpg',
])
assert.equal(maxActivePreviewDownloads, 2)
assert.ok(nativeOpenOptions.items[2].thumbnailUrl.startsWith('file:///native/_doc/sandrox_levixel_previews/'))

const failedURL = 'https://example.com/save-failure.jpg'
const failedItem = { id: 'save-failure', type: 'image', url: failedURL }
forcedDownloadFailures.add(failedURL)
forcedSaveFailures.add(failedURL)
await sdk.warmupLevixelItem(failedItem, { detail: { width: 400, height: 600 } })
measuredRects = [{ left: 0, top: 0, width: 100, height: 120 }]
await sdk.openLevixelFromSelector({
  items: [failedItem],
  sourceSelector: '.source',
})
assert.equal(nativeOpenOptions.items[0].url, failedURL)
assert.equal(nativeOpenOptions.items[0].thumbnailUrl, undefined)

const evictionItems = Array.from({ length: 82 }, (_, index) => ({
  id: `eviction-${index}`,
  type: 'image',
  url: `https://example.com/eviction-${index}.jpg`,
}))
await Promise.all(evictionItems.map(item => sdk.warmupLevixelItem(item, {
  detail: { width: 400, height: 600 },
})))
assert.ok(removedSavedFiles.some(path => path !== '/_doc/uniapp_save/stale.preview'))
assert.ok(storage.get(registryKey).length <= 80)

await sdk.closeLevixel()
