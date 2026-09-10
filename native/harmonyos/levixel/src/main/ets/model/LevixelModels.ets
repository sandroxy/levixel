export enum LevixelMediaType {
  IMAGE = 'image',
  VIDEO = 'video'
}

export enum LevixelSourceImageFit {
  COVER = 'cover',
  CONTAIN = 'contain',
  FILL = 'fill'
}

export interface LevixelMediaItem {
  id: string;
  mediaType: LevixelMediaType;
  sourceUrl: string;
  thumbnailUrl: string;
  title: string;
  aspectWidth: number;
  aspectHeight: number;
}

export interface RectMetrics {
  left: number;
  top: number;
  width: number;
  height: number;
}

export function cloneRect(rect: RectMetrics): RectMetrics {
  return {
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height
  };
}

export interface LevixelMediaContext {
  sessionId: string;
  galleryId: string;
  index: number;
  itemId: string;
  mediaType: LevixelMediaType;
  currentIndex?: number;
  actionId?: string;
  code?: string;
  message?: string;
}

export interface LevixelViewerEvent {
  type: string;
  payload: LevixelMediaContext;
  time: number;
}

export type LevixelActionLayout = 'list' | 'grid';

export interface LevixelAction {
  id: string;
  label: string;
  icon?: string;
  group?: string;
  disabled?: boolean;
  destructive?: boolean;
  onPress?: (event: LevixelViewerEvent) => void;
}

export function snapshotLevixelActions(actions: LevixelAction[], layout: LevixelActionLayout = 'list'): LevixelAction[] {
  if (layout !== 'list' && layout !== 'grid') throw new Error('Levixel actionLayout must be list or grid.');
  const ids: Set<string> = new Set<string>();
  return actions.map((action: LevixelAction, index: number): LevixelAction => {
    if (action.id.trim().length === 0 || action.label.trim().length === 0 || ids.has(action.id) ||
      (action.icon !== undefined && action.icon.trim().length === 0) ||
      (action.group !== undefined && action.group.trim().length === 0)) {
      throw new Error('Levixel actions require unique non-blank IDs and non-blank text.');
    }
    if (layout === 'grid' && action.icon === undefined) {
      throw new Error(`Levixel actions[${index}].icon is required for grid actionLayout.`);
    }
    ids.add(action.id);
    return {
      id: action.id, label: action.label, icon: action.icon, group: action.group,
      disabled: action.disabled, destructive: action.destructive, onPress: action.onPress
    };
  });
}

export interface LevixelPanOffset { x: number; y: number; }

export function clampLevixelPan(scale: number, x: number, y: number, width: number, height: number,
  viewportWidth: number, viewportHeight: number): LevixelPanOffset {
  const maxX: number = Math.max(0, (width * scale - viewportWidth) / 2);
  const maxY: number = Math.max(0, (height * scale - viewportHeight) / 2);
  return { x: maxX === 0 ? 0 : Math.max(-maxX, Math.min(maxX, x)), y: maxY === 0 ? 0 : Math.max(-maxY, Math.min(maxY, y)) };
}

export function cloneLevixelViewerEvent(event: LevixelViewerEvent): LevixelViewerEvent {
  const source: LevixelMediaContext = event.payload;
  const payload: LevixelMediaContext = {
    sessionId: source.sessionId, galleryId: source.galleryId, index: source.index,
    itemId: source.itemId, mediaType: source.mediaType, currentIndex: source.currentIndex,
    actionId: source.actionId, code: source.code, message: source.message
  };
  return { type: event.type, payload: payload, time: event.time };
}
