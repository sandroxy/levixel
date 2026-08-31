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
let systemInfoRequests = 0
let heldPreviewDownload
let holdNextPreviewDownload = false
const imageInfoRequests = []
const previewDownloadRequests = []
const downloadedPreviews = []
const savedPreviews = []
const removedSavedFiles = []
const convertedLocalPaths = []
const forcedDownloadFailures = new Set()
const downloadedPathOverrides = new Map()
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
      assert.ok(path.startsWith('_doc/') || path.startsWith('/storage/'))
      convertedLocalPaths.push(path)
      if (path.startsWith('/storage/'))
        return path
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
  const filename = downloadedPathOverrides.get(request.url) || request.options.filename
  if (forcedDownloadFailures.has(request.url)) {
    request.callback({ filename }, 500)
    return
  }
  downloadedPreviews.push({ owner: request.url, savedFilePath: filename })
  request.callback({ filename }, 200)
}

globalThis.uni = {
  requireNativePlugin(name) {
    assert.equal(name, 'Sandrox-Levixel')
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
    systemInfoRequests += 1
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

const preparedCachedImage = await sdk.prepareLevixelItem(items[0])
assert.deepEqual(preparedCachedImage, {
  src: downloadedPreviews[0].savedFilePath,
  width: 400,
  height: 600,
})
await assert.rejects(
  sdk.prepareLevixelItem(items[0], { eager: true }),
  /eager is not part of the Levixel SDK contract/,
)
await assert.rejects(
  sdk.prepareLevixelItem(items[0], { priority: 'yes' }),
  /priority must be a boolean/,
)

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

const androidSystemInfoRequests = systemInfoRequests
globalThis.plus.os = { name: 'iOS' }
await sdk.openLevixelFromSelector({
  items,
  sourceSelector: '.source',
})
assert.equal(systemInfoRequests, androidSystemInfoRequests)
assert.equal(nativeOpenOptions.sourceHints[0].rectScale, 1)
delete globalThis.plus.os

const preparedItem = {
  id: 'prepared-image',
  type: 'image',
  url: 'https://example.com/prepared-image.jpg',
}
const preparedPreview = await sdk.prepareLevixelItem(preparedItem, { priority: true })
const preparedDownload = downloadedPreviews.find(preview => preview.owner === preparedItem.url)
assert.ok(preparedDownload)
assert.deepEqual(preparedPreview, {
  src: preparedDownload.savedFilePath,
  width: 400,
  height: 600,
})
assert.ok(imageInfoRequests.includes(`file:///native/${preparedDownload.savedFilePath}`))

const absolutePathItem = {
  id: 'absolute-path-image',
  type: 'image',
  url: 'https://example.com/absolute-path-image.jpg',
}
downloadedPathOverrides.set(absolutePathItem.url, '/storage/emulated/0/levixel.preview')
assert.deepEqual(await sdk.prepareLevixelItem(absolutePathItem, { priority: true }), {
  src: 'file:///storage/emulated/0/levixel.preview',
  width: 400,
  height: 600,
})

await assert.rejects(
  sdk.openLevixelFromSelector({ items, sourceSelector: '.source', galleryId: 'old-contract' }),
  /galleryId is not part of the Levixel SDK contract/,
)
await assert.rejects(
  sdk.openLevixelFromSelector({
    items: [items[0], { ...items[0], url: 'https://example.com/duplicate.jpg' }],
    sourceSelector: '.source',
  }),
  /\$\.items\[1\]\.id must be unique within \$\.items/,
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
receivedEvent = undefined
nativeEventCallback({ type: 'indexChange', payload: { currentIndex: 1 }, time: 2 })
assert.equal(receivedEvent, undefined)

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
assert.ok(!removedSavedFiles.includes('file:///cache/shared-preview.tmp'))

const secondFailedURL = 'https://example.com/second-save-failure.jpg'
const secondFailedItem = { id: 'second-save-failure', type: 'image', url: secondFailedURL }
forcedDownloadFailures.add(secondFailedURL)
forcedSaveFailures.add(secondFailedURL)
await sdk.warmupLevixelItem(secondFailedItem, { detail: { width: 400, height: 600 } })
await sdk.openLevixelFromSelector({ items: [secondFailedItem] })
assert.equal(nativeOpenOptions.items[0].thumbnailUrl, undefined)
assert.ok(!removedSavedFiles.includes('file:///cache/shared-preview.tmp'))

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

let injectedEventCallback
const injectedCalls = []
const utsSdk = await import(
  `data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}#uts-transport`
)
utsSdk.__setLevixelNativeTransport({
  invoke(method, options) {
    injectedCalls.push({ method, options })
    if (method === 'open') {
      return Promise.resolve({
        ok: true,
        data: { index: options.index ?? 0, count: options.items.length },
      })
    }
    return Promise.resolve({ ok: true, data: { closed: true } })
  },
  subscribe(callback) {
    injectedEventCallback = callback
    return true
  },
})

const legacyInjectedOptions = { items, index: 1 }
assert.deepEqual(await utsSdk.openLevixel(legacyInjectedOptions), { index: 1, count: 2 })
assert.deepEqual(await utsSdk.closeLevixel(), { closed: true })
assert.deepEqual(injectedCalls.map(call => call.method), ['open', 'close'])
assert.equal(injectedCalls[0].options, legacyInjectedOptions)

let injectedEvent
const removeInjectedListener = utsSdk.onLevixelEvent((event) => {
  injectedEvent = event
})
injectedEventCallback({ type: 'ready', payload: {}, time: 2 })
assert.deepEqual(injectedEvent, { type: 'ready', payload: {}, time: 2 })
removeInjectedListener()
injectedEvent = undefined
injectedEventCallback({ type: 'dismiss', payload: {}, time: 3 })
assert.equal(injectedEvent, undefined)

let classicFileSystemManagerSaveCalls = 0
let classicFileSystemManagerRemoveCalls = 0
globalThis.uni.getFileSystemManager = () => ({
  saveFile() {
    classicFileSystemManagerSaveCalls += 1
  },
  removeSavedFile() {
    classicFileSystemManagerRemoveCalls += 1
  },
})
const classicResolverSdk = await import(
  `data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}#classic-resolver-filesystem-order`
)
classicResolverSdk.__setLevixelNativeTransport({
  invoke() {
    return { ok: true, data: {} }
  },
  resolvePaths(paths) {
    return paths
  },
  subscribe() {
    return true
  },
})
const classicFallbackURL = 'https://example.com/classic-save-api-order.jpg'
forcedDownloadFailures.add(classicFallbackURL)
const classicSavedPreviewCount = savedPreviews.length
assert.deepEqual(await classicResolverSdk.prepareLevixelItem({
  id: 'classic-save-api-order',
  type: 'image',
  url: classicFallbackURL,
}, { priority: true }), {
  src: `_doc/uniapp_save/${encodeURIComponent(classicFallbackURL)}-${classicSavedPreviewCount + 1}.preview`,
  width: 400,
  height: 600,
})
assert.equal(savedPreviews.length, classicSavedPreviewCount + 1)
assert.equal(classicFileSystemManagerSaveCalls, 0)
assert.equal(classicFileSystemManagerRemoveCalls, 0)

const classicSaveFile = globalThis.uni.saveFile
delete globalThis.uni.saveFile
const classicMissingSaveSdk = await import(
  `data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}#classic-missing-save-file`
)
classicMissingSaveSdk.__setLevixelNativeTransport({
  invoke() {
    return { ok: true, data: {} }
  },
  resolvePaths(paths) {
    return paths
  },
  subscribe() {
    return true
  },
})
const classicMissingSaveURL = 'https://example.com/classic-missing-save-file.jpg'
forcedDownloadFailures.add(classicMissingSaveURL)
assert.equal(await classicMissingSaveSdk.prepareLevixelItem({
  id: 'classic-missing-save-file',
  type: 'image',
  url: classicMissingSaveURL,
}, { priority: true }), undefined)
assert.equal(classicFileSystemManagerSaveCalls, 0)
globalThis.uni.saveFile = classicSaveFile
delete globalThis.uni.getFileSystemManager

delete globalThis.plus

const vaporRemovedSavedFiles = []
const vaporSavedFiles = []
const vaporStorage = new Map([[registryKey, ['unifile://uni-store/stale.preview']]])
let vaporImageInfoSequence = 0

globalThis.uni = {
  env: {
    CACHE_PATH: 'unifile://cache/',
  },
  getImageInfo({ success }) {
    vaporImageInfoSequence += 1
    success({
      width: 320,
      height: 480,
      path: `unifile://cache/raw-${vaporImageInfoSequence}.jpeg`,
    })
  },
  getFileSystemManager() {
    return {
      saveFile({ tempFilePath, filePath, success }) {
        const savedFilePath = filePath || 'unifile://uni-store/default.preview'
        vaporSavedFiles.push({ tempFilePath, filePath, savedFilePath })
        success({ savedFilePath })
      },
      removeSavedFile({ filePath }) {
        vaporRemovedSavedFiles.push(filePath)
      },
    }
  },
  getStorageSync(key) {
    return vaporStorage.get(key)
  },
  setStorageSync(key, value) {
    vaporStorage.set(key, value)
  },
  getSystemInfoSync() {
    return { platform: 'android', pixelRatio: 2 }
  },
}

const vaporSdk = await import(
  `data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}#vapor-filesystem`
)
const vaporNativeCalls = []
const vaporResolvedPaths = []
const vaporResolveBatches = []
vaporSdk.__setLevixelNativeTransport({
  invoke(method, options) {
    vaporNativeCalls.push({ method, options })
    if (method === 'open') {
      return {
        ok: true,
        data: { index: options.index ?? 0, count: options.items.length },
      }
    }
    return { ok: true, data: { closed: true } }
  },
  resolvePaths(paths) {
    vaporResolveBatches.push(paths.slice())
    vaporResolvedPaths.push(...paths)
    return Promise.resolve(paths.map(path => (
      path.includes('/reject/') ? '' : `file:///native/${encodeURIComponent(path)}`
    )))
  },
  subscribe() {
    return true
  },
})

const vaporItem = {
  id: 'vapor-image',
  type: 'image',
  url: 'https://example.com/vapor-image.jpg',
}
assert.deepEqual(await vaporSdk.prepareLevixelItem(vaporItem, { priority: true }), {
  src: vaporSavedFiles[0].savedFilePath,
  width: 320,
  height: 480,
})
assert.equal(vaporSavedFiles[0].tempFilePath, 'unifile://cache/raw-1.jpeg')
assert.equal(vaporSavedFiles[0].filePath, vaporSavedFiles[0].savedFilePath)
assert.match(
  vaporSavedFiles[0].savedFilePath,
  /^unifile:\/\/cache\/sandrox-levixel-previews\/\d+-\d+\.jpeg$/,
)
assert.ok(vaporRemovedSavedFiles.includes('unifile://uni-store/stale.preview'))

const concurrentVaporItems = [0, 1].map(index => ({
  id: `vapor-concurrent-${index}`,
  type: 'image',
  url: `https://example.com/vapor-concurrent-${index}.jpg`,
}))
const concurrentVaporStart = vaporSavedFiles.length
await Promise.all(concurrentVaporItems.map(item => (
  vaporSdk.prepareLevixelItem(item, { priority: true })
)))
const concurrentVaporSaves = vaporSavedFiles.slice(concurrentVaporStart)
assert.equal(concurrentVaporSaves.length, concurrentVaporItems.length)
assert.equal(
  new Set(concurrentVaporSaves.map(saved => saved.savedFilePath)).size,
  concurrentVaporItems.length,
)
assert.ok(concurrentVaporSaves.every(saved => saved.filePath === saved.savedFilePath))

await vaporSdk.openLevixelFromSelector({ items: [vaporItem] })
const vaporSelectorCall = vaporNativeCalls.at(-1)
assert.equal(vaporSelectorCall.options.items[0].url, vaporItem.url)
assert.equal(
  vaporSelectorCall.options.items[0].thumbnailUrl,
  `file:///native/${encodeURIComponent(vaporSavedFiles[0].savedFilePath)}`,
)
assert.equal(vaporSelectorCall.options.sourceVisibility, 'visible')
assert.equal(vaporItem.thumbnailUrl, undefined)
assert.equal(vaporResolveBatches.length, 1)

const directVaporOptions = Object.freeze({
  items: Object.freeze([
    Object.freeze({
      id: 'local-paths',
      type: 'image',
      url: 'unifile://cache/local.jpg',
      thumbnailUrl: '/static/local-thumb.jpg',
      posterUrl: '/storage/emulated/0/local-poster.jpg',
    }),
    Object.freeze({
      id: 'safe-schemes',
      type: 'video',
      url: 'https://example.com/video.mp4',
      thumbnailUrl: 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yw=',
      posterUrl: 'file:///native/already-resolved.jpg',
    }),
    Object.freeze({
      id: 'resolver-fallback',
      type: 'image',
      url: 'unifile://cache/reject/fallback.jpg',
    }),
  ]),
  index: 0,
})
const directVaporSnapshot = JSON.parse(JSON.stringify(directVaporOptions))
const directCallStart = vaporNativeCalls.length
assert.deepEqual(await vaporSdk.openLevixel(directVaporOptions), { index: 0, count: 3 })
assert.equal(vaporNativeCalls.length, directCallStart + 1)
const directVaporCall = vaporNativeCalls.at(-1)
assert.deepEqual(directVaporOptions, directVaporSnapshot)
assert.equal(
  directVaporCall.options.items[0].url,
  `file:///native/${encodeURIComponent(directVaporOptions.items[0].url)}`,
)
assert.equal(
  directVaporCall.options.items[0].thumbnailUrl,
  `file:///native/${encodeURIComponent(directVaporOptions.items[0].thumbnailUrl)}`,
)
assert.equal(
  directVaporCall.options.items[0].posterUrl,
  `file:///native/${encodeURIComponent(directVaporOptions.items[0].posterUrl)}`,
)
assert.equal(directVaporCall.options.items[1].url, directVaporOptions.items[1].url)
assert.equal(directVaporCall.options.items[1].thumbnailUrl, directVaporOptions.items[1].thumbnailUrl)
assert.equal(directVaporCall.options.items[1].posterUrl, directVaporOptions.items[1].posterUrl)
assert.equal(directVaporCall.options.items[2].url, directVaporOptions.items[2].url)
assert.equal(vaporResolveBatches.length, 2)
assert.deepEqual(vaporResolveBatches[1], [
  directVaporOptions.items[0].url,
  directVaporOptions.items[0].thumbnailUrl,
  directVaporOptions.items[0].posterUrl,
  directVaporOptions.items[2].url,
])
assert.ok(!vaporResolvedPaths.includes(directVaporOptions.items[1].url))
assert.ok(!vaporResolvedPaths.includes(directVaporOptions.items[1].thumbnailUrl))
assert.ok(!vaporResolvedPaths.includes(directVaporOptions.items[1].posterUrl))

const batchItems = Array.from({ length: 18 }, (_, index) => ({
  id: `batch-${index}`,
  type: 'image',
  url: `unifile://cache/batch-${index}.jpg`,
  thumbnailUrl: '/static/shared-thumbnail.jpg',
}))
const batchStart = vaporResolveBatches.length
assert.deepEqual(await vaporSdk.openLevixel({ items: batchItems }), { index: 0, count: 18 })
assert.equal(vaporResolveBatches.length, batchStart + 1)
assert.equal(vaporResolveBatches.at(-1).length, 19)
assert.equal(vaporResolveBatches.at(-1).filter(path => path === '/static/shared-thumbnail.jpg').length, 1)

for (let index = 0; index < 80; index += 1) {
  await vaporSdk.prepareLevixelItem({
    id: `vapor-eviction-${index}`,
    type: 'image',
    url: `https://example.com/vapor-eviction-${index}.jpg`,
  }, { priority: true })
}
assert.ok(vaporRemovedSavedFiles.includes(vaporSavedFiles[0].savedFilePath))
assert.ok(!vaporRemovedSavedFiles.some(path => path.startsWith('unifile://cache/raw-')))

const failedVaporRemovals = []
const failedVaporRawPath = 'unifile://cache/save-failure.preview'
globalThis.uni = {
  getImageInfo({ success }) {
    success({ width: 640, height: 360, path: failedVaporRawPath })
  },
  getFileSystemManager() {
    return {
      saveFile({ fail }) {
        fail({ errMsg: 'saveFile:fail expected test failure' })
      },
      removeSavedFile({ filePath }) {
        failedVaporRemovals.push(filePath)
      },
    }
  },
  getStorageSync() {
    return []
  },
  setStorageSync() {},
  getSystemInfoSync() {
    return { platform: 'ios', pixelRatio: 3 }
  },
}
const failedVaporSdk = await import(
  `data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}#vapor-save-failure`
)
let failedVaporNativeOptions
failedVaporSdk.__setLevixelNativeTransport({
  invoke(method, options) {
    failedVaporNativeOptions = options
    return {
      ok: true,
      data: method === 'open' ? { index: 0, count: options.items.length } : { closed: true },
    }
  },
  resolvePaths(paths) {
    return paths.map(path => `file:///resolved/${encodeURIComponent(path)}`)
  },
  subscribe() {
    return true
  },
})
const failedVaporItem = {
  id: 'vapor-save-failure',
  type: 'image',
  url: 'https://example.com/vapor-save-failure.jpg',
}
assert.equal(await failedVaporSdk.prepareLevixelItem(failedVaporItem, { priority: true }), undefined)
await failedVaporSdk.openLevixelFromSelector({ items: [failedVaporItem] })
assert.equal(failedVaporNativeOptions.items[0].thumbnailUrl, undefined)
assert.ok(!failedVaporRemovals.includes(failedVaporRawPath))

const utsWrapperSource = await readFile(
  new URL('../../../uni_modules/Sandrox-Levixel/js_sdk/index.js', import.meta.url),
  'utf8',
)
const utsNativeStubSource = `
export function openLevixelNative(optionsJson, callback) {
  globalThis.__levixelWrapperNativeCalls.push(JSON.parse(optionsJson))
  callback(JSON.stringify({ ok: true, data: { opened: true } }))
}
export function closeLevixelNative(_optionsJson, callback) {
  callback(JSON.stringify({ ok: true, data: { closed: true } }))
}
export function onLevixelNativeEvent(callback) {
  globalThis.__levixelWrapperEventCallback = callback
}
export function resolveLevixelNativePaths(pathsJson, callback) {
  const paths = JSON.parse(pathsJson)
  globalThis.__levixelWrapperResolveCalls.push(paths)
  if (paths.some(path => path.includes('no-callback')))
    return
  setTimeout(() => {
    callback(JSON.stringify(paths.map(path => 'file:///first/' + encodeURIComponent(path))))
    callback(JSON.stringify(paths.map(path => 'file:///duplicate/' + encodeURIComponent(path))))
  }, 0)
}
`
const utsNativeStubURL = `data:text/javascript;base64,${Buffer.from(utsNativeStubSource).toString('base64')}`
const utsCanonicalURL = `data:text/javascript;base64,${Buffer.from(sdkSource).toString('base64')}#wrapper-canonical`
const executableUtsWrapperSource = utsWrapperSource
  .replace("from '@/uni_modules/Sandrox-Levixel'", `from '${utsNativeStubURL}'`)
  .replace("from './canonical.js'", `from '${utsCanonicalURL}'`)
  .replace('const NATIVE_PATH_RESOLUTION_TIMEOUT_MS = 5000', 'const NATIVE_PATH_RESOLUTION_TIMEOUT_MS = 20')
globalThis.__levixelWrapperNativeCalls = []
globalThis.__levixelWrapperResolveCalls = []
const executableUtsWrapper = await import(
  `data:text/javascript;base64,${Buffer.from(executableUtsWrapperSource).toString('base64')}`
)
assert.deepEqual(
  await executableUtsWrapper.openLevixel({
    items: [
      {
        id: 'callback-once',
        type: 'image',
        url: 'unifile://cache/callback-once.jpg',
        thumbnailUrl: '/static/shared-callback-preview.jpg',
      },
      {
        id: 'callback-deduplicated',
        type: 'image',
        url: 'unifile://cache/callback-deduplicated.jpg',
        thumbnailUrl: '/static/shared-callback-preview.jpg',
      },
    ],
  }),
  { opened: true },
)
assert.deepEqual(globalThis.__levixelWrapperResolveCalls, [[
  'unifile://cache/callback-once.jpg',
  '/static/shared-callback-preview.jpg',
  'unifile://cache/callback-deduplicated.jpg',
]])
assert.equal(
  globalThis.__levixelWrapperNativeCalls[0].items[0].url,
  `file:///first/${encodeURIComponent('unifile://cache/callback-once.jpg')}`,
)
assert.equal(
  globalThis.__levixelWrapperNativeCalls[0].items[1].thumbnailUrl,
  `file:///first/${encodeURIComponent('/static/shared-callback-preview.jpg')}`,
)
assert.deepEqual(
  await executableUtsWrapper.openLevixel({
    items: [{ id: 'missing-callback', type: 'image', url: 'unifile://cache/no-callback.jpg' }],
  }),
  { opened: true },
)
assert.equal(
  globalThis.__levixelWrapperNativeCalls[1].items[0].url,
  'unifile://cache/no-callback.jpg',
)

const utsTypedImage = {
  id: 'uts-typed-image',
  type: 'image',
  url: 'https://example.com/uts-typed-image.jpg',
  thumbnailUrl: 'https://example.com/uts-typed-image-thumb.jpg',
  posterUrl: null,
  width: null,
  height: null,
  alt: null,
}
const utsTypedVideo = {
  id: 'uts-typed-video',
  type: 'video',
  url: 'https://example.com/uts-typed-video.mp4',
  thumbnailUrl: null,
  posterUrl: 'https://example.com/uts-typed-video-poster.jpg',
  width: null,
  height: null,
  alt: null,
}
assert.deepEqual(
  await executableUtsWrapper.openLevixel({
    items: [utsTypedImage, utsTypedVideo],
    index: null,
    theme: null,
    sourceHints: null,
    sourceVisibility: null,
    counter: null,
    closeButton: null,
  }),
  { opened: true },
)
const normalizedUtsTypedOpen = globalThis.__levixelWrapperNativeCalls[2]
assert.deepEqual(normalizedUtsTypedOpen, {
  items: [
    {
      id: utsTypedImage.id,
      type: utsTypedImage.type,
      url: utsTypedImage.url,
      thumbnailUrl: utsTypedImage.thumbnailUrl,
    },
    {
      id: utsTypedVideo.id,
      type: utsTypedVideo.type,
      url: utsTypedVideo.url,
      posterUrl: utsTypedVideo.posterUrl,
    },
  ],
})
assert.equal(utsTypedImage.posterUrl, null)
assert.equal(utsTypedVideo.thumbnailUrl, null)

await executableUtsWrapper.warmupLevixelItem(
  utsTypedImage,
  { detail: { width: 320, height: 480 } },
)
await executableUtsWrapper.openLevixelFromSelector({
  items: [utsTypedImage],
  index: null,
  theme: null,
  sourceVisibility: null,
  sourceSelector: null,
  sourceStyles: [{ objectFit: null, cornerRadius: null }],
})
const normalizedUtsTypedSelectorOpen = globalThis.__levixelWrapperNativeCalls[3]
assert.equal(normalizedUtsTypedSelectorOpen.items[0].posterUrl, undefined)
assert.equal(normalizedUtsTypedSelectorOpen.items[0].width, undefined)
assert.equal(normalizedUtsTypedSelectorOpen.items[0].height, undefined)
assert.equal(normalizedUtsTypedSelectorOpen.items[0].alt, undefined)
assert.equal(normalizedUtsTypedSelectorOpen.index, 0)
assert.equal(normalizedUtsTypedSelectorOpen.theme, 'dark')
assert.equal(normalizedUtsTypedSelectorOpen.sourceVisibility, 'visible')
assert.deepEqual(normalizedUtsTypedSelectorOpen.sourceHints, [null])
assert.throws(
  () => executableUtsWrapper.warmupLevixelItem({
    ...utsTypedImage,
    posterUrl: '',
  }),
  /posterUrl must be a non-empty string/,
)
