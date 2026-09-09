export type LevixelMediaType = 'image' | 'video';
export type LevixelTheme = 'dark' | 'light';
export type LevixelActionLayout = 'list' | 'grid';
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

export interface LevixelMediaContext {
  sessionId: string;
  galleryId: string;
  index: number;
  itemId: string;
  mediaType: LevixelMediaType;
}

export interface LevixelActionContext extends LevixelMediaContext {
  actionId: string;
}

export interface LevixelAction {
  id: string;
  label: string;
  /** Image URI. Required for grid; optional for list. */
  icon?: string;
  group?: string;
  disabled?: boolean;
  destructive?: boolean;
  onPress?: (context: LevixelActionContext) => void;
}

export interface LevixelRetryResult { retried: boolean }

export interface LevixelOpenOptions {
  actions?: readonly LevixelAction[];
  /** Explicit layout, independent of action count. Defaults to 'list'. */
  actionLayout?: LevixelActionLayout;
  /** Show provided icons in list layout. Defaults to false; grid always shows icons. */
  actionListIcons?: boolean;
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
  actions?: readonly LevixelAction[];
  /** Explicit layout, independent of action count. Defaults to 'list'. */
  actionLayout?: LevixelActionLayout;
  /** Show provided icons in list layout. Defaults to false; grid always shows icons. */
  actionListIcons?: boolean;
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
  | { type: 'opened' | 'longPress' | 'mediaLoad'; payload: LevixelMediaContext; time: number }
  | { type: 'action'; payload: LevixelActionContext; time: number }
  | { type: 'mediaError'; payload: LevixelMediaContext & { code: 'LOAD_FAILED'; message: string }; time: number }
  | {
      type: 'ready';
      payload: Record<string, unknown>;
      time: number;
    }
  | {
      type: 'indexChange';
      payload: { currentIndex: number; itemId: string } & Partial<LevixelMediaContext>;
      time: number;
    }
  | {
      type: 'sourceVisibilityChange';
      payload: { hidden: boolean; index: number; itemId: string; galleryId: string };
      time: number;
    }
  | {
      type: 'dismiss';
      payload: LevixelMediaContext;
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
  actions: LevixelAction[];
  actionLayout: LevixelActionLayout;
  actionListIcons: boolean;
  items: LevixelMediaItem[];
  index: number;
  theme: LevixelTheme;
  sourceHints: Array<LevixelSourceHint | null>;
  sourceVisibility: LevixelSourceVisibility;
}

interface NormalizedSelectorOpenOptionsBase {
  actions: LevixelAction[];
  actionLayout: LevixelActionLayout;
  actionListIcons: boolean;
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
