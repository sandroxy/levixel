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

export interface LevixelSelectorOpenOptions {
  items: LevixelMediaItem[]
  index?: number
  theme?: LevixelTheme
  sourceVisibility?: LevixelSourceVisibility
  sourceSelector?: string
  sourceStyles?: LevixelSelectorSourceStyle[]
}

export interface LevixelEvent {
  type: 'ready' | 'indexChange' | 'sourceVisibilityChange' | 'dismiss'
  payload: Record<string, unknown>
  time: number
}

export function openLevixel(options: LevixelOpenOptions): Promise<Record<string, unknown>>
export function closeLevixel(): Promise<Record<string, unknown>>
export function onLevixelEvent(listener: (event: LevixelEvent) => void): () => void
export function warmupLevixelItem(item: LevixelMediaItem, loadEvent?: unknown): Promise<void>
export function openLevixelFromSelector(
  options: LevixelSelectorOpenOptions,
): Promise<Record<string, unknown>>

declare const levixel: {
  open: typeof openLevixel
  close: typeof closeLevixel
  onEvent: typeof onLevixelEvent
  warmupItem: typeof warmupLevixelItem
  openFromSelector: typeof openLevixelFromSelector
}

export default levixel
