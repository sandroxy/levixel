import type {
  LevixelMediaItem,
  LevixelObjectFit,
  LevixelOpenOptions,
  LevixelRect,
  LevixelSelectorOpenOptions,
  LevixelSelectorSourceStyle,
  LevixelSize,
  LevixelSourceHint,
  NormalizedOpenOptions,
  NormalizedSelectorOpenOptions,
} from './types.js';

const OPEN_KEYS = new Set([
  'items',
  'index',
  'theme',
  'sourceHints',
  'sourceVisibility',
  'counter',
  'closeButton',
]);
const SELECTOR_KEYS = new Set([
  'items',
  'index',
  'theme',
  'sourceVisibility',
  'sourceSelector',
  'sourceStyles',
]);
const ITEM_KEYS = new Set([
  'id',
  'type',
  'url',
  'thumbnailUrl',
  'posterUrl',
  'width',
  'height',
  'alt',
]);
const HINT_KEYS = new Set([
  'rect',
  'imageSize',
  'objectFit',
  'coordinateSpace',
  'rectScale',
  'cornerRadius',
]);
const RECT_KEYS = new Set(['left', 'top', 'width', 'height']);
const SIZE_KEYS = new Set(['width', 'height']);
const SOURCE_STYLE_KEYS = new Set(['objectFit', 'cornerRadius']);

export class LevixelContractError extends Error {
  readonly code: string;
  readonly path: string;

  constructor(code: string, path: string, message: string) {
    super(message);
    this.name = 'LevixelContractError';
    this.code = code;
    this.path = path;
  }
}

function contractError(path: string, message: string, code = 'INVALID_REQUEST'): never {
  throw new LevixelContractError(code, path, message);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown, path: string): Record<string, unknown> {
  if (!isRecord(value))
    contractError(path, `${path} must be an object`);
  return value;
}

function rejectUnknownKeys(
  value: Record<string, unknown>,
  allowed: ReadonlySet<string>,
  path: string,
): void {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key))
      contractError(`${path}.${key}`, `${path}.${key} is not part of the Levixel SDK contract`);
  }
}

function requireNonEmptyString(value: unknown, path: string): string {
  if (typeof value !== 'string' || value.length === 0)
    contractError(path, `${path} must be a non-empty string`);
  return value;
}

function normalizeURL(value: unknown, path: string): string {
  const normalized = requireNonEmptyString(value, path).trim();
  if (!normalized)
    contractError(path, `${path} must be a non-empty string`);
  return normalized.startsWith('//') ? `https:${normalized}` : normalized;
}

function optionalPositiveNumber(value: unknown, path: string): number | undefined {
  if (value === undefined)
    return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0)
    contractError(path, `${path} must be a positive finite number`);
  return value;
}

function nonNegativeNumber(value: unknown, path: string, fallback: number): number {
  if (value === undefined)
    return fallback;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0)
    contractError(path, `${path} must be a non-negative finite number`);
  return value;
}

function objectFit(value: unknown, path: string, fallback?: LevixelObjectFit): LevixelObjectFit {
  if (value === undefined && fallback)
    return fallback;
  if (value !== 'contain' && value !== 'cover' && value !== 'fill')
    contractError(path, `${path} contains an unsupported value`, 'UNSUPPORTED_VALUE');
  return value;
}

function sanitizeItem(value: unknown, index: number): LevixelMediaItem {
  const path = `$.items[${index}]`;
  const record = requireRecord(value, path);
  rejectUnknownKeys(record, ITEM_KEYS, path);
  const type = requireNonEmptyString(record.type, `${path}.type`);
  if (type !== 'image' && type !== 'video')
    contractError(`${path}.type`, `${path}.type contains an unsupported value`, 'UNSUPPORTED_VALUE');

  const item: LevixelMediaItem = {
    id: requireNonEmptyString(record.id, `${path}.id`),
    type,
    url: normalizeURL(record.url, `${path}.url`),
  };
  if (record.thumbnailUrl !== undefined)
    item.thumbnailUrl = normalizeURL(record.thumbnailUrl, `${path}.thumbnailUrl`);
  if (record.posterUrl !== undefined)
    item.posterUrl = normalizeURL(record.posterUrl, `${path}.posterUrl`);
  const width = optionalPositiveNumber(record.width, `${path}.width`);
  const height = optionalPositiveNumber(record.height, `${path}.height`);
  if (width !== undefined)
    item.width = width;
  if (height !== undefined)
    item.height = height;
  if (record.alt !== undefined) {
    if (typeof record.alt !== 'string')
      contractError(`${path}.alt`, `${path}.alt must be a string`);
    item.alt = record.alt;
  }
  return item;
}

