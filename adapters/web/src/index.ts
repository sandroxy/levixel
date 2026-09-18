import {
  LevixelContractError,
  normalizeOpenOptions,
  normalizePrepareOptions,
  normalizeSelectorOpenOptions,
  sanitizeSingleItem,
} from './contract.js';
import {
  imageInfoFromElement,
  loadImage,
  loadImageWithTimeout,
  peekImage,
  rememberImage,
  transitionURL,
} from './media-cache.js';
import { onLevixelSourceActivate } from './source-activation.js';
import { LevixelWebViewer } from './viewer.js';
import type {
  ImageInfo,
  LevixelCloseResult,
  LevixelEvent,
  LevixelMediaItem,
  LevixelOpenOptions,
  LevixelOpenResult,
  LevixelPrepareOptions,
  LevixelPreparedPreview,
  LevixelSelectorOpenOptions,
  LevixelSelectorSourceStyle,
  LevixelSourceUpdateOptions,
  NormalizedOpenOptions,
  NormalizedSelectorOpenOptions,
  SourceBinding,
} from './types.js';

export type {
  LevixelAction,
  LevixelActionLayout,
  LevixelActionContext,
  LevixelMediaContext,
  LevixelRetryResult,
  LevixelCloseResult,
  LevixelEvent,
  LevixelMediaItem,
  LevixelMediaType,
  LevixelObjectFit,
  LevixelOpenOptions,
  LevixelOpenResult,
  LevixelPrepareOptions,
  LevixelPreparedPreview,
  LevixelRect,
  LevixelSelectorOpenOptions,
  LevixelSelectorSourceBinding,
  LevixelSelectorSourceStyle,
  LevixelSize,
  LevixelSourceHint,
  LevixelSourceVisibility,
  LevixelSourceUpdateOptions,
  LevixelTheme,
} from './types.js';
export { LevixelContractError } from './contract.js';
export {
  onLevixelSourceActivate,
  type LevixelSourceActivationListener,
} from './source-activation.js';

const eventListeners = new Set<(event: LevixelEvent) => void>();
let eventChannelStarted = false;
let activeViewer: LevixelWebViewer | undefined;
let sessionGeneration = 0;

export async function openLevixel(options: LevixelOpenOptions): Promise<LevixelOpenResult> {
  requireBrowser();
  const normalized = normalizeOpenOptions(options);
  const bindings = normalized.sourceHints.map((hint, index): SourceBinding => {
    const sourceId = normalized.sourceIds?.[index];
    return { element: null, hint, ...(sourceId != null ? { sourceId } : {}) };
  });
  return await openNormalized(normalized, bindings);
}

export async function closeLevixel(): Promise<LevixelCloseResult> {
  requireBrowser();
  sessionGeneration += 1;
  const viewer = activeViewer;
  if (!viewer)
    return { closed: true };
  await viewer.close(true, true);
  if (activeViewer === viewer)
    activeViewer = undefined;
  return { closed: true };
}

export async function retryLevixel(): Promise<{ retried: boolean }> {
  requireBrowser();
  return { retried: activeViewer?.retry() ?? false };
}

export function onLevixelEvent(listener: (event: LevixelEvent) => void): () => void {
  if (typeof listener !== 'function')
    throw new Error('Levixel event listener must be a function');
  eventListeners.add(listener);
  if (!eventChannelStarted) {
    eventChannelStarted = true;
    emit({
      type: 'ready',
      payload: { message: 'levixel event channel ready' },
      time: Date.now(),
    });
  }
  return () => eventListeners.delete(listener);
}

export async function prepareLevixelItem(
  item: LevixelMediaItem,
  options?: LevixelPrepareOptions,
): Promise<LevixelPreparedPreview | undefined> {
  requireBrowser();
  const normalizedItem = sanitizeSingleItem(item);
  const normalizedOptions = normalizePrepareOptions(options);
  const url = transitionURL(normalizedItem);
  if (!url)
    return undefined;
  try {
    return await loadImage(url, normalizedOptions.priority);
  }
  catch (_) {
    return undefined;
  }
}

