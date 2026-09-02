const PLUGIN_NAME = 'Sandrox-Levixel'
const INITIAL_PREVIEW_TIMEOUT_MS = 120
const MAX_IMAGE_INFO_CACHE_SIZE = 80
const MAX_MANAGED_PREVIEW_BYTES = 16 * 1024 * 1024
const MAX_MANAGED_PREVIEW_CACHE_BYTES = 64 * 1024 * 1024
const MANAGED_PREVIEW_IDLE_TTL_MS = 30 * 60 * 1000
const SAVED_PREVIEW_REGISTRY_KEY = '__sandrox_levixel_saved_previews_v1__'
const DOWNLOADED_PREVIEW_DIRECTORY = '_doc/sandrox_levixel_previews/'
const FILE_SYSTEM_PREVIEW_DIRECTORY = 'sandrox-levixel-previews'

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
const SOURCE_BINDING_KEYS = new Set([
  'itemId',
  'selector',
  'objectFit',
  'cornerRadius',
  'queryContext',
])
const PREPARE_ITEM_KEYS = new Set(['priority'])
const NATIVE_MEDIA_PATH_KEYS = ['url', 'thumbnailUrl', 'posterUrl']
const SELECTOR_OPEN_KEYS = new Set([
  'items',
  'index',
  'initialItemId',
  'theme',
  'sourceVisibility',
  'sourceSelector',
  'sourceStyles',
  'sourceBindings',
  'queryContext',
])

const ROOT_QUERY_CONTEXT = {}

let nativePlugin
let injectedNativeTransport
let eventChannelStarted = false
const eventListeners = new Set()
const imageInfoCache = new Map()
const previewJobs = new Map()
const previewQueue = []
const ownedPreviewBytesByPath = new Map()
let activePreviewJob = null
let savedPreviewRegistryInitialized = false
let previewPathSequence = 0

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
  return new Error('Levixel requires an App package containing the Sandrox-Levixel native runtime')
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

const nativePluginTransport = {
  invoke(method, options) {
    const plugin = getNativePlugin()
    if (!plugin || typeof plugin[method] !== 'function')
      return Promise.reject(nativeUnavailableError())

    return new Promise((resolve, reject) => {
      try {
        plugin[method](options, resolve)
      }
      catch (error) {
        reject(error)
      }
    })
  },
  subscribe(listener) {
    const plugin = getNativePlugin()
    if (!plugin || typeof plugin.onEvent !== 'function')
      return false
    plugin.onEvent(listener)
    return true
  },
}

function getNativeTransport() {
  return injectedNativeTransport || nativePluginTransport
}

function shouldResolveNativeMediaPath(value) {
  if (typeof value !== 'string')
    return false
  const path = value.trim()
  if (!path || path.startsWith('//'))
    return false
  if (/^[a-z]:[\\/]/i.test(path))
    return true

  const scheme = path.match(/^([a-z][a-z0-9+.-]*):/i)
  return !scheme || scheme[1].toLowerCase() === 'unifile'
}

async function resolveOpenNativeMediaPaths(options, transport) {
  if (!options || typeof options !== 'object' || Array.isArray(options) || !Array.isArray(options.items))
    return options

  const resolutions = []
  const uniquePaths = []
  const uniquePathIndexes = new Map()
  options.items.forEach((item, itemIndex) => {
    if (!item || typeof item !== 'object' || Array.isArray(item))
      return
    NATIVE_MEDIA_PATH_KEYS.forEach((key) => {
      const path = item[key]
      if (!shouldResolveNativeMediaPath(path))
        return
      let pathIndex = uniquePathIndexes.get(path)
      if (pathIndex === undefined) {
        pathIndex = uniquePaths.length
        uniquePathIndexes.set(path, pathIndex)
        uniquePaths.push(path)
      }
      resolutions.push({
        itemIndex,
        key,
        path,
        pathIndex,
      })
    })
  })
  if (resolutions.length === 0)
    return options

  let resolvedPaths
  try {
    resolvedPaths = await Promise.resolve(transport.resolvePaths(uniquePaths))
  }
  catch (_) {
    return options
  }
  if (!Array.isArray(resolvedPaths) || resolvedPaths.length !== uniquePaths.length)
    return options

  let resolvedItems
  resolutions.forEach((entry) => {
    const candidate = resolvedPaths[entry.pathIndex]
    const resolvedPath = typeof candidate === 'string' && candidate.length > 0
      ? candidate
      : entry.path
    if (resolvedPath === entry.path)
      return
    if (!resolvedItems)
      resolvedItems = options.items.slice()
    if (resolvedItems[entry.itemIndex] === options.items[entry.itemIndex])
      resolvedItems[entry.itemIndex] = { ...options.items[entry.itemIndex] }
    resolvedItems[entry.itemIndex][entry.key] = resolvedPath
  })
  return resolvedItems ? { ...options, items: resolvedItems } : options
}

