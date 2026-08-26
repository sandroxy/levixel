import type { ImageInfo, LevixelMediaItem } from './types.js';

const MAX_CACHE_SIZE = 80;
const imageCache = new Map<string, ImageInfo>();
const imageJobs = new Map<string, Promise<ImageInfo>>();

export function transitionURL(item: LevixelMediaItem): string {
  if (item.type === 'video')
    return item.posterUrl ?? item.thumbnailUrl ?? '';
  return item.thumbnailUrl ?? item.url;
}

export function peekImage(url: string): ImageInfo | undefined {
  const cached = imageCache.get(url);
  if (!cached)
    return undefined;
  imageCache.delete(url);
  imageCache.set(url, cached);
  return cached;
}

export function rememberImage(url: string, info: ImageInfo): void {
  if (!url || info.width <= 0 || info.height <= 0)
    return;
  imageCache.delete(url);
  imageCache.set(url, info);
  while (imageCache.size > MAX_CACHE_SIZE) {
    const oldest = imageCache.keys().next().value as string | undefined;
    if (!oldest)
      break;
    imageCache.delete(oldest);
  }
}

export function imageInfoFromElement(element: Element | null): ImageInfo | undefined {
  const image = element instanceof HTMLImageElement
    ? element
    : element?.querySelector('img');
  if (!(image instanceof HTMLImageElement) || !image.complete)
    return undefined;
  if (image.naturalWidth <= 0 || image.naturalHeight <= 0)
    return undefined;
  const src = image.currentSrc || image.src;
  return src ? { src, width: image.naturalWidth, height: image.naturalHeight } : undefined;
}

export function loadImage(url: string, priority = false): Promise<ImageInfo> {
  const cached = peekImage(url);
  if (cached)
    return Promise.resolve(cached);
  const existing = imageJobs.get(url);
  if (existing)
    return existing;

  const job = new Promise<ImageInfo>((resolve, reject) => {
    const image = new Image();
    image.decoding = 'async';
    if ('fetchPriority' in image)
      image.fetchPriority = priority ? 'high' : 'auto';
    image.onload = () => {
      const finish = (): void => {
        if (image.naturalWidth <= 0 || image.naturalHeight <= 0) {
          reject(new Error(`Levixel could not decode image: ${url}`));
          return;
        }
        const info = {
          src: image.currentSrc || image.src || url,
          width: image.naturalWidth,
          height: image.naturalHeight,
        };
        rememberImage(url, info);
        resolve(info);
      };
      if (typeof image.decode === 'function')
        void image.decode().then(finish, finish);
      else
        finish();
    };
    image.onerror = () => reject(new Error(`Levixel could not load image: ${url}`));
    image.src = url;
  }).finally(() => imageJobs.delete(url));
  imageJobs.set(url, job);
  return job;
}

export async function loadImageWithTimeout(
  url: string,
  timeoutMs: number,
  priority = false,
): Promise<ImageInfo | undefined> {
  const cached = peekImage(url);
  if (cached)
    return cached;
  return await new Promise((resolve) => {
    let settled = false;
    const timeout = window.setTimeout(() => {
      if (settled)
        return;
      settled = true;
      resolve(undefined);
    }, timeoutMs);
    void loadImage(url, priority).then((info) => {
      if (settled)
        return;
      settled = true;
      window.clearTimeout(timeout);
      resolve(info);
    }, () => {
      if (settled)
        return;
      settled = true;
      window.clearTimeout(timeout);
      resolve(undefined);
    });
  });
}

export function clearImageCacheForTests(): void {
  imageCache.clear();
  imageJobs.clear();
}
