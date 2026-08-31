import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

const contractModule = process.env.LEVIXEL_RN_CONTRACT_PATH
  ? pathToFileURL(path.resolve(process.env.LEVIXEL_RN_CONTRACT_PATH)).href
  : new URL('../src/contract.ts', import.meta.url).href;
const { normalizeMediaItems } = await import(contractModule);

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
