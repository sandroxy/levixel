import { requireNativeView } from 'expo';
import * as React from 'react';
import { createContext, useContext, useMemo, useState } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

import { normalizeMediaItems } from './contract';
import type {
  LevixelIndexChangePayload,
  LevixelProps,
  LevixelSourceProps,
  LevixelTheme,
  NativeLevixelMediaItem,
} from './types';

interface LevixelContextValue {
  galleryId: string;
  items: NativeLevixelMediaItem[];
  theme: LevixelTheme;
  onIndexChange?: (index: number) => void;
}

interface NativeLevixelSourceProps extends ViewProps {
  galleryId: string;
  index: number;
  items: NativeLevixelMediaItem[];
  theme: LevixelTheme;
  onIndexChange?: (
    event: NativeSyntheticEvent<LevixelIndexChangePayload>,
  ) => void;
}

const LevixelContext = createContext<LevixelContextValue | null>(null);
const NativeLevixelSource =
  requireNativeView<NativeLevixelSourceProps>('Levixel');

let gallerySequence = 0;

function createGalleryId(): string {
  gallerySequence += 1;
  return `levixel-rn-${Date.now().toString(36)}-${gallerySequence.toString(36)}`;
}

function LevixelProvider({
  items,
  children,
  galleryId,
  theme = 'dark',
  onIndexChange,
}: LevixelProps) {
  const [generatedGalleryId] = useState(createGalleryId);
  const normalizedItems = useMemo(() => normalizeMediaItems(items), [items]);
  const resolvedGalleryId = galleryId?.trim() || generatedGalleryId;

  const value = useMemo<LevixelContextValue>(
    () => ({
      galleryId: resolvedGalleryId,
      items: normalizedItems,
      theme,
      onIndexChange,
    }),
    [normalizedItems, onIndexChange, resolvedGalleryId, theme],
  );

  return (
    <LevixelContext.Provider value={value}>{children}</LevixelContext.Provider>
  );
}

function LevixelSource({ index, children, style }: LevixelSourceProps) {
  const context = useContext(LevixelContext);
  if (context === null) {
    throw new Error('[Levixel] Levixel.Source must be rendered inside Levixel.');
  }
  if (!Number.isInteger(index) || index < 0 || index >= context.items.length) {
    throw new RangeError('[Levixel] Levixel.Source index is outside the items array.');
  }

  return (
    <NativeLevixelSource
      collapsable={false}
      galleryId={context.galleryId}
      index={index}
      items={context.items}
      onIndexChange={(event) => {
        context.onIndexChange?.(event.nativeEvent.currentIndex);
      }}
      style={style}
      theme={context.theme}
    >
      {React.Children.only(children)}
    </NativeLevixelSource>
  );
}

export const Levixel = Object.assign(LevixelProvider, {
  Source: LevixelSource,
});
