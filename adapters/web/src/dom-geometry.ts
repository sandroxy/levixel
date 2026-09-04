import { intersectRect, isUsableRect } from './geometry.js';
import type { LevixelRect } from './types.js';

export interface ElementSourceLayout {
  rect: LevixelRect;
  clippingRect: LevixelRect;
}

const CLIPPING_OVERFLOW = new Set(['auto', 'clip', 'hidden', 'overlay', 'scroll']);

export function resolveElementSourceLayout(
  element: HTMLElement,
  ignoreElementVisibility = false,
): ElementSourceLayout | null {
  if (!element.isConnected || element.getClientRects().length === 0)
    return null;

  const elementStyle = getComputedStyle(element);
  if (!isRenderedStyle(elementStyle, ignoreElementVisibility))
    return null;

  const rect = domRect(element.getBoundingClientRect());
  if (!isUsableRect(rect))
    return null;

  let clippingRect: LevixelRect | null = rect;
  let ancestor = element.parentElement;
  while (ancestor) {
    const style = getComputedStyle(ancestor);
    if (!isRenderedStyle(style, false))
      return null;

    const paintContainment = style.contain.split(/\s+/).some(value => (
      value === 'content' || value === 'paint' || value === 'strict'
    ));
    // Root overflow represents the viewport scrollport. The viewer locks that
    // scrollport while it is open, so treating it as an ordinary element clip
    // would offset the viewport by the document scroll position. Viewport
    // clipping is applied separately by resolveSourceGeometry.
    const rootViewport = ancestor === document.body || ancestor === document.documentElement;
    const clipX = paintContainment || (!rootViewport && CLIPPING_OVERFLOW.has(style.overflowX));
    const clipY = paintContainment || (!rootViewport && CLIPPING_OVERFLOW.has(style.overflowY));
    if (clipX || clipY) {
      clippingRect = intersectClippedAxes(
        clippingRect,
        clientRectInViewport(ancestor),
        clipX,
        clipY,
      );
      if (!clippingRect)
        return null;
    }
    ancestor = ancestor.parentElement;
  }

  return { rect, clippingRect };
}

function isRenderedStyle(style: CSSStyleDeclaration, ignoreVisibility: boolean): boolean {
  if (style.display === 'none' || style.contentVisibility === 'hidden')
    return false;
  if (!ignoreVisibility && (style.visibility === 'hidden' || style.visibility === 'collapse'))
    return false;
  const opacity = Number.parseFloat(style.opacity);
  return !Number.isFinite(opacity) || opacity > 0.001;
}

function domRect(rect: DOMRect): LevixelRect {
  return {
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
}

function clientRectInViewport(element: HTMLElement): LevixelRect {
  const bounds = element.getBoundingClientRect();
  const scaleX = element.offsetWidth > 0 ? bounds.width / element.offsetWidth : 1;
  const scaleY = element.offsetHeight > 0 ? bounds.height / element.offsetHeight : 1;
  return {
    left: bounds.left + element.clientLeft * scaleX,
    top: bounds.top + element.clientTop * scaleY,
    width: element.clientWidth * scaleX,
    height: element.clientHeight * scaleY,
  };
}

function intersectClippedAxes(
  source: LevixelRect,
  clip: LevixelRect,
  clipX: boolean,
  clipY: boolean,
): LevixelRect | null {
  const horizontal = clipX
    ? intersectRange(source.left, source.left + source.width, clip.left, clip.left + clip.width)
    : { start: source.left, end: source.left + source.width };
  const vertical = clipY
    ? intersectRange(source.top, source.top + source.height, clip.top, clip.top + clip.height)
    : { start: source.top, end: source.top + source.height };
  if (!horizontal || !vertical)
    return null;
  const result = {
    left: horizontal.start,
    top: vertical.start,
    width: horizontal.end - horizontal.start,
    height: vertical.end - vertical.start,
  };
  return isUsableRect(result) ? result : null;
}

function intersectRange(
  firstStart: number,
  firstEnd: number,
  secondStart: number,
  secondEnd: number,
): { start: number; end: number } | null {
  const start = Math.max(firstStart, secondStart);
  const end = Math.min(firstEnd, secondEnd);
  return end - start > 1 ? { start, end } : null;
}
