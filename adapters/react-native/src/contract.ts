import type { LevixelMediaItem, NativeLevixelMediaItem } from './types';

export function normalizeMediaItems(
  items: readonly LevixelMediaItem[],
): NativeLevixelMediaItem[] {
  if (!Array.isArray(items) || items.length === 0) {
    throw new TypeError('[Levixel] items must contain at least one media item.');
  }

  const ids = new Set<string>();
  return items.map((item, index) => {
    const path = `items[${index}]`;
    const id = requireNonEmptyString(item.id, `${path}.id`);
    if (ids.has(id)) {
      throw new TypeError(`[Levixel] ${path}.id must be unique.`);
    }
    ids.add(id);

    if (item.type !== 'image' && item.type !== 'video') {
      throw new TypeError(`[Levixel] ${path}.type must be "image" or "video".`);
    }

    const normalized: NativeLevixelMediaItem = {
      id,
      type: item.type,
      url: requireNonEmptyString(item.url, `${path}.url`),
    };

    const thumbnailUrl = optionalNonEmptyString(
      item.thumbnailUrl,
      `${path}.thumbnailUrl`,
    );
    if (thumbnailUrl !== undefined) {
      normalized.thumbnailUrl = thumbnailUrl;
    }
    if (item.type === 'video') {
      const posterUrl = optionalNonEmptyString(
        item.posterUrl,
        `${path}.posterUrl`,
      );
      if (posterUrl !== undefined) {
        normalized.posterUrl = posterUrl;
      }
    }
    const alt = optionalNonEmptyString(item.alt, `${path}.alt`);
    if (alt !== undefined) {
      normalized.alt = alt;
    }
    const width = optionalPositiveNumber(item.width, `${path}.width`);
    if (width !== undefined) {
      normalized.width = width;
    }
    const height = optionalPositiveNumber(item.height, `${path}.height`);
    if (height !== undefined) {
      normalized.height = height;
    }
    return normalized;
  });
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
