export type LevixelMediaType = 'image' | 'video'
export type LevixelTheme = 'dark' | 'light'
export type LevixelObjectFit = 'contain' | 'cover' | 'fill'
export type LevixelSourceVisibility = 'hidden' | 'visible'

export interface LevixelMediaItem {
  id: string
  type: LevixelMediaType
  url: string
  thumbnailUrl?: string
  posterUrl?: string
  width?: number
  height?: number
  alt?: string
}

export interface LevixelSourceHint {
  rect: { left: number, top: number, width: number, height: number }
  imageSize?: { width: number, height: number }
  objectFit: LevixelObjectFit
  coordinateSpace: 'screen' | 'viewport'
  rectScale?: number
  cornerRadius?: number
}

export interface LevixelOpenOptions {
  items: LevixelMediaItem[]
  index?: number
  theme?: LevixelTheme
  sourceHints?: Array<LevixelSourceHint | null>
  sourceVisibility?: LevixelSourceVisibility
  counter?: false
  closeButton?: false
}

export interface LevixelSelectorSourceStyle {
  objectFit?: LevixelObjectFit
  cornerRadius?: number
}

export interface LevixelSelectorSourceBinding extends LevixelSelectorSourceStyle {
  itemId: string
  selector: string
  queryContext?: unknown
}

export interface LevixelPrepareOptions {
  priority?: boolean
}

export interface LevixelPreparedPreview {
  src: string
  width: number
  height: number
}

export interface LevixelOpenResult {
  index: number
  itemId: string
  count: number
  galleryId: string
}

export interface LevixelCloseResult {
  closed: true
}

interface LevixelSelectorOpenOptionsBase {
  items: LevixelMediaItem[]
  theme?: LevixelTheme
  sourceVisibility?: LevixelSourceVisibility
}

type LevixelSelectorInitialSelection =
  | { index?: number, initialItemId?: never }
  | { index?: never, initialItemId: string }

type LevixelSelectorSources =
  | {
      sourceSelector?: never
      sourceStyles?: never
      sourceBindings?: never
      queryContext?: never
    }
  | {
      sourceSelector: string
      sourceStyles?: LevixelSelectorSourceStyle[]
      sourceBindings?: never
      queryContext?: unknown
    }
  | {
      sourceSelector?: never
      sourceStyles?: never
      sourceBindings: LevixelSelectorSourceBinding[]
      queryContext?: unknown
    }

export type LevixelSelectorOpenOptions = LevixelSelectorOpenOptionsBase
  & LevixelSelectorInitialSelection
  & LevixelSelectorSources

export type LevixelEvent =
  | { type: 'ready', payload: Record<string, unknown>, time: number }
  | {
      type: 'indexChange'
      payload: { currentIndex: number, itemId: string }
      time: number
    }
  | {
      type: 'sourceVisibilityChange'
      payload: { hidden: boolean, index: number, itemId: string, galleryId: string }
      time: number
    }
  | { type: 'dismiss', payload: Record<string, never>, time: number }

export function openLevixel(options: LevixelOpenOptions): Promise<LevixelOpenResult>
export function closeLevixel(): Promise<LevixelCloseResult>
export function onLevixelEvent(listener: (event: LevixelEvent) => void): () => void
export function prepareLevixelItem(
  item: LevixelMediaItem,
  options?: LevixelPrepareOptions,
): Promise<LevixelPreparedPreview | undefined>
export function warmupLevixelItem(item: LevixelMediaItem, loadEvent?: unknown): Promise<void>
export function openLevixelFromSelector(
  options: LevixelSelectorOpenOptions,
): Promise<LevixelOpenResult>

declare const levixel: {
  open: typeof openLevixel
  close: typeof closeLevixel
  onEvent: typeof onLevixelEvent
  prepareItem: typeof prepareLevixelItem
  warmupItem: typeof warmupLevixelItem
  openFromSelector: typeof openLevixelFromSelector
}

export default levixel
