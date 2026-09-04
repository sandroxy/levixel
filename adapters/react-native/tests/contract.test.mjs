import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

const contractModule = process.env.LEVIXEL_RN_CONTRACT_PATH
  ? pathToFileURL(path.resolve(process.env.LEVIXEL_RN_CONTRACT_PATH)).href
  : new URL('../src/contract.ts', import.meta.url).href;
const {
  normalizeMediaItems,
  resolveSourceCornerRadius,
  resolveSourceIndex,
} = await import(contractModule);

const image = {
  id: 'image-1',
  type: 'image',
  url: 'https://example.com/image.jpg',
};

test('provider normalization accepts an empty asynchronous state', () => {
  assert.deepEqual(normalizeMediaItems([]), []);
});

test('media normalization preserves an intentionally empty alt label', () => {
  assert.deepEqual(normalizeMediaItems([{ ...image, alt: '' }]), [
    { ...image, alt: '' },
  ]);
});

test('media normalization rejects duplicate ids', () => {
  assert.throws(
    () => normalizeMediaItems([image, { ...image, url: 'https://example.com/other.jpg' }]),
    /items\[1\]\.id must be unique/,
  );
});

test('media normalization rejects malformed items and unknown fields', () => {
  assert.throws(
    () => normalizeMediaItems([null]),
    /items\[0\] must be an object/,
  );
  assert.throws(
    () => normalizeMediaItems([{ ...image, cachePolicy: 'disk' }]),
    /items\[0\]\.cachePolicy is not part of the Levixel contract/,
  );
});

test('source identity follows a stable item id after prepend, append, and reorder', () => {
  const items = normalizeMediaItems([
    { id: 'newer', type: 'image', url: 'https://example.com/newer.jpg' },
    { id: 'image-2', type: 'image', url: 'https://example.com/image-2.jpg' },
    image,
    { id: 'older', type: 'image', url: 'https://example.com/older.jpg' },
  ]);

  assert.equal(resolveSourceIndex(items, { itemId: image.id }), 2);
  assert.equal(resolveSourceIndex(items, { index: 1 }), 1);
});

test('source identity rejects ambiguous, missing, and unknown selections', () => {
  const items = normalizeMediaItems([image]);

  assert.throws(
    () => resolveSourceIndex(items, {}),
    /exactly one of index or itemId/,
  );
  assert.throws(
    () => resolveSourceIndex(items, { index: 0, itemId: image.id }),
    /exactly one of index or itemId/,
  );
  assert.throws(
    () => resolveSourceIndex(items, { itemId: 'missing' }),
    /itemId does not reference an item/,
  );
  assert.throws(
    () => resolveSourceIndex(items, { itemId: '   ' }),
    /itemId must be a non-empty string/,
  );
});

test('source corner radius uses one clipped uniform source boundary', () => {
  assert.equal(resolveSourceCornerRadius(undefined), 0);
  assert.equal(
    resolveSourceCornerRadius({ borderRadius: 8, overflow: 'hidden' }),
    8,
  );
  assert.equal(resolveSourceCornerRadius({ borderRadius: 0 }), 0);
});

test('source corner radius rejects values the native transition cannot represent', () => {
  assert.throws(
    () => resolveSourceCornerRadius({ borderRadius: '50%', overflow: 'hidden' }),
    /borderRadius must be a non-negative finite number/,
  );
  assert.throws(
    () => resolveSourceCornerRadius({ borderRadius: -1, overflow: 'hidden' }),
    /borderRadius must be a non-negative finite number/,
  );
  assert.throws(
    () => resolveSourceCornerRadius({ borderRadius: 8 }),
    /must also set overflow to "hidden"/,
  );
  assert.throws(
    () => resolveSourceCornerRadius({
      borderRadius: 8,
      borderTopLeftRadius: 4,
      overflow: 'hidden',
    }),
    /borderTopLeftRadius is not supported/,
  );
});