function sanitizeItems(value: unknown): LevixelMediaItem[] {
  if (!Array.isArray(value) || value.length === 0)
    contractError('$.items', '$.items must contain at least one item');
  const items = value.map(sanitizeItem);
  const ids = new Set<string>();
  items.forEach((item, index) => {
    if (ids.has(item.id)) {
      contractError(
        `$.items[${index}].id`,
        `$.items[${index}].id must be unique within $.items`,
        'INVALID_VALUE',
      );
    }
    ids.add(item.id);
  });
  return items;
}

function normalizeIndex(value: unknown, itemCount: number): number {
  const index = value === undefined ? 0 : value;
  if (!Number.isInteger(index) || typeof index !== 'number' || index < 0 || index >= itemCount)
    contractError('$.index', '$.index must reference an item in $.items');
  return index;
}

function normalizeTheme(value: unknown): 'dark' | 'light' {
  if (value === undefined)
    return 'dark';
  if (value !== 'dark' && value !== 'light')
    contractError('$.theme', '$.theme contains an unsupported value', 'UNSUPPORTED_VALUE');
  return value;
}

function normalizeSourceVisibility(value: unknown): 'hidden' | 'visible' {
  if (value === undefined)
    return 'hidden';
  if (value !== 'hidden' && value !== 'visible')
    contractError(
      '$.sourceVisibility',
      '$.sourceVisibility contains an unsupported value',
      'UNSUPPORTED_VALUE',
    );
  return value;
}

function finiteNumber(value: unknown, path: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value))
    contractError(path, `${path} must be a finite number`);
  return value;
}

function normalizeRect(value: unknown, path: string): LevixelRect {
  const record = requireRecord(value, path);
  rejectUnknownKeys(record, RECT_KEYS, path);
  const rect = {
    left: finiteNumber(record.left, `${path}.left`),
    top: finiteNumber(record.top, `${path}.top`),
    width: finiteNumber(record.width, `${path}.width`),
    height: finiteNumber(record.height, `${path}.height`),
  };
  if (rect.width <= 0 || rect.height <= 0)
    contractError(path, `${path} must have positive width and height`);
  return rect;
}

function normalizeSize(value: unknown, path: string): LevixelSize {
  const record = requireRecord(value, path);
  rejectUnknownKeys(record, SIZE_KEYS, path);
  const width = optionalPositiveNumber(record.width, `${path}.width`);
  const height = optionalPositiveNumber(record.height, `${path}.height`);
  if (width === undefined || height === undefined)
    contractError(path, `${path} must have positive width and height`);
  return { width, height };
}

function normalizeHint(value: unknown, index: number): LevixelSourceHint | null {
  if (value === null)
    return null;
  const path = `$.sourceHints[${index}]`;
  const record = requireRecord(value, path);
  rejectUnknownKeys(record, HINT_KEYS, path);
  const coordinateSpace = record.coordinateSpace;
  if (coordinateSpace !== 'screen' && coordinateSpace !== 'viewport') {
    contractError(
      `${path}.coordinateSpace`,
      `${path}.coordinateSpace contains an unsupported value`,
      'UNSUPPORTED_VALUE',
    );
  }
  const hint: LevixelSourceHint = {
    rect: normalizeRect(record.rect, `${path}.rect`),
    objectFit: objectFit(record.objectFit, `${path}.objectFit`),
    coordinateSpace,
  };
  if (record.imageSize !== undefined)
    hint.imageSize = normalizeSize(record.imageSize, `${path}.imageSize`);
  const rectScale = optionalPositiveNumber(record.rectScale, `${path}.rectScale`);
  if (rectScale !== undefined)
    hint.rectScale = rectScale;
  if (record.cornerRadius !== undefined)
    hint.cornerRadius = nonNegativeNumber(record.cornerRadius, `${path}.cornerRadius`, 0);
  return hint;
}

