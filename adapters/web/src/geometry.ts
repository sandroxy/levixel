import type { LevixelObjectFit, LevixelRect, LevixelSize, LevixelSourceHint } from './types.js';

export interface ViewportMetrics extends LevixelRect {}

export interface SharedElementGeometry {
  visible: LevixelRect;
  content: LevixelRect;
  cornerRadius: number;
}

export interface ImageLayout {
  width: number;
  height: number;
  minimumAbsoluteScale: number;
  maximumRelativeZoom: number;
}

export interface ZoomedViewportState {
  relativeZoom: number;
  normalizedCenter: { x: number; y: number };
}

const EPSILON = 0.5;

export function clamp(value: number, lower: number, upper: number): number {
  return Math.min(Math.max(value, lower), upper);
}

export function currentViewport(): ViewportMetrics {
  const viewport = window.visualViewport;
  return {
    left: viewport?.offsetLeft ?? 0,
    top: viewport?.offsetTop ?? 0,
    width: Math.max(1, viewport?.width ?? window.innerWidth),
    height: Math.max(1, viewport?.height ?? window.innerHeight),
  };
}

export function isUsableRect(rect: LevixelRect | null | undefined): rect is LevixelRect {
  return Boolean(
    rect
      && [rect.left, rect.top, rect.width, rect.height].every(Number.isFinite)
      && rect.width > 1
      && rect.height > 1,
  );
}

export function intersectRect(first: LevixelRect, second: LevixelRect): LevixelRect | null {
  const left = Math.max(first.left, second.left);
  const top = Math.max(first.top, second.top);
  const right = Math.min(first.left + first.width, second.left + second.width);
  const bottom = Math.min(first.top + first.height, second.top + second.height);
  const result = { left, top, width: right - left, height: bottom - top };
  return isUsableRect(result) ? result : null;
}

export function aspectFitRect(imageSize: LevixelSize, bounds: LevixelRect): LevixelRect {
  if (imageSize.width <= 0 || imageSize.height <= 0)
    return { ...bounds };
  const scale = Math.min(bounds.width / imageSize.width, bounds.height / imageSize.height);
  const width = imageSize.width * scale;
  const height = imageSize.height * scale;
  return {
    left: bounds.left + (bounds.width - width) / 2,
    top: bounds.top + (bounds.height - height) / 2,
    width,
    height,
  };
}

function normalizeHintRect(hint: LevixelSourceHint, viewport: ViewportMetrics): LevixelRect {
  const scale = hint.rectScale ?? 1;
  let left = hint.rect.left / scale;
  let top = hint.rect.top / scale;
  if (hint.coordinateSpace === 'screen') {
    left -= window.screenX;
    top -= window.screenY;
  }
  return {
    left: left - viewport.left,
    top: top - viewport.top,
    width: hint.rect.width / scale,
    height: hint.rect.height / scale,
  };
}

export function resolveSourceGeometry(
  hint: LevixelSourceHint,
  fallbackImageSize: LevixelSize | undefined,
  viewport: ViewportMetrics,
): SharedElementGeometry | null {
  const source = normalizeHintRect(hint, viewport);
  if (!isUsableRect(source))
    return null;
  const viewportBounds = { left: 0, top: 0, width: viewport.width, height: viewport.height };
  const clippedSource = intersectRect(source, viewportBounds);
  if (!clippedSource)
    return null;

  const imageSize = hint.imageSize ?? fallbackImageSize ?? {
    width: source.width,
    height: source.height,
  };
  const fitted = fittedContentRect(imageSize, source, hint.objectFit);
  const visible = intersectRect(clippedSource, fitted);
  if (!visible)
    return null;

  const fullContainerVisible = approximatelyEqual(visible.left, source.left)
    && approximatelyEqual(visible.top, source.top)
    && approximatelyEqual(visible.left + visible.width, source.left + source.width)
    && approximatelyEqual(visible.top + visible.height, source.top + source.height);
  const cornerRadius = fullContainerVisible
    ? Math.min(hint.cornerRadius ?? 0, source.width / 2, source.height / 2)
    : 0;
  return {
    visible,
    content: {
      left: fitted.left - visible.left,
      top: fitted.top - visible.top,
      width: fitted.width,
      height: fitted.height,
    },
    cornerRadius,
  };
}

export function fittedContentRect(
  imageSize: LevixelSize,
  container: LevixelRect,
  objectFit: LevixelObjectFit,
): LevixelRect {
  if (objectFit === 'fill')
    return { ...container };
  const widthScale = container.width / Math.max(1, imageSize.width);
  const heightScale = container.height / Math.max(1, imageSize.height);
  const scale = objectFit === 'cover'
    ? Math.max(widthScale, heightScale)
    : Math.min(widthScale, heightScale);
  const width = imageSize.width * scale;
  const height = imageSize.height * scale;
  return {
    left: container.left + (container.width - width) / 2,
    top: container.top + (container.height - height) / 2,
    width,
    height,
  };
}

export function imageLayout(imageSize: LevixelSize, viewportSize: LevixelSize): ImageLayout {
  const widthScale = viewportSize.width / imageSize.width;
  const heightScale = viewportSize.height / imageSize.height;
  const minimumAbsoluteScale = Math.min(widthScale, heightScale);
  const width = imageSize.width * minimumAbsoluteScale;
  const height = imageSize.height * minimumAbsoluteScale;
  const maximumAbsoluteScale = Math.max(minimumAbsoluteScale * 4, 3);
  return {
    width,
    height,
    minimumAbsoluteScale,
    maximumRelativeZoom: maximumAbsoluteScale / minimumAbsoluteScale,
  };
}

export function doubleTapRelativeZoom(layout: ImageLayout): number {
  return Math.min(
    layout.maximumRelativeZoom,
    Math.max(2.4, 2 / layout.minimumAbsoluteScale),
  );
}

export function captureZoomedViewport(
  relativeZoom: number,
  pan: { x: number; y: number },
  layout: Pick<ImageLayout, 'width' | 'height'>,
): ZoomedViewportState | null {
  if (relativeZoom <= 1.01 || layout.width <= 0 || layout.height <= 0)
    return null;
  return {
    relativeZoom,
    normalizedCenter: {
      x: clamp(0.5 - pan.x / (layout.width * relativeZoom), 0, 1),
      y: clamp(0.5 - pan.y / (layout.height * relativeZoom), 0, 1),
    },
  };
}

export function restoreZoomedViewport(
  state: ZoomedViewportState,
  layout: ImageLayout,
  viewportSize: LevixelSize,
): { zoom: number; pan: { x: number; y: number } } {
  const zoom = clamp(state.relativeZoom, 1, layout.maximumRelativeZoom);
  const pan = clampPan(
    {
      x: (0.5 - state.normalizedCenter.x) * layout.width * zoom,
      y: (0.5 - state.normalizedCenter.y) * layout.height * zoom,
    },
    zoom,
    layout,
    viewportSize,
  );
  return { zoom, pan };
}

export function clampPan(
  pan: { x: number; y: number },
  zoom: number,
  layout: Pick<ImageLayout, 'width' | 'height'>,
  viewportSize: LevixelSize,
): { x: number; y: number } {
  const maximumX = Math.max((layout.width * zoom - viewportSize.width) / 2, 0);
  const maximumY = Math.max((layout.height * zoom - viewportSize.height) / 2, 0);
  return {
    x: clamp(pan.x, -maximumX, maximumX),
    y: clamp(pan.y, -maximumY, maximumY),
  };
}

function approximatelyEqual(first: number, second: number): boolean {
  return Math.abs(first - second) <= EPSILON;
}
