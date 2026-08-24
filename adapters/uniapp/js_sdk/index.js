const PLUGIN_NAME = 'Sandrox-Levixel'
const INITIAL_PREVIEW_TIMEOUT_MS = 120
const LOADED_SOURCE_PREVIEW_TIMEOUT_MS = 1200
const MAX_IMAGE_INFO_CACHE_SIZE = 80
const SAVED_PREVIEW_REGISTRY_KEY = '__sandrox_levixel_saved_previews_v1__'
const DOWNLOADED_PREVIEW_DIRECTORY = '_doc/sandrox_levixel_previews/'

const ITEM_KEYS = new Set([
  'id',
  'type',
  'url',
  'thumbnailUrl',
  'posterUrl',
  'width',
  'height',
  'alt',
])
const SOURCE_STYLE_KEYS = new Set(['objectFit', 'cornerRadius'])
const PREPARE_ITEM_KEYS = new Set(['priority'])
const SELECTOR_OPEN_KEYS = new Set([
  'items',
  'index',
  'theme',
  'sourceVisibility',
  'sourceSelector',
  'sourceStyles',
])

let nativePlugin
let eventChannelStarted = false
const eventListeners = new Set()
const imageInfoCache = new Map()
const previewJobs = new Map()
const previewQueue = []
const ownedPreviewPaths = new Set()
let activePreviewJob = null
let savedPreviewRegistryInitialized = false
let downloadedPreviewSequence = 0

function getNativePlugin() {
  if (nativePlugin)
    return nativePlugin

  const requireNativePlugin = typeof uni !== 'undefined' && uni.requireNativePlugin
  if (typeof requireNativePlugin !== 'function')
    return null

  try {
    nativePlugin = requireNativePlugin(PLUGIN_NAME)
  }
  catch (_) {
    nativePlugin = null
  }
  return nativePlugin
}

function nativeUnavailableError() {
  return new Error('Levixel requires an App custom base or offline package containing the native plugin')
}

function assertNativeResult(result) {
  if (result && result.ok !== false)
    return result.data

  const error = new Error((result && result.message) || 'Levixel request failed')
  if (result) {
    error.code = result.code
    error.path = result.path
  }
  throw error
}

function invokeNative(method, options) {
  const plugin = getNativePlugin()
  if (!plugin || typeof plugin[method] !== 'function')
    return Promise.reject(nativeUnavailableError())

  return new Promise((resolve, reject) => {
    try {
      plugin[method](options, (result) => {
        try {
          resolve(assertNativeResult(result))
        }
        catch (error) {
          reject(error)
        }
      })
    }
    catch (error) {
      reject(error)
    }
  })
}

function rejectUnknownKeys(value, allowed, path) {
  Object.keys(value).forEach((key) => {
    if (!allowed.has(key))
      throw new Error(`${path}.${key} is not part of the Levixel SDK contract`)
  })
}

function normalizeURL(value) {
  const url = typeof value === 'string' ? value.trim() : ''
  if (url.startsWith('//'))
    return `https:${url}`
  return url
}

function nativeFileURL(savedFilePath) {
  const normalizedPath = normalizeURL(savedFilePath)
  if (!normalizedPath)
    return ''

  const isDCloudVirtualPath = /^\/?_(?:www|doc|documents|downloads)(?:\/|$)/.test(normalizedPath)
  const conversionPath = isDCloudVirtualPath && normalizedPath.startsWith('/')
    ? normalizedPath.slice(1)
    : normalizedPath

  const convertLocalFileSystemURL = typeof plus !== 'undefined'
    && plus.io
    && plus.io.convertLocalFileSystemURL
  if (typeof convertLocalFileSystemURL !== 'function')
    return isDCloudVirtualPath ? '' : normalizedPath

  try {
    const resolvedPath = normalizeURL(convertLocalFileSystemURL(conversionPath))
    if (!resolvedPath)
      return isDCloudVirtualPath ? '' : normalizedPath
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(resolvedPath))
      return resolvedPath
    if (resolvedPath.startsWith('/'))
      return `file://${resolvedPath}`
    return isDCloudVirtualPath ? '' : resolvedPath
  }
  catch (_) {
    return isDCloudVirtualPath ? '' : normalizedPath
  }
}