function invokeNativeWithTransport(transport, method, options) {
  try {
    return Promise.resolve(transport.invoke(method, options)).then(assertNativeResult)
  }
  catch (error) {
    return Promise.reject(error)
  }
}

function invokeNative(method, options) {
  const transport = getNativeTransport()
  if (method !== 'open' || typeof transport.resolvePaths !== 'function')
    return invokeNativeWithTransport(transport, method, options)
  return resolveOpenNativeMediaPaths(options, transport)
    .then(resolvedOptions => invokeNativeWithTransport(transport, method, resolvedOptions))
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
  if (typeof value !== 'string' || value.trim().length === 0)
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

function sanitizeItems(value) {
  if (!Array.isArray(value) || value.length === 0)
    throw new Error('$.items must contain at least one item')

  const items = value.map(sanitizeItem)
  const ids = new Set()
  items.forEach((item, index) => {
    if (ids.has(item.id))
      throw new Error(`$.items[${index}].id must be unique within $.items`)
    ids.add(item.id)
  })
  return items
}

function transitionURL(item) {
  if (item.type === 'video')
    return item.posterUrl || item.thumbnailUrl || ''
  return item.thumbnailUrl || item.url
}

function getFileSystemManager() {
  if (typeof uni === 'undefined' || typeof uni.getFileSystemManager !== 'function')
    return undefined
  try {
    return uni.getFileSystemManager()
  }
  catch (_) {
    return undefined
  }
}

function prefersFileSystemManager() {
  return typeof plus === 'undefined'
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

  const fileSystemManager = getFileSystemManager()
  const removeWithFileSystemManager = typeof fileSystemManager?.removeSavedFile === 'function'
    ? (fallback) => {
        try {
          fileSystemManager.removeSavedFile({ filePath: path, fail: fallback })
        }
        catch (_) {
          fallback()
        }
      }
    : undefined
  const removeWithUni = typeof uni !== 'undefined' && typeof uni.removeSavedFile === 'function'
    ? (fallback) => {
        try {
          uni.removeSavedFile({ filePath: path, fail: fallback })
        }
        catch (_) {
          fallback()
        }
      }
    : undefined
  const removers = prefersFileSystemManager()
    ? [removeWithFileSystemManager, removeWithUni]
    : [removeWithUni]
  const availableRemovers = removers.filter(Boolean)
  const attempt = (index) => {
    const remover = availableRemovers[index]
    if (!remover) {
      removeWithPlus()
      return
    }
    let advanced = false
    remover(() => {
      if (advanced)
        return
      advanced = true
      attempt(index + 1)
    })
  }
  attempt(0)
}

function persistOwnedPreviewPaths() {
  if (typeof uni === 'undefined' || typeof uni.setStorageSync !== 'function')
    return
  try {
    uni.setStorageSync(SAVED_PREVIEW_REGISTRY_KEY, Array.from(ownedPreviewBytesByPath.keys()))
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

function normalizeFileSize(value) {
  const size = Number(value)
  return Number.isFinite(size) && size > 0 ? size : undefined
}

function readManagedPreviewSize(path, knownSize) {
  const normalizedKnownSize = normalizeFileSize(knownSize)
  if (normalizedKnownSize)
    return Promise.resolve(normalizedKnownSize)

  const readers = []
  const fileSystemManager = getFileSystemManager()
  if (typeof fileSystemManager?.getFileInfo === 'function') {
    readers.push((resolve, next) => {
      try {
        fileSystemManager.getFileInfo({
          filePath: path,
          success(result) {
            const size = normalizeFileSize(result && result.size)
            size ? resolve(size) : next()
          },
          fail: next,
        })
      }
      catch (_) {
        next()
      }
    })
  }
  if (typeof uni !== 'undefined' && typeof uni.getSavedFileInfo === 'function') {
    readers.push((resolve, next) => {
      try {
        uni.getSavedFileInfo({
          filePath: path,
          success(result) {
            const size = normalizeFileSize(result && result.size)
            size ? resolve(size) : next()
          },
          fail: next,
        })
      }
      catch (_) {
        next()
      }
    })
  }
  const resolveLocalFileSystemURL = typeof plus !== 'undefined'
    && plus.io
    && plus.io.resolveLocalFileSystemURL
  if (typeof resolveLocalFileSystemURL === 'function') {
    readers.push((resolve, next) => {
      try {
        resolveLocalFileSystemURL(path, (entry) => {
          if (!entry || typeof entry.file !== 'function') {
            next()
            return
          }
          entry.file((file) => {
            const size = normalizeFileSize(file && file.size)
            size ? resolve(size) : next()
          }, next)
        }, next)
      }
      catch (_) {
        next()
      }
    })
  }

  return new Promise((resolve) => {
    let settled = false
    const finish = (size) => {
      if (settled)
        return
      settled = true
      resolve(size)
    }
    const attempt = (index) => {
      const reader = readers[index]
      if (!reader) {
        finish(undefined)
        return
      }
      let advanced = false
      reader(finish, () => {
        if (advanced || settled)
          return
        advanced = true
        attempt(index + 1)
      })
    }
    attempt(0)
  })
}

function registerOwnedPreview(path, bytes) {
  const normalizedBytes = normalizeFileSize(bytes)
  if (!path || !normalizedBytes)
    return false
  ownedPreviewBytesByPath.set(path, normalizedBytes)
  persistOwnedPreviewPaths()
  return true
}

function releaseOwnedPreview(path) {
  if (!path || !ownedPreviewBytesByPath.delete(path))
    return
  persistOwnedPreviewPaths()
  requestRemoveSavedPreview(path)
}

async function acceptManagedPreview(path, knownSize) {
  const bytes = await readManagedPreviewSize(path, knownSize)
  if (!bytes || bytes > MAX_MANAGED_PREVIEW_BYTES) {
    requestRemoveSavedPreview(path)
    return false
  }
  return registerOwnedPreview(path, bytes)
}

function removeCachedImageInfo(key) {
  const cached = imageInfoCache.get(key)
  imageInfoCache.delete(key)
  if (cached && cached.ownedPreview)
    releaseOwnedPreview(cached.savedFilePath)
}

function managedPreviewCacheBytes() {
  let total = 0
  ownedPreviewBytesByPath.forEach((bytes) => {
    total += bytes
  })
  return total
}

function enforceImageInfoCacheLimits(now = Date.now()) {
  imageInfoCache.forEach((cached, key) => {
    if (cached.ownedPreview
      && now - cached.lastAccessedAt > MANAGED_PREVIEW_IDLE_TTL_MS)
      removeCachedImageInfo(key)
  })

  while (imageInfoCache.size > MAX_IMAGE_INFO_CACHE_SIZE) {
    const firstKey = imageInfoCache.keys().next().value
    if (!firstKey)
      break
    removeCachedImageInfo(firstKey)
  }

  while (managedPreviewCacheBytes() > MAX_MANAGED_PREVIEW_CACHE_BYTES) {
    let oldestOwnedPreviewKey
    for (const [key, cached] of imageInfoCache) {
      if (cached.ownedPreview) {
        oldestOwnedPreviewKey = key
        break
      }
    }
    if (!oldestOwnedPreviewKey)
      break
    removeCachedImageInfo(oldestOwnedPreviewKey)
  }
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
  nextInfo.lastAccessedAt = Date.now()
  imageInfoCache.delete(normalizedURL)
  imageInfoCache.set(normalizedURL, nextInfo)
  enforceImageInfoCacheLimits(nextInfo.lastAccessedAt)
  return imageInfoCache.get(normalizedURL)
}

function getCachedImageInfo(url) {
  const normalizedURL = normalizeURL(url)
  enforceImageInfoCacheLimits()
  const cached = normalizedURL ? imageInfoCache.get(normalizedURL) : undefined
  if (!cached)
    return undefined
  cached.lastAccessedAt = Date.now()
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

function nextPreviewFileName(extension) {
  previewPathSequence += 1
  return `${Date.now()}-${previewPathSequence}${extension}`
}

function nextDownloadedPreviewPath() {
  return `${DOWNLOADED_PREVIEW_DIRECTORY}${nextPreviewFileName('.preview')}`
}

function nextFileSystemPreviewPath(tempFilePath) {
  if (typeof uni === 'undefined')
    return ''
  const cachePath = normalizeURL(uni.env && uni.env.CACHE_PATH).replace(/\/+$/, '')
  if (!cachePath)
    return ''

  const pathWithoutQuery = normalizeURL(tempFilePath).split(/[?#]/)[0]
  const extensionMatch = pathWithoutQuery.match(/\.(avif|bmp|gif|heic|heif|jpe?g|png|webp)$/i)
  const extension = extensionMatch ? `.${extensionMatch[1].toLowerCase()}` : '.preview'
  return `${cachePath}/${FILE_SYSTEM_PREVIEW_DIRECTORY}/${nextPreviewFileName(extension)}`
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
        const knownSize = normalizeFileSize(download && download.downloadedSize)
          || normalizeFileSize(download && download.totalSize)
        void acceptManagedPreview(downloadedPath, knownSize).then((accepted) => {
          if (!accepted) {
            finish(undefined)
            return
          }
          finish({ path, savedFilePath: downloadedPath })
        }).catch(() => {
          requestRemoveSavedPreview(downloadedPath)
          finish(undefined)
        })
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
  if (!normalizedPath || typeof uni === 'undefined')
    return Promise.resolve(undefined)

  const fileSystemManager = getFileSystemManager()
  const saveWithFileSystemManager = typeof fileSystemManager?.saveFile === 'function'
    ? options => fileSystemManager.saveFile(options)
    : undefined
  const saveWithUni = typeof uni.saveFile === 'function'
    ? options => uni.saveFile(options)
    : undefined
  const useFileSystemManager = prefersFileSystemManager() && Boolean(saveWithFileSystemManager)
  const saveFile = useFileSystemManager
    ? saveWithFileSystemManager
    : saveWithUni
  if (!saveFile)
    return Promise.resolve(undefined)

  initializeSavedPreviewRegistry()
  return new Promise((resolve) => {
    let settled = false
    const finish = (preview) => {
      if (settled)
        return
      settled = true
      resolve(preview)
    }
    try {
      const saveOptions = {
        tempFilePath: normalizedPath,
        success(result) {
          const savedFilePath = normalizeURL(result && result.savedFilePath)
          if (!savedFilePath) {
            finish(undefined)
            return
          }

          const path = nativeFileURL(savedFilePath)
          if (!path) {
            requestRemoveSavedPreview(savedFilePath)
            finish(undefined)
            return
          }

          void acceptManagedPreview(savedFilePath, result && result.size).then((accepted) => {
            if (!accepted) {
              finish(undefined)
              return
            }
            finish({ path, savedFilePath })
          }).catch(() => {
            requestRemoveSavedPreview(savedFilePath)
            finish(undefined)
          })
        },
        fail() {
          finish(undefined)
        },
      }
      const filePath = useFileSystemManager
        ? nextFileSystemPreviewPath(normalizedPath)
        : ''
      if (filePath)
        saveOptions.filePath = filePath
      saveFile(saveOptions)
    }
    catch (_) {
      finish(undefined)
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
    releaseOwnedPreview(downloadedPreview.savedFilePath)
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
    const osName = typeof plus !== 'undefined' && plus.os
      ? String(plus.os.name || '').toLowerCase()
      : ''
    if (osName && osName !== 'android')
      return 1

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

function selectorQuery(queryContext) {
  const query = uni.createSelectorQuery()
  if (queryContext === undefined)
    return query
  const scopedQuery = query.in(queryContext)
  if (!scopedQuery)
    throw new Error('selector query context was rejected')
  return scopedQuery
}

function measureSources(selector, itemCount, queryContext) {
  if (!selector)
    return Promise.resolve(Array(itemCount).fill(null))

  return new Promise((resolve, reject) => {
    let query
    try {
      query = selectorQuery(queryContext)
    }
    catch (_) {
      if (queryContext !== undefined) {
        reject(new Error('$.queryContext is not a valid selector query context'))
        return
      }
      reject(new Error('$.sourceSelector could not create its selector query'))
      return
    }
    try {
      query
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
      reject(new Error('$.sourceSelector is not valid'))
    }
  })
}

function measureSourceBindings(sourceBindings, itemCount) {
  const rects = Array(itemCount).fill(null)
  if (sourceBindings.length === 0)
    return Promise.resolve(rects)

  const groupsByContext = new Map()
  sourceBindings.forEach((binding, bindingIndex) => {
    const contextKey = binding.queryContext === undefined
      ? ROOT_QUERY_CONTEXT
      : binding.queryContext
    let group = groupsByContext.get(contextKey)
    if (!group) {
      group = {
        queryContext: binding.queryContext,
        queryContextPath: binding.queryContextPath,
        bindings: [],
      }
      groupsByContext.set(contextKey, group)
    }
    group.bindings.push({ binding, bindingIndex })
  })

  const measurements = [...groupsByContext.values()].map(group => new Promise((resolve, reject) => {
    let settled = false
    const fail = (error) => {
      if (settled)
        return
      settled = true
      reject(error)
    }
    let query
    try {
      query = selectorQuery(group.queryContext)
    }
    catch (_) {
      fail(new Error(`${group.queryContextPath} is not a valid selector query context`))
      return
    }
    group.bindings.forEach(({ binding, bindingIndex }) => {
      if (settled)
        return
      try {
        const path = `$.sourceBindings[${bindingIndex}].selector`
        query
          .selectAll(binding.selector)
          .boundingClientRect((values) => {
            if (settled)
              return
            if (!Array.isArray(values)) {
              fail(new Error(`${path} returned an invalid selector result`))
              return
            }
            if (values.length > 1) {
              fail(new Error(`${path} must match at most one element`))
              return
            }
            rects[binding.itemIndex] = values.length === 1 ? normalizeRect(values[0]) : null
          })
      }
      catch (_) {
        fail(new Error(`$.sourceBindings[${bindingIndex}].selector is not valid`))
      }
    })
    if (settled)
      return
    try {
      query.exec(() => {
        if (settled)
          return
        settled = true
        resolve()
      })
    }
    catch (_) {
      fail(new Error('$.sourceBindings could not execute its selector query'))
    }
  }))
  return Promise.all(measurements).then(() => rects)
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

function normalizeQueryContext(value, path) {
  if (value === undefined)
    return undefined
  if (value === null || typeof value !== 'object' || Array.isArray(value))
    throw new Error(`${path} must be a component instance`)
  return value
}

function normalizeSourceBindings(rawBindings, items, defaultQueryContext) {
  if (rawBindings === undefined)
    return undefined
  if (!Array.isArray(rawBindings))
    throw new Error('$.sourceBindings must be an array')

  const itemIndexes = new Map(items.map((item, index) => [item.id, index]))
  const itemIds = new Set()
  const selectorsByContext = new Map()
  return rawBindings.map((value, index) => {
    const path = `$.sourceBindings[${index}]`
    if (!value || typeof value !== 'object' || Array.isArray(value))
      throw new Error(`${path} must be an object`)
    rejectUnknownKeys(value, SOURCE_BINDING_KEYS, path)

    const itemId = requireNonEmptyString(value.itemId, `${path}.itemId`)
    const itemIndex = itemIndexes.get(itemId)
    if (itemIndex === undefined)
      throw new Error(`${path}.itemId must reference an item in $.items`)
    if (itemIds.has(itemId))
      throw new Error(`${path}.itemId must be unique within $.sourceBindings`)
    itemIds.add(itemId)

    const rawSelector = requireNonEmptyString(value.selector, `${path}.selector`)
    const selector = rawSelector.trim()
    if (!selector)
      throw new Error(`${path}.selector must be a non-empty string`)
    const queryContext = value.queryContext === undefined
      ? defaultQueryContext
      : normalizeQueryContext(value.queryContext, `${path}.queryContext`)
    const queryContextPath = value.queryContext === undefined
      ? '$.queryContext'
      : `${path}.queryContext`
    const contextKey = queryContext === undefined ? ROOT_QUERY_CONTEXT : queryContext
    let selectors = selectorsByContext.get(contextKey)
    if (!selectors) {
      selectors = new Set()
      selectorsByContext.set(contextKey, selectors)
    }
    if (selectors.has(selector))
      throw new Error(`${path}.selector must be unique within $.sourceBindings`)
    selectors.add(selector)

    const objectFit = value.objectFit === undefined ? 'cover' : value.objectFit
    if (!['contain', 'cover', 'fill'].includes(objectFit))
      throw new Error(`${path}.objectFit contains an unsupported value`)
    const cornerRadius = value.cornerRadius === undefined ? 0 : value.cornerRadius
    if (typeof cornerRadius !== 'number' || !Number.isFinite(cornerRadius) || cornerRadius < 0)
      throw new Error(`${path}.cornerRadius must be a non-negative finite number`)
    return {
      itemId,
      itemIndex,
      selector,
      objectFit,
      cornerRadius,
      queryContext,
      queryContextPath,
    }
  })
}

function normalizeInitialIndex(options, items) {
  if (options.index !== undefined && options.initialItemId !== undefined)
    throw new Error('$.initialItemId cannot be combined with $.index')
  if (options.initialItemId === undefined) {
    const index = options.index === undefined ? 0 : options.index
    if (!Number.isInteger(index) || index < 0 || index >= items.length)
      throw new Error('$.index must reference an item in $.items')
    return index
  }

  const initialItemId = requireNonEmptyString(options.initialItemId, '$.initialItemId')
  const index = items.findIndex(item => item.id === initialItemId)
  if (index < 0)
    throw new Error('$.initialItemId must reference an item in $.items')
  return index
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
  const transport = getNativeTransport()
  try {
    const subscribed = transport.subscribe((event) => {
      eventListeners.forEach((listener) => {
        try {
          listener(event)
        }
        catch (_) {}
      })
    })
    if (subscribed !== false)
      eventChannelStarted = true
  }
  catch (_) {}
}

export function __setLevixelNativeTransport(transport) {
  if (!transport || typeof transport.invoke !== 'function' || typeof transport.subscribe !== 'function')
    throw new Error('Levixel native transport must implement invoke and subscribe')
  if (eventChannelStarted)
    throw new Error('Levixel native transport must be configured before event subscription')
  injectedNativeTransport = transport
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
  // Warmup only records dimensions supplied by a completed source-image load.
  // Stable local previews are created exclusively by prepareLevixelItem.
  if (loadedInfo)
    cacheImageInfo(url, loadedInfo)
  return Promise.resolve()
}

export async function openLevixelFromSelector(options) {
  if (!options || typeof options !== 'object' || Array.isArray(options))
    throw new Error('$ must be an object')
  rejectUnknownKeys(options, SELECTOR_OPEN_KEYS, '$')
  const items = sanitizeItems(options.items)
  const index = normalizeInitialIndex(options, items)
  const theme = options.theme === undefined ? 'dark' : options.theme
  if (theme !== 'dark' && theme !== 'light')
    throw new Error('$.theme contains an unsupported value')
  const sourceVisibility = options.sourceVisibility === undefined ? 'visible' : options.sourceVisibility
  if (sourceVisibility !== 'visible' && sourceVisibility !== 'hidden')
    throw new Error('$.sourceVisibility contains an unsupported value')
  if (options.sourceBindings !== undefined
    && (options.sourceSelector !== undefined || options.sourceStyles !== undefined))
    throw new Error('$.sourceBindings cannot be combined with sourceSelector or sourceStyles')

  const sourceSelector = options.sourceSelector === undefined
    ? undefined
    : requireNonEmptyString(options.sourceSelector, '$.sourceSelector').trim()
  if (options.sourceStyles !== undefined && sourceSelector === undefined)
    throw new Error('$.sourceStyles requires $.sourceSelector')
  if (options.queryContext !== undefined
    && sourceSelector === undefined
    && options.sourceBindings === undefined)
    throw new Error('$.queryContext requires $.sourceSelector or $.sourceBindings')

  const queryContext = normalizeQueryContext(options.queryContext, '$.queryContext')
  const sourceBindings = normalizeSourceBindings(options.sourceBindings, items, queryContext)
  const sourceStyles = sourceBindings === undefined
    ? normalizeSourceStyles(options.sourceStyles, items.length)
    : Array.from({ length: items.length }, () => ({ objectFit: 'cover', cornerRadius: 0 }))
  sourceBindings?.forEach((binding) => {
    sourceStyles[binding.itemIndex] = {
      objectFit: binding.objectFit,
      cornerRadius: binding.cornerRadius,
    }
  })
  const rectScale = readSourceRectScale()
  const previewURLs = items.map(transitionURL)
  const selectedPreviewURL = previewURLs[index]
  const selectedPreviewPromise = selectedPreviewURL
    ? ensureStableImageInfo(selectedPreviewURL, true)
    : Promise.resolve(undefined)

  const [rects, initialInfo] = await Promise.all([
    sourceBindings === undefined
      ? measureSources(sourceSelector, items.length, queryContext)
      : measureSourceBindings(sourceBindings, items.length),
    selectedPreviewURL
      ? withTimeout(selectedPreviewPromise, INITIAL_PREVIEW_TIMEOUT_MS)
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
