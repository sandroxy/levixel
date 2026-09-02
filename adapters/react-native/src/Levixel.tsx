import { requireNativeView } from 'expo';
import * as React from 'react';
import { createContext, useContext, useMemo, useState } from 'react';
import type { NativeSyntheticEvent, ViewProps } from 'react-native';

import { normalizeMediaItems, resolveSourceIndex } from './contract';
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
  onIndexChange?: (index: number, itemId: string) => void;
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
      ...(onIndexChange === undefined ? {} : { onIndexChange }),
    }),
    [normalizedItems, onIndexChange, resolvedGalleryId, theme],
  );

  return (
    <LevixelContext.Provider value={value}>{children}</LevixelContext.Provider>
  );
}

function LevixelSource(props: LevixelSourceProps) {
  const context = useContext(LevixelContext);
  if (context === null) {
    throw new Error('[Levixel] Levixel.Source must be rendered inside Levixel.');
  }
  const { children, style } = props;
  const index = resolveSourceIndex(context.items, props);

  return (
    <NativeLevixelSource
      collapsable={false}
      galleryId={context.galleryId}
      index={index}
      items={context.items}
      onIndexChange={(event) => {
        context.onIndexChange?.(
          event.nativeEvent.currentIndex,
          event.nativeEvent.itemId,
        );
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