function webFileURL(info) {
  if (!info)
    return ''

  const savedFilePath = normalizeURL(info.savedFilePath)
  if (savedFilePath) {
    const isDCloudVirtualPath = /^\/?_(?:www|doc|documents|downloads)(?:\/|$)/.test(savedFilePath)
    if (isDCloudVirtualPath && savedFilePath.startsWith('/'))
      return savedFilePath.slice(1)
    if (isDCloudVirtualPath || /^[a-z][a-z0-9+.-]*:\/\//i.test(savedFilePath))
      return savedFilePath
  }
  return normalizeURL(info.path) || savedFilePath
}

function requireNonEmptyString(value, path) {
  if (typeof value !== 'string' || value.length === 0)
    throw new Error(`${path} must be a non-empty string`)
  return value
}

function optionalPositiveNumber(value, path) {
  if (value === undefined)
    return undefined
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0)
    throw new Error(`${path} must be a positive finite number`)
  return value
}

function sanitizeItem(value, index) {
  const path = `$.items[${index}]`
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error(`${path} must be an object`)
  rejectUnknownKeys(value, ITEM_KEYS, path)

  const type = requireNonEmptyString(value.type, `${path}.type`)
  if (type !== 'image' && type !== 'video')
    throw new Error(`${path}.type contains an unsupported value`)

  const item = {
    id: requireNonEmptyString(value.id, `${path}.id`),
    type,
    url: normalizeURL(requireNonEmptyString(value.url, `${path}.url`)),
  }
  if (value.thumbnailUrl !== undefined)
    item.thumbnailUrl = normalizeURL(requireNonEmptyString(value.thumbnailUrl, `${path}.thumbnailUrl`))
  if (value.posterUrl !== undefined)
    item.posterUrl = normalizeURL(requireNonEmptyString(value.posterUrl, `${path}.posterUrl`))
  if (value.width !== undefined)
    item.width = optionalPositiveNumber(value.width, `${path}.width`)
  if (value.height !== undefined)
    item.height = optionalPositiveNumber(value.height, `${path}.height`)
  if (value.alt !== undefined) {
    if (typeof value.alt !== 'string')
      throw new Error(`${path}.alt must be a string`)
    item.alt = value.alt
  }
  return item
}

function transitionURL(item) {
  if (item.type === 'video')
    return item.posterUrl || item.thumbnailUrl || ''
  return item.thumbnailUrl || item.url
}

function requestRemoveSavedPreview(path) {
  if (!path)
    return

  const removeWithPlus = () => {
    const resolveLocalFileSystemURL = typeof plus !== 'undefined'
      && plus.io
      && plus.io.resolveLocalFileSystemURL
    if (typeof resolveLocalFileSystemURL !== 'function')
      return
    try {
      resolveLocalFileSystemURL(path, entry => entry.remove(() => {}, () => {}), () => {})
    }
    catch (_) {}
  }

  if (typeof uni === 'undefined' || typeof uni.removeSavedFile !== 'function') {
    removeWithPlus()
    return
  }
  try {
    uni.removeSavedFile({
      filePath: path,
      fail: removeWithPlus,
    })
  }
  catch (_) {
    removeWithPlus()
  }
}

function persistOwnedPreviewPaths() {
  if (typeof uni === 'undefined' || typeof uni.setStorageSync !== 'function')
    return
  try {
    uni.setStorageSync(SAVED_PREVIEW_REGISTRY_KEY, Array.from(ownedPreviewPaths))
  }
  catch (_) {}
}

function initializeSavedPreviewRegistry() {
  if (savedPreviewRegistryInitialized)
    return
  savedPreviewRegistryInitialized = true

  if (typeof uni === 'undefined')
    return
  let stalePaths = []
  if (typeof uni.getStorageSync === 'function') {
    try {
      const storedPaths = uni.getStorageSync(SAVED_PREVIEW_REGISTRY_KEY)
      if (Array.isArray(storedPaths))
        stalePaths = storedPaths.filter(path => typeof path === 'string' && path.length > 0)
    }
    catch (_) {}
  }
  if (typeof uni.setStorageSync === 'function') {
    try {
      uni.setStorageSync(SAVED_PREVIEW_REGISTRY_KEY, [])
    }
    catch (_) {}
  }
  stalePaths.forEach(requestRemoveSavedPreview)
}

function registerOwnedPreview(path) {
  if (!path)
    return
  ownedPreviewPaths.add(path)
  persistOwnedPreviewPaths()
}

function releaseOwnedPreview(path) {
  if (!path || !ownedPreviewPaths.delete(path))
    return
  persistOwnedPreviewPaths()
  requestRemoveSavedPreview(path)
}

