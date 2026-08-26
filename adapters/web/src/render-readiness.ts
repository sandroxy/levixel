function currentSource(image: HTMLImageElement): string {
  return image.currentSrc || image.src;
}

function isDecodedSource(image: HTMLImageElement, source: string): boolean {
  return currentSource(image) === source
    && image.complete
    && image.naturalWidth > 0
    && image.naturalHeight > 0;
}

function waitForImageLoad(image: HTMLImageElement, signal?: AbortSignal): Promise<boolean> {
  if (image.complete)
    return Promise.resolve(!signal?.aborted);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (ready: boolean): void => {
      if (settled)
        return;
      settled = true;
      image.removeEventListener('load', loaded);
      image.removeEventListener('error', failed);
      signal?.removeEventListener('abort', abort);
      resolve(ready);
    };
    const loaded = (): void => finish(true);
    const failed = (): void => finish(false);
    const abort = (): void => finish(false);
    image.addEventListener('load', loaded, { once: true });
    image.addEventListener('error', failed, { once: true });
    signal?.addEventListener('abort', abort, { once: true });
    if (signal?.aborted) {
      abort();
      return;
    }
    if (image.complete)
      finish(true);
  });
}

function waitForImageDecode(image: HTMLImageElement, signal?: AbortSignal): Promise<boolean> {
  if (signal?.aborted)
    return Promise.resolve(false);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (ready: boolean): void => {
      if (settled)
        return;
      settled = true;
      signal?.removeEventListener('abort', abort);
      resolve(ready);
    };
    const abort = (): void => finish(false);
    signal?.addEventListener('abort', abort, { once: true });
    void image.decode().then(
      () => finish(true),
      // A few engines reject decode() for an already usable SVG/resource.
      // complete + natural size remains the standards-compatible fallback.
      () => finish(true),
    );
  });
}

/**
 * Waits for the concrete DOM image and source revision used by a handoff.
 * Decoding a separate preload image is insufficient: the visible element may
 * still have a pending source selection or a newer src assignment.
 */
export async function waitForDecodedImage(
  image: HTMLImageElement,
  signal?: AbortSignal,
): Promise<boolean> {
  const source = currentSource(image);
  if (!source || signal?.aborted)
    return false;
  if (!await waitForImageLoad(image, signal)
    || signal?.aborted
    || !isDecodedSource(image, source)) {
    return false;
  }
  if (typeof image.decode === 'function') {
    if (!await waitForImageDecode(image, signal))
      return false;
  }
  return !signal?.aborted && isDecodedSource(image, source);
}

/**
 * Commits a decoded image during the next rendering update. The previous image
 * remains in the DOM until this callback, so there is no source-less frame;
 * decode()'s rendering-update guarantee covers the newly revealed element.
 */
export function commitOnNextRenderingUpdate(
  commit: () => void,
  signal?: AbortSignal,
): Promise<boolean> {
  if (signal?.aborted)
    return Promise.resolve(false);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (committed: boolean): void => {
      if (settled)
        return;
      settled = true;
      signal?.removeEventListener('abort', abort);
      resolve(committed);
    };
    const frame = requestAnimationFrame(() => {
      if (signal?.aborted) {
        finish(false);
        return;
      }
      commit();
      finish(true);
    });
    const abort = (): void => {
      cancelAnimationFrame(frame);
      finish(false);
    };
    signal?.addEventListener('abort', abort, { once: true });
  });
}
