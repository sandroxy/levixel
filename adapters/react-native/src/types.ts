import type { ReactElement, ReactNode } from 'react';
import type { ViewProps } from 'react-native';

export type LevixelTheme = 'dark' | 'light';
export type LevixelActionLayout = 'list' | 'grid';

interface LevixelMediaItemBase {
  id: string;
  url: string;
  width?: number;
  height?: number;
  alt?: string;
}

export interface LevixelImageItem extends LevixelMediaItemBase {
  type: 'image';
  thumbnailUrl?: string;
}

export interface LevixelVideoItem extends LevixelMediaItemBase {
  type: 'video';
  posterUrl?: string;
  thumbnailUrl?: string;
}

export type LevixelMediaItem = LevixelImageItem | LevixelVideoItem;

export interface LevixelMediaContext {
  sessionId: string;
  galleryId: string;
  index: number;
  itemId: string;
  mediaType: 'image' | 'video';
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

export type LevixelEvent =
  | { type: 'opened' | 'longPress' | 'mediaLoad' | 'dismiss'; payload: LevixelMediaContext; time: number }
  | { type: 'action'; payload: LevixelActionContext; time: number }
  | { type: 'indexChange'; payload: LevixelMediaContext & { currentIndex: number }; time: number }
  | { type: 'mediaError'; payload: LevixelMediaContext & { code: 'LOAD_FAILED'; message: string }; time: number };

export interface LevixelRef {
  open(itemId: string): Promise<void>;
  close(): Promise<void>;
  retry(): Promise<boolean>;
}

export interface LevixelProps {
  actions?: readonly LevixelAction[];
  /** Explicit layout, independent of action count. Defaults to 'list'. */
  actionLayout?: LevixelActionLayout;
  /** Show provided icons in list layout. Defaults to false; grid always shows icons. */
  actionListIcons?: boolean;
  onEvent?: (event: LevixelEvent) => void;
  items: readonly LevixelMediaItem[];
  children: ReactNode;
  galleryId?: string;
  theme?: LevixelTheme;
  onIndexChange?: (index: number, itemId: string) => void;
}

interface LevixelSourcePropsBase extends Pick<ViewProps, 'style'> {
  children: ReactElement;
}

type LevixelSourceSelection =
  | { index: number; itemId?: never }
  | { index?: never; itemId: string };

export type LevixelSourceProps = LevixelSourcePropsBase & LevixelSourceSelection;

export interface LevixelIndexChangePayload {
  currentIndex: number;
  itemId: string;
}

export interface NativeLevixelMediaItem {
  id: string;
  type: 'image' | 'video';
  url: string;
  thumbnailUrl?: string;
  posterUrl?: string;
  width?: number;
  height?: number;
  alt?: string;
}