function cacheImageInfo(url, info) {
  const normalizedURL = normalizeURL(url)
  if (!normalizedURL || !info)
    return undefined

  const existing = imageInfoCache.get(normalizedURL)
  const width = Number(info.width) > 0 ? Number(info.width) : (existing && existing.width) || 0
  const height = Number(info.height) > 0 ? Number(info.height) : (existing && existing.height) || 0
  if (width <= 0 || height <= 0)
    return existing

  const path = normalizeURL(info.path) || (existing && existing.path) || ''
  const savedFilePath = normalizeURL(info.savedFilePath)
    || (existing && existing.savedFilePath)
    || ''
  const ownedPreview = info.ownedPreview === true
    || Boolean(existing && existing.savedFilePath === savedFilePath && existing.ownedPreview)
  const sourceLoaded = info.sourceLoaded === true
    || Boolean(existing && existing.sourceLoaded)
  if (existing && existing.savedFilePath && existing.savedFilePath !== savedFilePath && existing.ownedPreview)
    releaseOwnedPreview(existing.savedFilePath)

  const nextInfo = { width, height }
  if (path)
    nextInfo.path = path
  if (savedFilePath)
    nextInfo.savedFilePath = savedFilePath
  if (ownedPreview)
    nextInfo.ownedPreview = true
  if (sourceLoaded)
    nextInfo.sourceLoaded = true
  imageInfoCache.delete(normalizedURL)
  imageInfoCache.set(normalizedURL, nextInfo)

  while (imageInfoCache.size > MAX_IMAGE_INFO_CACHE_SIZE) {
    const firstKey = imageInfoCache.keys().next().value
    if (!firstKey)
      break
    const evicted = imageInfoCache.get(firstKey)
    imageInfoCache.delete(firstKey)
    if (evicted && evicted.ownedPreview)
      releaseOwnedPreview(evicted.savedFilePath)
  }
  return nextInfo
}

function getCachedImageInfo(url) {
  const normalizedURL = normalizeURL(url)
  const cached = normalizedURL ? imageInfoCache.get(normalizedURL) : undefined
  if (!cached)
    return undefined
  imageInfoCache.delete(normalizedURL)
  imageInfoCache.set(normalizedURL, cached)
  return cached
}

function imageInfoFromLoadEvent(event) {
  const detail = event && event.detail
  const width = Number(detail && detail.width)
  const height = Number(detail && detail.height)
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0)
    return undefined
  return { width, height, sourceLoaded: true }
}

function canDownloadStablePreview(url) {
  return /^https?:\/\//i.test(normalizeURL(url))
    && typeof plus !== 'undefined'
    && plus.downloader
    && typeof plus.downloader.createDownload === 'function'
}

function nextDownloadedPreviewPath() {
  downloadedPreviewSequence += 1
  return `${DOWNLOADED_PREVIEW_DIRECTORY}${Date.now()}-${downloadedPreviewSequence}.preview`
}

function downloadStablePreview(url) {
  const normalizedURL = normalizeURL(url)
  if (!canDownloadStablePreview(normalizedURL))
    return Promise.resolve(undefined)

  initializeSavedPreviewRegistry()
  const requestedPath = nextDownloadedPreviewPath()
  return new Promise((resolve) => {
    let settled = false
    const finish = (preview) => {
      if (settled)
        return
      settled = true
      resolve(preview)
    }

    try {
      const task = plus.downloader.createDownload(normalizedURL, {
        filename: requestedPath,
        retry: 0,
        timeout: 15,
      }, (download, statusCode) => {
        const downloadedPath = normalizeURL(download && download.filename) || requestedPath
        if (!Number.isFinite(Number(statusCode)) || Number(statusCode) < 200 || Number(statusCode) >= 400) {
          requestRemoveSavedPreview(downloadedPath)
          finish(undefined)
          return
        }

        const path = nativeFileURL(downloadedPath)
        if (!path) {
          requestRemoveSavedPreview(downloadedPath)
          finish(undefined)
          return
        }
        registerOwnedPreview(downloadedPath)
        finish({ path, savedFilePath: downloadedPath })
      })
      if (!task || typeof task.start !== 'function') {
        finish(undefined)
        return
      }
      task.start()
    }
    catch (_) {
      requestRemoveSavedPreview(requestedPath)
      finish(undefined)
    }
  })
}

