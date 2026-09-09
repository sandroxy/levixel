import { requireNativeView } from 'expo';
import * as React from 'react';
import { StyleSheet, type NativeSyntheticEvent, type ViewProps } from 'react-native';
import { normalizeActionOptions, normalizeMediaItems, resolveSourceCornerRadius, resolveSourceIndex } from './contract';
import { LevixelSessions } from './session';
import type { LevixelAction, LevixelActionLayout, LevixelEvent, LevixelProps, LevixelRef, LevixelSourceProps, LevixelTheme, NativeLevixelMediaItem } from './types';

interface NativeOpenOptions {
  requestId: string;
  galleryId: string;
  items: NativeLevixelMediaItem[];
  index: number;
  theme: LevixelTheme;
  actions: Omit<LevixelAction, 'onPress'>[];
  actionLayout: LevixelActionLayout;
  actionListIcons: boolean;
}
interface NativeController {
  open(options: NativeOpenOptions): Promise<void>;
  close(): Promise<void>;
  retry(): Promise<boolean>;
}
interface NativeSourceProps extends ViewProps {
  ref?: React.Ref<NativeController>;
  galleryId?: string;
  index?: number;
  items?: NativeLevixelMediaItem[];
  sourceCornerRadius?: number;
  onSourcePress?: (event: NativeSyntheticEvent<{ itemId: string }>) => void;
  onViewerEvent?: (event: NativeSyntheticEvent<LevixelEvent & { requestId: string }>) => void;
}
interface ContextValue {
  galleryId: string;
  items: NativeLevixelMediaItem[];
  open(itemId: string): Promise<void>;
}
const LevixelContext = React.createContext<ContextValue | null>(null);
const NativeSource = requireNativeView<NativeSourceProps>('Levixel');
let sequence = 0;
const uniqueId = () => `levixel-rn-${Date.now().toString(36)}-${(++sequence).toString(36)}`;

const LevixelProvider = React.forwardRef<LevixelRef, LevixelProps>(function LevixelProvider({
  items, children, galleryId, theme = 'dark', actions, actionLayout, actionListIcons, onEvent, onIndexChange,
}, ref) {
  const [generatedGalleryId] = React.useState(uniqueId);
  const [sessions] = React.useState(() => new LevixelSessions());
  const native = React.useRef<NativeController>(null);
  const normalizedItems = React.useMemo(() => normalizeMediaItems(items), [items]);
  const actionOptions = React.useMemo(() => normalizeActionOptions(actions, actionLayout, actionListIcons),
    [actions, actionLayout, actionListIcons]);
  const normalizedActions = actionOptions.actions;
  const resolvedGalleryId = galleryId?.trim() || generatedGalleryId;
  if (theme !== 'dark' && theme !== 'light') throw new TypeError('[Levixel] theme must be dark or light.');
  const open = React.useCallback(async (itemId: string) => {
    const index = resolveSourceIndex(normalizedItems, { itemId });
    if (native.current === null) throw new Error('[Levixel] Levixel is not mounted.');
    const requestId = uniqueId();
    sessions.begin(requestId, normalizedActions);
    try {
      await native.current.open({
        requestId, galleryId: resolvedGalleryId, index, theme,
        items: normalizedItems.map(item => ({ ...item })),
        actions: normalizedActions.map(({ onPress: _callback, ...action }) => action),
        actionLayout: actionOptions.actionLayout,
        actionListIcons: actionOptions.actionListIcons,
      });
    } catch (error) { sessions.end(requestId); throw error; }
  }, [normalizedItems, normalizedActions, actionOptions, resolvedGalleryId, sessions, theme]);
  React.useImperativeHandle(ref, () => ({
    open,
    async close() { await native.current?.close(); },
    async retry() { return await native.current?.retry() ?? false; },
  }), [open]);
  const value = React.useMemo(() => ({ galleryId: resolvedGalleryId, items: normalizedItems, open }),
    [resolvedGalleryId, normalizedItems, open]);
  return (
    <LevixelContext.Provider value={value}>
      <NativeSource ref={native} collapsable={false} pointerEvents="none" accessible={false}
        style={{ width: 0, height: 0, position: 'absolute' }}
        onViewerEvent={({ nativeEvent }) => {
          const { requestId, ...event } = nativeEvent;
          sessions.dispatch(requestId, event as LevixelEvent, event => {
            if (event.type === 'indexChange') onIndexChange?.(event.payload.currentIndex, event.payload.itemId);
            onEvent?.(event);
          });
        }} />
      {children}
    </LevixelContext.Provider>
  );
});

function LevixelSource(props: LevixelSourceProps) {
  const context = React.useContext(LevixelContext);
  if (context === null) throw new Error('[Levixel] Levixel.Source must be rendered inside Levixel.');
  const { children, style } = props;
  const index = resolveSourceIndex(context.items, props);
  const sourceCornerRadius = resolveSourceCornerRadius(StyleSheet.flatten(style) as Readonly<Record<string, unknown>> | undefined);
  return (
    <NativeSource collapsable={false} galleryId={context.galleryId} index={index}
      items={context.items} sourceCornerRadius={sourceCornerRadius} style={style}
      onSourcePress={({ nativeEvent }) => {
        void context.open(nativeEvent.itemId).catch(error => console.warn('[Levixel] Could not open viewer.', error));
      }}>
      {React.Children.only(children)}
    </NativeSource>
  );
}

export const Levixel = Object.assign(LevixelProvider, { Source: LevixelSource });
