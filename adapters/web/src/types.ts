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

export interface LevixelSelectorSourceBinding extends LevixelSelectorSourceStyle {
  itemId: string;
  selector: string;
}

export interface LevixelPrepareOptions {
  priority?: boolean;
}

export interface LevixelPreparedPreview {
  src: string;
  width: number;
  height: number;
}

interface LevixelSelectorOpenOptionsBase {
  items: LevixelMediaItem[];
  theme?: LevixelTheme;
  sourceVisibility?: LevixelSourceVisibility;
}

type LevixelSelectorInitialSelection =
  | { index?: number; initialItemId?: never }
  | { index?: never; initialItemId: string };

type LevixelSelectorSources =
  | {
      sourceSelector?: never;
      sourceStyles?: never;
      sourceBindings?: never;
    }
  | {
      sourceSelector: string;
      sourceStyles?: LevixelSelectorSourceStyle[];
      sourceBindings?: never;
    }
  | {
      sourceSelector?: never;
      sourceStyles?: never;
      sourceBindings: LevixelSelectorSourceBinding[];
    };

export type LevixelSelectorOpenOptions = LevixelSelectorOpenOptionsBase
  & LevixelSelectorInitialSelection
  & LevixelSelectorSources;

export type LevixelEvent =
  | {
      type: 'ready';
      payload: Record<string, unknown>;
      time: number;
    }
  | {
      type: 'indexChange';
      payload: { currentIndex: number; itemId: string };
      time: number;
    }
  | {
      type: 'sourceVisibilityChange';
      payload: { hidden: boolean; index: number; itemId: string; galleryId: string };
      time: number;
    }
  | {
      type: 'dismiss';
      payload: Record<string, never>;
      time: number;
    };

export interface LevixelOpenResult {
  index: number;
  itemId: string;
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

interface NormalizedSelectorOpenOptionsBase {
  items: LevixelMediaItem[];
  index: number;
  theme: LevixelTheme;
  sourceVisibility: LevixelSourceVisibility;
}

export type NormalizedSelectorOpenOptions =
  | (NormalizedSelectorOpenOptionsBase & {
      sourceMode: 'positional';
      sourceSelector?: string;
      sourceStyles: LevixelSelectorSourceStyle[];
      sourceBindings?: never;
    })
  | (NormalizedSelectorOpenOptionsBase & {
      sourceMode: 'identified';
      sourceSelector?: never;
      sourceStyles?: never;
      sourceBindings: NormalizedSelectorSourceBinding[];
    });

export interface NormalizedSelectorSourceBinding {
  itemId: string;
  itemIndex: number;
  selector: string;
  objectFit: LevixelObjectFit;
  cornerRadius: number;
}

export interface ImageInfo extends LevixelPreparedPreview {}

export interface SourceBinding {
  element: HTMLElement | null;
  hint: LevixelSourceHint | null;
  preview?: ImageInfo;
  identitySelector?: string;
}