function normalizeHints(value: unknown, itemCount: number): Array<LevixelSourceHint | null> {
  if (value === undefined)
    return Array.from({ length: itemCount }, () => null);
  if (!Array.isArray(value) || value.length !== itemCount) {
    contractError(
      '$.sourceHints',
      '$.sourceHints must contain one entry for each media item',
    );
  }
  return value.map(normalizeHint);
}

function rejectUnsupportedBoolean(value: unknown, path: '$.counter' | '$.closeButton'): void {
  if (value === undefined || value === false)
    return;
  if (typeof value !== 'boolean')
    contractError(path, `${path} must be a boolean`);
  const message = path === '$.counter'
    ? 'Levixel does not render a counter overlay'
    : 'Levixel closes by gesture, tap, Escape, or the video controls';
  contractError(path, message, 'UNSUPPORTED_VALUE');
}

export function normalizeOpenOptions(value: LevixelOpenOptions | unknown): NormalizedOpenOptions {
  const record = requireRecord(value, '$');
  rejectUnknownKeys(record, OPEN_KEYS, '$');
  const items = sanitizeItems(record.items);
  rejectUnsupportedBoolean(record.counter, '$.counter');
  rejectUnsupportedBoolean(record.closeButton, '$.closeButton');
  return {
    items,
    index: normalizeIndex(record.index, items.length),
    theme: normalizeTheme(record.theme),
    sourceHints: normalizeHints(record.sourceHints, items.length),
    sourceVisibility: normalizeSourceVisibility(record.sourceVisibility),
  };
}

function normalizeSourceStyles(value: unknown, itemCount: number): LevixelSelectorSourceStyle[] {
  if (value === undefined) {
    return Array.from({ length: itemCount }, () => ({
      objectFit: 'cover' as const,
      cornerRadius: 0,
    }));
  }
  if (!Array.isArray(value) || value.length !== itemCount) {
    contractError(
      '$.sourceStyles',
      '$.sourceStyles must contain one entry for each media item',
    );
  }
  return value.map((entry, index) => {
    const path = `$.sourceStyles[${index}]`;
    const record = requireRecord(entry, path);
    rejectUnknownKeys(record, SOURCE_STYLE_KEYS, path);
    return {
      objectFit: objectFit(record.objectFit, `${path}.objectFit`, 'cover'),
      cornerRadius: nonNegativeNumber(record.cornerRadius, `${path}.cornerRadius`, 0),
    };
  });
}

export function normalizeSelectorOpenOptions(
  value: LevixelSelectorOpenOptions | unknown,
): NormalizedSelectorOpenOptions {
  const record = requireRecord(value, '$');
  rejectUnknownKeys(record, SELECTOR_KEYS, '$');
  const items = sanitizeItems(record.items);
  if (record.sourceSelector !== undefined && typeof record.sourceSelector !== 'string')
    contractError('$.sourceSelector', '$.sourceSelector must be a string');
  const normalized: NormalizedSelectorOpenOptions = {
    items,
    index: normalizeIndex(record.index, items.length),
    theme: normalizeTheme(record.theme),
    sourceVisibility: normalizeSourceVisibility(record.sourceVisibility),
    sourceStyles: normalizeSourceStyles(record.sourceStyles, items.length),
  };
  if (typeof record.sourceSelector === 'string')
    normalized.sourceSelector = record.sourceSelector;
  return normalized;
}

export function normalizePrepareOptions(value: unknown): { priority: boolean } {
  if (value === undefined)
    return { priority: false };
  const record = requireRecord(value, '$.options');
  rejectUnknownKeys(record, new Set(['priority']), '$.options');
  if (record.priority !== undefined && typeof record.priority !== 'boolean')
    contractError('$.options.priority', '$.options.priority must be a boolean');
  return { priority: record.priority === true };
}

export function sanitizeSingleItem(value: LevixelMediaItem | unknown): LevixelMediaItem {
  return sanitizeItem(value, 0);
}
