import {
  closeLevixelNative,
  onLevixelNativeEvent,
  openLevixelNative,
  resolveLevixelNativePaths,
} from '@/uni_modules/Sandrox-Levixel'
import {
  __setLevixelNativeTransport,
  closeLevixel as closeLevixelCanonical,
  onLevixelEvent as onLevixelEventCanonical,
  openLevixel as openLevixelCanonical,
  openLevixelFromSelector as openLevixelFromSelectorCanonical,
  prepareLevixelItem as prepareLevixelItemCanonical,
  warmupLevixelItem as warmupLevixelItemCanonical,
} from './canonical.js'

const OPTIONAL_ITEM_KEYS = ['thumbnailUrl', 'posterUrl', 'width', 'height', 'alt']
const OPTIONAL_OPEN_KEYS = [
  'index',
  'initialItemId',
  'theme',
  'sourceHints',
  'sourceVisibility',
  'counter',
  'closeButton',
  'sourceSelector',
  'sourceStyles',
  'sourceBindings',
  'queryContext',
]
const OPTIONAL_SOURCE_HINT_KEYS = ['imageSize', 'rectScale', 'cornerRadius']
const OPTIONAL_SOURCE_STYLE_KEYS = ['objectFit', 'cornerRadius']
const OPTIONAL_SOURCE_BINDING_KEYS = ['objectFit', 'cornerRadius', 'queryContext']
const NATIVE_PATH_RESOLUTION_TIMEOUT_MS = 5000

function omitNullOptionalFields(value, optionalKeys) {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    return value

  let normalized
  optionalKeys.forEach((key) => {
    if (value[key] !== null)
      return
    if (!normalized)
      normalized = { ...value }
    delete normalized[key]
  })
  return normalized || value
}

function normalizeArrayEntries(value, normalizeEntry) {
  if (!Array.isArray(value))
    return value

  let normalized
  value.forEach((entry, index) => {
    const candidate = normalizeEntry(entry)
    if (candidate === entry)
      return
    if (!normalized)
      normalized = value.slice()
    normalized[index] = candidate
  })
  return normalized || value
}

function normalizeMediaItem(item) {
  return omitNullOptionalFields(item, OPTIONAL_ITEM_KEYS)
}

function normalizeSourceHint(hint) {
  return omitNullOptionalFields(hint, OPTIONAL_SOURCE_HINT_KEYS)
}

function normalizeSourceStyle(style) {
  return omitNullOptionalFields(style, OPTIONAL_SOURCE_STYLE_KEYS)
}

function normalizeSourceBinding(binding) {
  return omitNullOptionalFields(binding, OPTIONAL_SOURCE_BINDING_KEYS)
}

function normalizeOpenOptions(options) {
  let normalized = omitNullOptionalFields(options, OPTIONAL_OPEN_KEYS)
  if (!normalized || typeof normalized !== 'object' || Array.isArray(normalized))
    return normalized

  const items = normalizeArrayEntries(normalized.items, normalizeMediaItem)
  const sourceHints = normalizeArrayEntries(normalized.sourceHints, normalizeSourceHint)
  const sourceStyles = normalizeArrayEntries(normalized.sourceStyles, normalizeSourceStyle)
  const sourceBindings = normalizeArrayEntries(normalized.sourceBindings, normalizeSourceBinding)
  if (items === normalized.items
    && sourceHints === normalized.sourceHints
    && sourceStyles === normalized.sourceStyles
    && sourceBindings === normalized.sourceBindings)
    return normalized

  normalized = { ...normalized }
  if (items !== normalized.items)
    normalized.items = items
  if (sourceHints !== normalized.sourceHints)
    normalized.sourceHints = sourceHints
  if (sourceStyles !== normalized.sourceStyles)
    normalized.sourceStyles = sourceStyles
  if (sourceBindings !== normalized.sourceBindings)
    normalized.sourceBindings = sourceBindings
  return normalized
}

function normalizePrepareOptions(options) {
  if (options === null)
    return {}
  return omitNullOptionalFields(options, ['priority'])
}

const nativeMethods = {
  open: openLevixelNative,
  close: closeLevixelNative,
}

function decodeNativeJSON(json, kind) {
  if (typeof json !== 'string')
    throw new Error(`Levixel ${kind} must be a JSON string`)
  return JSON.parse(json)
}

function decodeResolvedPaths(json, originalPaths) {
  const resolvedPaths = decodeNativeJSON(json, 'resolved paths')
  if (!Array.isArray(resolvedPaths) || resolvedPaths.length !== originalPaths.length)
    throw new Error('Levixel resolved paths must match the request length')
  return resolvedPaths.map((path, index) => (
    typeof path === 'string' && path.length > 0 ? path : originalPaths[index]
  ))
}

__setLevixelNativeTransport({
  invoke(method, options) {
    const nativeMethod = nativeMethods[method]
    if (typeof nativeMethod !== 'function')
      return Promise.reject(new Error(`Levixel native method ${method} is unavailable`))

    return new Promise((resolve, reject) => {
      try {
        nativeMethod(JSON.stringify(options), (resultJson) => {
          try {
            resolve(decodeNativeJSON(resultJson, 'result'))
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
  },
  resolvePaths(paths) {
    return new Promise((resolve) => {
      let settled = false
      const fallbackPaths = paths.slice()
      let timeoutId
      const finish = (resolvedPaths) => {
        if (settled)
          return
        settled = true
        if (timeoutId !== undefined)
          clearTimeout(timeoutId)
        resolve(resolvedPaths)
      }
      timeoutId = setTimeout(() => finish(fallbackPaths), NATIVE_PATH_RESOLUTION_TIMEOUT_MS)
      try {
        resolveLevixelNativePaths(JSON.stringify(paths), (resultJson) => {
          try {
            finish(decodeResolvedPaths(resultJson, fallbackPaths))
          }
          catch (_) {
            finish(fallbackPaths)
          }
        })
      }
      catch (_) {
        finish(fallbackPaths)
      }
    })
  },
  subscribe(listener) {
    onLevixelNativeEvent((eventJson) => {
      try {
        listener(decodeNativeJSON(eventJson, 'event'))
      }
      catch (_) {}
    })
    return true
  },
})

function openLevixel(options) {
  return openLevixelCanonical(normalizeOpenOptions(options))
}

function closeLevixel() {
  return closeLevixelCanonical()
}

function onLevixelEvent(listener) {
  return onLevixelEventCanonical(listener)
}

function prepareLevixelItem(item, options) {
  return prepareLevixelItemCanonical(
    normalizeMediaItem(item),
    normalizePrepareOptions(options),
  )
}

function warmupLevixelItem(item, loadEvent) {
  return warmupLevixelItemCanonical(normalizeMediaItem(item), loadEvent)
}

function openLevixelFromSelector(options) {
  return openLevixelFromSelectorCanonical(normalizeOpenOptions(options))
}

const levixel = {
  open: openLevixel,
  close: closeLevixel,
  onEvent: onLevixelEvent,
  prepareItem: prepareLevixelItem,
  warmupItem: warmupLevixelItem,
  openFromSelector: openLevixelFromSelector,
}

export {
  closeLevixel,
  onLevixelEvent,
  openLevixel,
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
}

export default levixel