function readImageInfo(url) {
  return new Promise((resolve) => {
    uni.getImageInfo({
      src: url,
      success(result) {
        if (result && result.width > 0 && result.height > 0) {
          resolve({
            width: result.width,
            height: result.height,
            path: normalizeURL(result.path),
          })
          return
        }
        resolve(undefined)
      },
      fail() {
        resolve(undefined)
      },
    })
  })
}

function saveStablePreview(tempFilePath) {
  const normalizedPath = normalizeURL(tempFilePath)
  if (!normalizedPath || typeof uni === 'undefined' || typeof uni.saveFile !== 'function')
    return Promise.resolve(undefined)

  initializeSavedPreviewRegistry()
  return new Promise((resolve) => {
    try {
      uni.saveFile({
        tempFilePath: normalizedPath,
        success(result) {
          const savedFilePath = normalizeURL(result && result.savedFilePath)
          if (!savedFilePath) {
            resolve(undefined)
            return
          }

          const path = nativeFileURL(savedFilePath)
          if (!path) {
            requestRemoveSavedPreview(savedFilePath)
            resolve(undefined)
            return
          }

          registerOwnedPreview(savedFilePath)
          resolve({ path, savedFilePath })
        },
        fail() {
          resolve(undefined)
        },
      })
    }
    catch (_) {
      resolve(undefined)
    }
  })
}

async function stabilizeImageInfo(url) {
  const existing = getCachedImageInfo(url)
  const downloadedPreview = await downloadStablePreview(url)
  if (downloadedPreview) {
    let width = existing && existing.width
    let height = existing && existing.height
    if (!(width > 0 && height > 0)) {
      const downloadedInfo = await readImageInfo(downloadedPreview.path)
      width = downloadedInfo && downloadedInfo.width
      height = downloadedInfo && downloadedInfo.height
    }
    if (width > 0 && height > 0) {
      return cacheImageInfo(url, {
        width,
        height,
        path: downloadedPreview.path,
        savedFilePath: downloadedPreview.savedFilePath,
        ownedPreview: true,
      })
    }
    requestRemoveSavedPreview(downloadedPreview.savedFilePath)
  }

  const rawInfo = await readImageInfo(url)
  if (!rawInfo)
    return getCachedImageInfo(url)

  const savedPreview = await saveStablePreview(rawInfo.path)
  return cacheImageInfo(url, {
    width: rawInfo.width,
    height: rawInfo.height,
    path: savedPreview && savedPreview.path,
    savedFilePath: savedPreview && savedPreview.savedFilePath,
    ownedPreview: Boolean(savedPreview),
  })
}

async function resolvePreviewJob(job) {
  let info
  try {
    info = await stabilizeImageInfo(job.url)
  }
  catch (_) {
    info = getCachedImageInfo(job.url)
  }
  previewJobs.delete(job.url)
  job.resolve(info)
}

async function drainPreviewQueue() {
  if (activePreviewJob)
    return

  while (previewQueue.length > 0) {
    const job = previewQueue.shift()
    activePreviewJob = job
    job.queued = false
    await resolvePreviewJob(job)
    activePreviewJob = null
  }
}

function startPriorityPreviewJob(job) {
  const queueIndex = previewQueue.indexOf(job)
  if (queueIndex >= 0)
    previewQueue.splice(queueIndex, 1)
  job.queued = false
  void resolvePreviewJob(job)
}

function ensureStableImageInfo(url, priority = false) {
  const normalizedURL = normalizeURL(url)
  if (!normalizedURL)
    return Promise.resolve(undefined)

  const cached = getCachedImageInfo(normalizedURL)
  if (cached && cached.path)
    return Promise.resolve(cached)

  const existingJob = previewJobs.get(normalizedURL)
  if (existingJob) {
    if (priority && existingJob.queued) {
      if (canDownloadStablePreview(normalizedURL))
        startPriorityPreviewJob(existingJob)
      else {
        const queueIndex = previewQueue.indexOf(existingJob)
        if (queueIndex > 0) {
          previewQueue.splice(queueIndex, 1)
          previewQueue.unshift(existingJob)
        }
      }
    }
    return existingJob.promise
  }

  let resolveJob
  const promise = new Promise((resolve) => {
    resolveJob = resolve
  })
  const job = {
    url: normalizedURL,
    queued: true,
    promise,
    resolve: resolveJob,
  }
  previewJobs.set(normalizedURL, job)
  if (priority && canDownloadStablePreview(normalizedURL))
    startPriorityPreviewJob(job)
  else if (priority)
    previewQueue.unshift(job)
  else
    previewQueue.push(job)
  void drainPreviewQueue()
  return promise
}

