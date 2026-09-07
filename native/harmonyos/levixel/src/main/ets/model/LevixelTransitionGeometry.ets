import { cloneRect, LevixelSourceImageFit } from './LevixelModels';
import type { RectMetrics } from './LevixelModels';

export interface LevixelTransitionGeometry {
  visibleFrame: RectMetrics;
  contentFrame: RectMetrics;
}

export function isUsableRect(rect: RectMetrics): boolean {
  return Number.isFinite(rect.left) && Number.isFinite(rect.top) &&
    Number.isFinite(rect.width) && Number.isFinite(rect.height) &&
    rect.width > 0 && rect.height > 0 &&
    Number.isFinite(rect.left + rect.width) && Number.isFinite(rect.top + rect.height);
}

export function intersectRects(first: RectMetrics, second: RectMetrics): RectMetrics | null {
  if (!isUsableRect(first) || !isUsableRect(second)) {
    return null;
  }
  const left: number = Math.max(first.left, second.left);
  const top: number = Math.max(first.top, second.top);
  const right: number = Math.min(first.left + first.width, second.left + second.width);
  const bottom: number = Math.min(first.top + first.height, second.top + second.height);
  if (right <= left || bottom <= top) {
    return null;
  }
  return { left: left, top: top, width: right - left, height: bottom - top };
}

export function imageContentFrame(
  imageWidth: number,
  imageHeight: number,
  containerFrame: RectMetrics,
  fit: LevixelSourceImageFit
): RectMetrics {
  if (!Number.isFinite(imageWidth) || !Number.isFinite(imageHeight) ||
    imageWidth <= 0 || imageHeight <= 0 || !isUsableRect(containerFrame)) {
    throw new Error('Levixel image geometry requires finite positive dimensions and a usable container.');
  }
  if (fit === LevixelSourceImageFit.FILL) {
    return cloneRect(containerFrame);
  }
  if (fit !== LevixelSourceImageFit.COVER && fit !== LevixelSourceImageFit.CONTAIN) {
    throw new Error('Levixel source imageFit must be COVER, CONTAIN, or FILL.');
  }

  const widthScale: number = containerFrame.width / imageWidth;
  const heightScale: number = containerFrame.height / imageHeight;
  const scale: number = fit === LevixelSourceImageFit.COVER ?
    Math.max(widthScale, heightScale) : Math.min(widthScale, heightScale);
  const width: number = imageWidth * scale;
  const height: number = imageHeight * scale;
  const contentFrame: RectMetrics = {
    left: containerFrame.left + (containerFrame.width - width) * 0.5,
    top: containerFrame.top + (containerFrame.height - height) * 0.5,
    width: width,
    height: height
  };
  if (!isUsableRect(contentFrame)) {
    throw new Error('Levixel image dimensions cannot produce a finite positive content frame.');
  }
  return contentFrame;
}

export function resolveImageGeometry(
  imageWidth: number,
  imageHeight: number,
  containerFrame: RectMetrics,
  fit: LevixelSourceImageFit,
  clippingFrame: RectMetrics = containerFrame
): LevixelTransitionGeometry | null {
  const contentFrame: RectMetrics = imageContentFrame(imageWidth, imageHeight, containerFrame, fit);
  const visibleFrame: RectMetrics | null = intersectRects(clippingFrame, contentFrame);
  if (visibleFrame === null) {
    return null;
  }
  return {
    visibleFrame: visibleFrame,
    contentFrame: {
      left: contentFrame.left - visibleFrame.left,
      top: contentFrame.top - visibleFrame.top,
      width: contentFrame.width,
      height: contentFrame.height
    }
  };
}

export function mapSourceSnapshotToTarget(
  imageWidth: number,
  imageHeight: number,
  sourceFrame: RectMetrics,
  targetFrame: RectMetrics,
  fit: LevixelSourceImageFit
): RectMetrics {
  if (!isUsableRect(targetFrame)) {
    throw new Error('Levixel snapshot geometry requires a usable target.');
  }
  // A source snapshot already contains the host's crop or letterboxing. Carry
  // those pixels through the original media frame instead of fitting them again.
  const mediaInSource: RectMetrics = imageContentFrame(imageWidth, imageHeight, sourceFrame, fit);
  const scaleX: number = targetFrame.width / mediaInSource.width;
  const scaleY: number = targetFrame.height / mediaInSource.height;
  const snapshotFrame: RectMetrics = {
    left: targetFrame.left + (sourceFrame.left - mediaInSource.left) * scaleX,
    top: targetFrame.top + (sourceFrame.top - mediaInSource.top) * scaleY,
    width: sourceFrame.width * scaleX,
    height: sourceFrame.height * scaleY
  };
  if (!isUsableRect(snapshotFrame)) {
    throw new Error('Levixel source snapshot cannot produce a finite positive target frame.');
  }
  return snapshotFrame;
}
