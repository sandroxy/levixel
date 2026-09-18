import { requireNativeView } from 'expo';
import * as React from 'react';
import { Platform, StyleSheet, type NativeSyntheticEvent, type ViewProps } from 'react-native';
import { normalizeActionOptions, normalizeMediaItems, resolveSourceCornerRadius, resolveSourceIndex } from './contract';
import { LevixelSessions } from './session';
import type { LevixelAction, LevixelActionLayout, LevixelEvent, LevixelProps, LevixelRef, LevixelSourceProps, LevixelTheme, NativeLevixelMediaItem } from './types';

interface NativeOpenOptions {
  requestId: string;
  sourceId?: string;
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
  sourceId?: string;
  index?: number;
  items?: NativeLevixelMediaItem[];
  sourceCornerRadius?: number;
  isController?: boolean;
  onControllerReady?: () => void;
  onSourcePress?: (event: NativeSyntheticEvent<{ itemId: string; sourceId: string }>) => void;
  onViewerEvent?: (event: NativeSyntheticEvent<LevixelEvent & { requestId: string }>) => void;
}
interface ContextValue {
  galleryId: string;
  items: NativeLevixelMediaItem[];
  open(itemId: string, sourceId?: string): Promise<void>;
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
  const [mount] = React.useState(() => ({
    ready: Platform.OS !== 'android',
    waiting: new Set<(view: NativeController | null) => void>(),
  }));
  const setNative = React.useCallback((view: NativeController | null) => {
    native.current = view;
    if (view === null) {
      mount.ready = Platform.OS !== 'android';
      for (const resolve of mount.waiting) resolve(null);
      mount.waiting.clear();
    }
  }, [mount]);
  const controller = React.useCallback(async () => {
    if (native.current === null || mount.ready) return native.current;
    // A JS ref can precede the native mount. Wait for the actual attachment,
    // not a timer or a future host UI update; unmount releases pending calls.
    return new Promise<NativeController | null>(resolve => mount.waiting.add(resolve));
  }, [mount]);
  const normalizedItems = React.useMemo(() => normalizeMediaItems(items), [items]);
  const actionOptions = React.useMemo(() => normalizeActionOptions(actions, actionLayout, actionListIcons),
    [actions, actionLayout, actionListIcons]);
  const normalizedActions = actionOptions.actions;
  const resolvedGalleryId = galleryId?.trim() || generatedGalleryId;
  if (theme !== 'dark' && theme !== 'light') throw new TypeError('[Levixel] theme must be dark or light.');
  const open = React.useCallback(async (itemId: string, sourceId?: string) => {
    const index = resolveSourceIndex(normalizedItems, { itemId });
    const view = await controller();
    if (view === null || native.current !== view) throw new Error('[Levixel] Levixel is not mounted.');
    const requestId = uniqueId();
    sessions.begin(requestId, normalizedActions);
    try {
      await view.open({
        requestId, galleryId: resolvedGalleryId, index, theme,
        ...(sourceId === undefined ? {} : { sourceId }),
        items: normalizedItems.map(item => ({ ...item })),
        actions: normalizedActions.map(({ onPress: _callback, ...action }) => action),
        actionLayout: actionOptions.actionLayout,
        actionListIcons: actionOptions.actionListIcons,
      });
    } catch (error) { sessions.end(requestId); throw error; }
  }, [normalizedItems, normalizedActions, actionOptions, resolvedGalleryId, sessions, theme, controller]);
  React.useImperativeHandle(ref, () => ({
    open(itemId: string) { return open(itemId); },
    async close() {
      const view = await controller();
      if (native.current === view) await view?.close();
    },
    async retry() {
      const view = await controller();
      return native.current === view ? await view?.retry() ?? false : false;
    },
  }), [open, controller]);
  const value = React.useMemo(() => ({ galleryId: resolvedGalleryId, items: normalizedItems, open }),
    [resolvedGalleryId, normalizedItems, open]);
  return (
    <LevixelContext.Provider value={value}>
      <NativeSource ref={setNative} collapsable={false} pointerEvents="none" accessible={false}
        style={{ width: 0, height: 0, position: 'absolute' }}
        {...(Platform.OS === 'android' ? {
          isController: true,
          onControllerReady: () => {
            if (native.current === null) return;
            mount.ready = true;
            for (const resolve of mount.waiting) resolve(native.current);
            mount.waiting.clear();
          },
        } : {})}
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
  const [sourceId] = React.useState(uniqueId);
  const context = React.useContext(LevixelContext);
  if (context === null) throw new Error('[Levixel] Levixel.Source must be rendered inside Levixel.');
  const { children, style } = props;
  const index = resolveSourceIndex(context.items, props);
  const sourceCornerRadius = resolveSourceCornerRadius(StyleSheet.flatten(style) as Readonly<Record<string, unknown>> | undefined);
  return (
    <NativeSource collapsable={false} galleryId={context.galleryId} sourceId={sourceId} index={index}
      items={context.items} sourceCornerRadius={sourceCornerRadius} style={style}
      onSourcePress={({ nativeEvent }) => {
        if (nativeEvent.sourceId !== sourceId || nativeEvent.itemId !== context.items[index].id) return;
        void context.open(nativeEvent.itemId, sourceId).catch(error => console.warn('[Levixel] Could not open viewer.', error));
      }}>
      {React.Children.only(children)}
    </NativeSource>
  );
}

export const Levixel = Object.assign(LevixelProvider, { Source: LevixelSource });