export async function warmupLevixelItem(item: LevixelMediaItem, loadEvent?: unknown): Promise<void> {
  requireBrowser();
  const normalizedItem = sanitizeSingleItem(item);
  const url = transitionURL(normalizedItem);
  if (!url)
    return;
  const target = isRecord(loadEvent) ? loadEvent.target : undefined;
  const fromElement = target instanceof Element ? imageInfoFromElement(target) : undefined;
  if (fromElement) {
    rememberImage(url, fromElement);
    return;
  }
  try {
    await loadImage(url);
  }
  catch (_) {}
}

export async function openLevixelFromSelector(
  options: LevixelSelectorOpenOptions,
): Promise<LevixelOpenResult> {
  requireBrowser();
  const normalized = normalizeSelectorOpenOptions(options);
  const bindings = bindingsFromSelector(normalized);
  const openOptions: NormalizedOpenOptions = {
    items: normalized.items,
    actions: normalized.actions,
    actionLayout: normalized.actionLayout,
    actionListIcons: normalized.actionListIcons,
    index: normalized.index,
    theme: normalized.theme,
    sourceVisibility: normalized.sourceVisibility,
    sourceHints: bindings.map(binding => binding.hint),
  };
  return await openNormalized(openOptions, bindings);
}

/** Replace mounted bindings after host rendering; media and the viewer session stay unchanged. */
export async function updateLevixelSources(options: LevixelSourceUpdateOptions): Promise<{ updated: boolean }> {
  requireBrowser();
  if (!options || typeof options !== 'object' || Array.isArray(options)
    || Object.keys(options).some(key => key !== 'galleryId' && key !== 'sourceBindings')
    || typeof options.galleryId !== 'string' || !options.galleryId.trim()
    || !Array.isArray(options.sourceBindings)) {
    throw new LevixelContractError('INVALID_REQUEST', '$', 'Expected galleryId and sourceBindings');
  }
  const viewer = activeViewer;
  if (!viewer || viewer.galleryId !== options.galleryId || viewer.isClosing()) return { updated: false };
  const normalized = normalizeSelectorOpenOptions({ items: viewer.mediaItems, sourceBindings: options.sourceBindings });
  viewer.updateSources(bindingsFromSelector(normalized));
  return { updated: true };
}

async function openNormalized(
  options: NormalizedOpenOptions,
  bindings: SourceBinding[],
): Promise<LevixelOpenResult> {
  const generation = ++sessionGeneration;
  const previous = activeViewer;
  if (previous) {
    previous.replace();
    if (activeViewer === previous)
      activeViewer = undefined;
  }
  const previews = await resolveInitialPreviews(options, bindings);
  if (generation !== sessionGeneration)
    throw cancelledError();
  const viewer = new LevixelWebViewer(options, bindings, previews, {
    emit,
    requestClose: () => {
      if (activeViewer !== viewer)
        return;
      void closeLevixel();
    },
  });
  activeViewer = viewer;
  try {
    const result = await viewer.open();
    if (generation !== sessionGeneration || activeViewer !== viewer)
      throw cancelledError();
    return result;
  }
  catch (error) {
    if (activeViewer === viewer && !viewer.isClosing()) {
      viewer.replace();
      activeViewer = undefined;
    }
    throw error;
  }
}

async function resolveInitialPreviews(
  options: NormalizedOpenOptions,
  bindings: SourceBinding[],
): Promise<Array<ImageInfo | undefined>> {
  const previews = options.items.map((item, index) => {
    const bindingPreview = bindings[index]?.preview;
    return bindingPreview ?? peekImage(transitionURL(item));
  });
  if (previews[options.index])
    return previews;
  const selectedURL = transitionURL(options.items[options.index]!);
  if (!selectedURL)
    return previews;
  previews[options.index] = await loadImageWithTimeout(selectedURL, 120, true);
  return previews;
}

