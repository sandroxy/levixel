export type LevixelMediaType = 'image' | 'video';
export type LevixelTheme = 'dark' | 'light';
export type LevixelObjectFit = 'contain' | 'cover' | 'fill';
export type LevixelSourceVisibility = 'hidden' | 'visible';

export interface LevixelMediaItem {
  id: string;
  type: LevixelMediaType;
  url: string;
  thumbnailUrl?: string;
  posterUrl?: string;
  width?: number;
  height?: number;
  alt?: string;
}

export interface LevixelRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface LevixelSize {
  width: number;
  height: number;
}

export interface LevixelSourceHint {
  rect: LevixelRect;
  imageSize?: LevixelSize;
  objectFit: LevixelObjectFit;
  coordinateSpace: 'screen' | 'viewport';
  rectScale?: number;
  cornerRadius?: number;
}

export interface LevixelOpenOptions {
  items: LevixelMediaItem[];
  index?: number;
  theme?: LevixelTheme;
  sourceHints?: Array<LevixelSourceHint | null>;
  /** Web defaults to `hidden`, matching the standalone native viewers. */
  sourceVisibility?: LevixelSourceVisibility;
  counter?: false;
  closeButton?: false;
}

export interface LevixelSelectorSourceStyle {
  objectFit?: LevixelObjectFit;
  cornerRadius?: number;
}

export interface LevixelPrepareOptions {
  priority?: boolean;
}

export interface LevixelPreparedPreview {
  src: string;
  width: number;
  height: number;
}

export interface LevixelSelectorOpenOptions {
  items: LevixelMediaItem[];
  index?: number;
  theme?: LevixelTheme;
  sourceVisibility?: LevixelSourceVisibility;
  sourceSelector?: string;
  sourceStyles?: LevixelSelectorSourceStyle[];
}

export interface LevixelEvent {
  type: 'ready' | 'indexChange' | 'sourceVisibilityChange' | 'dismiss';
  payload: Record<string, unknown>;
  time: number;
}

export interface LevixelOpenResult {
  index: number;
  count: number;
  galleryId: string;
}

export interface LevixelCloseResult {
  closed: true;
}

export interface NormalizedOpenOptions {
  items: LevixelMediaItem[];
  index: number;
  theme: LevixelTheme;
  sourceHints: Array<LevixelSourceHint | null>;
  sourceVisibility: LevixelSourceVisibility;
}

export interface NormalizedSelectorOpenOptions {
  items: LevixelMediaItem[];
  index: number;
  theme: LevixelTheme;
  sourceVisibility: LevixelSourceVisibility;
  sourceSelector?: string;
  sourceStyles: LevixelSelectorSourceStyle[];
}

export interface ImageInfo extends LevixelPreparedPreview {}

export interface SourceBinding {
  element: HTMLElement | null;
  hint: LevixelSourceHint | null;
  preview?: ImageInfo;
}
