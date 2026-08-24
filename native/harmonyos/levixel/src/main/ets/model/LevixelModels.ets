export enum LevixelMediaType {
  IMAGE = 'image',
  VIDEO = 'video'
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