function withTimeout(promise, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false
    const timer = setTimeout(() => {
      if (settled)
        return
      settled = true
      resolve(undefined)
    }, timeoutMs)

    promise.then((value) => {
      if (settled)
        return
      settled = true
      clearTimeout(timer)
      resolve(value)
    }).catch(() => {
      if (settled)
        return
      settled = true
      clearTimeout(timer)
      resolve(undefined)
    })
  })
}

function normalizeRect(value) {
  if (!value || Array.isArray(value))
    return null
  const left = Number(value.left)
  const top = Number(value.top)
  const width = Number(value.width)
  const height = Number(value.height)
  if (![left, top, width, height].every(Number.isFinite) || width <= 1 || height <= 1)
    return null
  return { left, top, width, height }
}

function readSourceRectScale() {
  try {
    const info = uni.getSystemInfoSync()
    const platform = String(info.platform || '').toLowerCase()
    if (platform !== 'android')
      return 1
    const pixelRatio = Number(info.pixelRatio)
    return Number.isFinite(pixelRatio) && pixelRatio > 0 ? pixelRatio : 1
  }
  catch (_) {
    return 1
  }
}

function measureSources(selector, itemCount) {
  if (!selector)
    return Promise.resolve(Array(itemCount).fill(null))

  return new Promise((resolve) => {
    try {
      uni.createSelectorQuery()
        .selectAll(selector)
        .boundingClientRect((values) => {
          if (!Array.isArray(values) || values.length !== itemCount) {
            resolve(Array(itemCount).fill(null))
            return
          }
          resolve(values.map(normalizeRect))
        })
        .exec()
    }
    catch (_) {
      resolve(Array(itemCount).fill(null))
    }
  })
}

function normalizeSourceStyles(rawStyles, itemCount) {
  if (rawStyles === undefined)
    return Array.from({ length: itemCount }, () => ({ objectFit: 'cover', cornerRadius: 0 }))
  if (!Array.isArray(rawStyles) || rawStyles.length !== itemCount)
    throw new Error('$.sourceStyles must contain one entry for each media item')

  return rawStyles.map((value, index) => {
    const path = `$.sourceStyles[${index}]`
    if (!value || typeof value !== 'object' || Array.isArray(value))
      throw new Error(`${path} must be an object`)
    rejectUnknownKeys(value, SOURCE_STYLE_KEYS, path)
    const objectFit = value.objectFit === undefined ? 'cover' : value.objectFit
    if (!['contain', 'cover', 'fill'].includes(objectFit))
      throw new Error(`${path}.objectFit contains an unsupported value`)
    const cornerRadius = value.cornerRadius === undefined ? 0 : value.cornerRadius
    if (typeof cornerRadius !== 'number' || !Number.isFinite(cornerRadius) || cornerRadius < 0)
      throw new Error(`${path}.cornerRadius must be a non-negative finite number`)
    return { objectFit, cornerRadius }
  })
}

function applyLocalPreview(item, info) {
  if (!info || !info.path)
    return item
  if (item.type === 'video')
    return { ...item, posterUrl: info.path }
  return { ...item, thumbnailUrl: info.path }
}

function startEventChannel() {
  if (eventChannelStarted)
    return
  const plugin = getNativePlugin()
  if (!plugin || typeof plugin.onEvent !== 'function')
    return

  eventChannelStarted = true
  plugin.onEvent((event) => {
    eventListeners.forEach((listener) => {
      try {
        listener(event)
      }
      catch (_) {}
    })
  })
}

export function openLevixel(options) {
  return invokeNative('open', options)
}

export function closeLevixel() {
  return invokeNative('close', {})
}

export function onLevixelEvent(listener) {
  if (typeof listener !== 'function')
    throw new Error('Levixel event listener must be a function')
  eventListeners.add(listener)
  startEventChannel()
  return () => eventListeners.delete(listener)
}

export async function prepareLevixelItem(item, options = {}) {
  if (!options || typeof options !== 'object' || Array.isArray(options))
    throw new Error('$.options must be an object')
  rejectUnknownKeys(options, PREPARE_ITEM_KEYS, '$.options')
  if (options.priority !== undefined && typeof options.priority !== 'boolean')
    throw new Error('$.options.priority must be a boolean')

  const normalizedItem = sanitizeItem(item, 0)
  const url = transitionURL(normalizedItem)
  if (!url)
    return undefined

  const info = await ensureStableImageInfo(url, options.priority === true)
  const src = webFileURL(info)
  if (!src || !(info && info.width > 0 && info.height > 0))
    return undefined
  return {
    src,
    width: info.width,
    height: info.height,
  }
}

