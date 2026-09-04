import type { LevixelMediaItem, NativeLevixelMediaItem } from './types';

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

const NON_UNIFORM_SOURCE_RADIUS_KEYS = [
  'borderTopLeftRadius',
  'borderTopRightRadius',
  'borderBottomLeftRadius',
  'borderBottomRightRadius',
  'borderTopStartRadius',
  'borderTopEndRadius',
  'borderBottomStartRadius',
  'borderBottomEndRadius',
  'borderStartStartRadius',
  'borderStartEndRadius',
  'borderEndStartRadius',
  'borderEndEndRadius',
] as const;

export function normalizeMediaItems(
  items: readonly LevixelMediaItem[],
): NativeLevixelMediaItem[] {
  if (!Array.isArray(items)) {
    throw new TypeError('[Levixel] items must be an array.');
  }

  const ids = new Set<string>();
  return items.map((item, index) => {
    const path = `items[${index}]`;
    const record = requireRecord(item, path);
    rejectUnknownKeys(record, path);

    const id = requireNonEmptyString(record.id, `${path}.id`);
    if (ids.has(id)) {
      throw new TypeError(`[Levixel] ${path}.id must be unique.`);
    }
    ids.add(id);

    if (record.type !== 'image' && record.type !== 'video') {
      throw new TypeError(`[Levixel] ${path}.type must be "image" or "video".`);
    }

    const normalized: NativeLevixelMediaItem = {
      id,
      type: record.type,
      url: requireNonEmptyString(record.url, `${path}.url`),
    };

    const thumbnailUrl = optionalNonEmptyString(
      record.thumbnailUrl,
      `${path}.thumbnailUrl`,
    );
    if (thumbnailUrl !== undefined) {
      normalized.thumbnailUrl = thumbnailUrl;
    }
    if (record.type === 'video') {
      const posterUrl = optionalNonEmptyString(
        record.posterUrl,
        `${path}.posterUrl`,
      );
      if (posterUrl !== undefined) {
        normalized.posterUrl = posterUrl;
      }
    }
    if (record.alt !== undefined) {
      if (typeof record.alt !== 'string') {
        throw new TypeError(`[Levixel] ${path}.alt must be a string.`);
      }
      normalized.alt = record.alt;
    }
    const width = optionalPositiveNumber(record.width, `${path}.width`);
    if (width !== undefined) {
      normalized.width = width;
    }
    const height = optionalPositiveNumber(record.height, `${path}.height`);
    if (height !== undefined) {
      normalized.height = height;
    }
    return normalized;
  });
}

export function resolveSourceIndex(
  items: readonly NativeLevixelMediaItem[],
  selection: { readonly index?: unknown; readonly itemId?: unknown },
): number {
  const hasIndex = selection.index !== undefined;
  const hasItemId = selection.itemId !== undefined;
  if (hasIndex === hasItemId) {
    throw new TypeError(
      '[Levixel] Levixel.Source requires exactly one of index or itemId.',
    );
  }

  if (hasItemId) {
    if (typeof selection.itemId !== 'string' || selection.itemId.trim().length === 0) {
      throw new TypeError('[Levixel] Levixel.Source itemId must be a non-empty string.');
    }
    const resolvedIndex = items.findIndex(item => item.id === selection.itemId);
    if (resolvedIndex < 0) {
      throw new RangeError(
        '[Levixel] Levixel.Source itemId does not reference an item in the items array.',
      );
    }
    return resolvedIndex;
  }

  if (
    typeof selection.index !== 'number'
    || !Number.isInteger(selection.index)
    || selection.index < 0
    || selection.index >= items.length
  ) {
    throw new RangeError('[Levixel] Levixel.Source index is outside the items array.');
  }
  return selection.index;
}

export function resolveSourceCornerRadius(
  style: Readonly<Record<string, unknown>> | undefined,
): number {
  if (style === undefined) {
    return 0;
  }

  for (const key of NON_UNIFORM_SOURCE_RADIUS_KEYS) {
    if (style[key] !== undefined) {
      throw new TypeError(
        `[Levixel] Levixel.Source style.${key} is not supported; use one uniform numeric borderRadius.`,
      );
    }
  }

  const cornerRadius = style.borderRadius;
  if (cornerRadius === undefined) {
    return 0;
  }
  if (
    typeof cornerRadius !== 'number'
    || !Number.isFinite(cornerRadius)
    || cornerRadius < 0
  ) {
    throw new TypeError(
      '[Levixel] Levixel.Source style.borderRadius must be a non-negative finite number.',
    );
  }
  if (cornerRadius > 0 && style.overflow !== 'hidden') {
    throw new TypeError(
      '[Levixel] Levixel.Source with borderRadius must also set overflow to "hidden".',
    );
  }
  return cornerRadius;
}

function requireRecord(value: unknown, path: string): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new TypeError(`[Levixel] ${path} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function rejectUnknownKeys(value: Record<string, unknown>, path: string): void {
  for (const key of Object.keys(value)) {
    if (!ITEM_KEYS.has(key)) {
      throw new TypeError(
        `[Levixel] ${path}.${key} is not part of the Levixel contract.`,
      );
    }
  }
}

function requireNonEmptyString(value: unknown, path: string): string {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new TypeError(`[Levixel] ${path} must be a non-empty string.`);
  }
  return value;
}

function optionalNonEmptyString(
  value: unknown,
  path: string,
): string | undefined {
  if (value === undefined) {
    return undefined;
  }
  return requireNonEmptyString(value, path);
}

function optionalPositiveNumber(
  value: unknown,
  path: string,
): number | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw new TypeError(`[Levixel] ${path} must be a positive number.`);
  }
  return value;
}
