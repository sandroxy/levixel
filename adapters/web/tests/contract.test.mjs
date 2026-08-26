import assert from 'node:assert/strict';
import test from 'node:test';

import { normalizeOpenOptions, normalizeSelectorOpenOptions } from '../dist/contract.js';

const item = {
  id: 'wide-coast',
  type: 'image',
  url: 'https://example.com/full.jpg',
  thumbnailUrl: 'https://example.com/thumb.jpg',
  width: 2400,
  height: 1600,
};

test('Web defaults preserve the canonical contract and use native source hiding', () => {
  const request = normalizeOpenOptions({ items: [item] });
  assert.equal(request.index, 0);
  assert.equal(request.theme, 'dark');
  assert.equal(request.sourceVisibility, 'hidden');
  assert.deepEqual(request.sourceHints, [null]);
  assert.deepEqual(request.items, [item]);
});

test('counter and global close button remain explicitly unsupported', () => {
  assert.throws(
    () => normalizeOpenOptions({ items: [item], counter: true }),
    error => error.code === 'UNSUPPORTED_VALUE' && error.path === '$.counter',
  );
  assert.throws(
    () => normalizeOpenOptions({ items: [item], closeButton: true }),
    error => error.code === 'UNSUPPORTED_VALUE' && error.path === '$.closeButton',
  );
});

test('unknown fields and drifting source arrays fail instead of being ignored', () => {
  assert.throws(
    () => normalizeOpenOptions({ items: [item], inventedOverlay: true }),
    error => error.path === '$.inventedOverlay',
  );
  assert.throws(
    () => normalizeOpenOptions({ items: [item], sourceHints: [] }),
    error => error.path === '$.sourceHints',
  );
  assert.throws(
    () => normalizeSelectorOpenOptions({ items: [item], sourceStyles: [] }),
    error => error.path === '$.sourceStyles',
  );
});

test('selector defaults use the same field values without UniApp-only visibility behavior', () => {
  const request = normalizeSelectorOpenOptions({ items: [item], sourceSelector: '.source' });
  assert.equal(request.sourceVisibility, 'hidden');
  assert.deepEqual(request.sourceStyles, [{ objectFit: 'cover', cornerRadius: 0 }]);
});