export function warmupLevixelItem(item, loadEvent) {
  const normalizedItem = sanitizeItem(item, 0)
  const url = transitionURL(normalizedItem)
  if (!url)
    return Promise.resolve()

  const loadedInfo = imageInfoFromLoadEvent(loadEvent)
  if (loadedInfo)
    cacheImageInfo(url, loadedInfo)
  return ensureStableImageInfo(url).then(() => undefined)
}

export async function openLevixelFromSelector(options) {
  if (!options || typeof options !== 'object' || Array.isArray(options))
    throw new Error('$ must be an object')
  rejectUnknownKeys(options, SELECTOR_OPEN_KEYS, '$')
  if (!Array.isArray(options.items) || options.items.length === 0)
    throw new Error('$.items must contain at least one item')

  const items = options.items.map(sanitizeItem)
  const index = options.index === undefined ? 0 : options.index
  if (!Number.isInteger(index) || index < 0 || index >= items.length)
    throw new Error('$.index must reference an item in $.items')
  const theme = options.theme === undefined ? 'dark' : options.theme
  if (theme !== 'dark' && theme !== 'light')
    throw new Error('$.theme contains an unsupported value')
  const sourceVisibility = options.sourceVisibility === undefined ? 'visible' : options.sourceVisibility
  if (sourceVisibility !== 'visible' && sourceVisibility !== 'hidden')
    throw new Error('$.sourceVisibility contains an unsupported value')
  if (options.sourceSelector !== undefined && typeof options.sourceSelector !== 'string')
    throw new Error('$.sourceSelector must be a string')

  const sourceStyles = normalizeSourceStyles(options.sourceStyles, items.length)
  const rectScale = readSourceRectScale()
  const previewURLs = items.map(transitionURL)
  const selectedPreviewURL = previewURLs[index]
  const selectedCachedInfo = selectedPreviewURL
    ? getCachedImageInfo(selectedPreviewURL)
    : undefined
  const selectedPreviewPromise = selectedPreviewURL
    ? ensureStableImageInfo(selectedPreviewURL, true)
    : Promise.resolve(undefined)
  const previewTimeout = selectedCachedInfo && selectedCachedInfo.sourceLoaded
    ? LOADED_SOURCE_PREVIEW_TIMEOUT_MS
    : INITIAL_PREVIEW_TIMEOUT_MS

  const [rects, initialInfo] = await Promise.all([
    measureSources(options.sourceSelector, items.length),
    selectedPreviewURL
      ? withTimeout(selectedPreviewPromise, previewTimeout)
      : Promise.resolve(undefined),
  ])
  const previewInfos = previewURLs.map(url => url ? getCachedImageInfo(url) : undefined)
  if (initialInfo && selectedPreviewURL)
    previewInfos[index] = initialInfo
  const resolvedItems = items.map((item, itemIndex) => applyLocalPreview(item, previewInfos[itemIndex]))
  const sourceHints = rects.map((rect, itemIndex) => {
    if (!rect)
      return null
    const item = resolvedItems[itemIndex]
    const url = previewURLs[itemIndex]
    const info = previewInfos[itemIndex] || (url ? getCachedImageInfo(url) : undefined)
    const imageSize = info && info.width > 0 && info.height > 0
      ? { width: info.width, height: info.height }
      : (item.width > 0 && item.height > 0 ? { width: item.width, height: item.height } : undefined)
    const hint = {
      rect,
      objectFit: sourceStyles[itemIndex].objectFit,
      coordinateSpace: 'viewport',
      rectScale,
      cornerRadius: sourceStyles[itemIndex].cornerRadius,
    }
    if (imageSize)
      hint.imageSize = imageSize
    return hint
  })

  return openLevixel({
    items: resolvedItems,
    index,
    theme,
    sourceHints,
    sourceVisibility,
  })
}

export default {
  open: openLevixel,
  close: closeLevixel,
  onEvent: onLevixelEvent,
  prepareItem: prepareLevixelItem,
  warmupItem: warmupLevixelItem,
  openFromSelector: openLevixelFromSelector,
}
