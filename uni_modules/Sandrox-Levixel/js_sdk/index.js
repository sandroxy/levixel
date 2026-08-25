import {
  closeLevixelNative,
  onLevixelNativeEvent,
  openLevixelNative,
} from '@/uni_modules/Sandrox-Levixel'
import levixel, {
  __setLevixelNativeTransport,
  closeLevixel,
  onLevixelEvent,
  openLevixel,
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
} from './canonical.js'

const nativeMethods = {
  open: openLevixelNative,
  close: closeLevixelNative,
}

function decodeNativeJSON(json, kind) {
  if (typeof json !== 'string')
    throw new Error(`Levixel ${kind} must be a JSON string`)
  return JSON.parse(json)
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

export {
  closeLevixel,
  onLevixelEvent,
  openLevixel,
  openLevixelFromSelector,
  prepareLevixelItem,
  warmupLevixelItem,
}

export default levixel
