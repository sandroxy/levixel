import type { ReactElement, ReactNode } from 'react';
import type { ViewProps } from 'react-native';

export type LevixelTheme = 'dark' | 'light';

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

export interface LevixelProps {
  items: readonly LevixelMediaItem[];
  children: ReactNode;
  galleryId?: string;
  theme?: LevixelTheme;
  onIndexChange?: (index: number) => void;
}

export interface LevixelSourceProps extends Pick<ViewProps, 'style'> {
  index: number;
  children: ReactElement;
}

export interface LevixelIndexChangePayload {
  currentIndex: number;
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