function bindingsFromSelector(options: NormalizedSelectorOpenOptions): SourceBinding[] {
  if (options.sourceMode === 'identified') {
    const bindings = options.items.map((): SourceBinding => ({ element: null, hint: null, candidates: [] }));
    const boundElements = new Set<HTMLElement>();
    options.sourceBindings.forEach((sourceBinding, bindingIndex) => {
      const path = `$.sourceBindings[${bindingIndex}].selector`;
      const element = uniqueSelectorElement(sourceBinding.selector, path);
      if (element && boundElements.has(element)) {
        throw new LevixelContractError(
          'INVALID_VALUE',
          path,
          `${path} must resolve to a different element from every other binding`,
        );
      }
      if (element)
        boundElements.add(element);
      const candidate = bindingFromElement(
        options.items[sourceBinding.itemIndex]!,
        element,
        sourceBinding,
        sourceBinding.selector,
      );
      if (sourceBinding.sourceId !== undefined)
        candidate.sourceId = sourceBinding.sourceId;
      bindings[sourceBinding.itemIndex]!.candidates!.push(candidate);
    });
    bindings.forEach((binding, index) => {
      if (index === options.index && options.initialSourceId !== undefined)
        binding.preferredSourceId = options.initialSourceId;
      const initial = binding.preferredSourceId === undefined ? binding.candidates![0]
        : binding.candidates!.find(candidate => candidate.sourceId === binding.preferredSourceId);
      if (initial?.preview)
        binding.preview = initial.preview;
    });
    return bindings;
  }
  if (!options.sourceSelector)
    return options.items.map(() => ({ element: null, hint: null }));
  let matches: Element[];
  try {
    matches = [...document.querySelectorAll(options.sourceSelector)];
  }
  catch (_) {
    throw new LevixelContractError(
      'INVALID_REQUEST',
      '$.sourceSelector',
      '$.sourceSelector must be a valid CSS selector',
    );
  }
  if (matches.length !== options.items.length)
    return options.items.map(() => ({ element: null, hint: null }));

  return options.items.map((item, index) => bindingFromElement(
    item,
    matches[index] instanceof HTMLElement ? matches[index] : null,
    options.sourceStyles[index]!,
  ));
}

function uniqueSelectorElement(selector: string, path: string): HTMLElement | null {
  let matches: Element[];
  try {
    matches = [...document.querySelectorAll(selector)];
  }
  catch (_) {
    throw new LevixelContractError(
      'INVALID_REQUEST',
      path,
      `${path} must be a valid CSS selector`,
    );
  }
  if (matches.length > 1) {
    throw new LevixelContractError(
      'INVALID_VALUE',
      path,
      `${path} must match at most one element`,
    );
  }
  return matches[0] instanceof HTMLElement ? matches[0] : null;
}

function bindingFromElement(
  item: LevixelMediaItem,
  element: HTMLElement | null,
  style: LevixelSelectorSourceStyle,
  identitySelector?: string,
): SourceBinding {
  if (!element)
    return { element: null, hint: null, ...(identitySelector ? { identitySelector } : {}) };
  const rect = element.getBoundingClientRect();
  const normalizedRect = {
    left: rect.left,
    top: rect.top,
    width: rect.width,
    height: rect.height,
  };
  const preview = imageInfoFromElement(element);
  const transition = transitionURL(item);
  if (preview && transition)
    rememberImage(transition, preview);
  const imageSize = preview
    ? { width: preview.width, height: preview.height }
    : (item.width && item.height ? { width: item.width, height: item.height } : undefined);
  const binding: SourceBinding = {
    element,
    hint: {
      rect: normalizedRect,
      objectFit: style.objectFit ?? 'cover',
      coordinateSpace: 'viewport' as const,
      rectScale: 1,
      cornerRadius: style.cornerRadius ?? 0,
      ...(imageSize ? { imageSize } : {}),
    },
    ...(identitySelector ? { identitySelector } : {}),
  };
  if (preview)
    binding.preview = preview;
  return binding;
}

function emit(event: LevixelEvent): void {
  eventListeners.forEach((listener) => {
    try {
      listener(event);
    }
    catch (_) {}
  });
}

function requireBrowser(): void {
  if (typeof window === 'undefined' || typeof document === 'undefined' || !document.body)
    throw new Error('Levixel Web requires a browser document');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function cancelledError(): Error {
  const error = new Error('Viewer opening was cancelled');
  error.name = 'LevixelCancelledError';
  return error;
}

const levixel = {
  open: openLevixel,
  close: closeLevixel,
  retry: retryLevixel,
  updateSources: updateLevixelSources,
  onEvent: onLevixelEvent,
  prepareItem: prepareLevixelItem,
  warmupItem: warmupLevixelItem,
  openFromSelector: openLevixelFromSelector,
  onSourceActivate: onLevixelSourceActivate,
};

export default levixel;
