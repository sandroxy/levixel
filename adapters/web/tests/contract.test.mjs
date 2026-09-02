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

test('media ids must be unique within a request', () => {
  assert.throws(
    () => normalizeOpenOptions({ items: [item, { ...item, url: 'https://example.com/other.jpg' }] }),
    error => error.code === 'INVALID_VALUE' && error.path === '$.items[1].id',
  );
  assert.throws(
    () => normalizeOpenOptions({ items: [{ ...item, id: '   ' }] }),
    error => error.path === '$.items[0].id',
  );
});

test('selector defaults use the same field values without UniApp-only visibility behavior', () => {
  const request = normalizeSelectorOpenOptions({ items: [item], sourceSelector: '.source' });
  assert.equal(request.sourceVisibility, 'hidden');
  assert.equal(request.sourceMode, 'positional');
  assert.deepEqual(request.sourceStyles, [{ objectFit: 'cover', cornerRadius: 0 }]);
});

test('identified selector bindings survive prepend, append, and binding reordering', () => {
  const prepended = {
    ...item,
    id: 'prepended',
    url: 'https://example.com/prepended.jpg',
  };
  const appended = {
    ...item,
    id: 'appended',
    url: 'https://example.com/appended.jpg',
  };
  const request = normalizeSelectorOpenOptions({
    items: [prepended, item, appended],
    initialItemId: item.id,
    sourceBindings: [
      { itemId: appended.id, selector: '#appended', objectFit: 'contain' },
      { itemId: item.id, selector: '#wide-coast', cornerRadius: 12 },
    ],
  });

  assert.equal(request.index, 1);
  assert.equal(request.sourceMode, 'identified');
  assert.deepEqual(request.sourceBindings, [
    {
      itemId: appended.id,
      itemIndex: 2,
      selector: '#appended',
      objectFit: 'contain',
      cornerRadius: 0,
    },
    {
      itemId: item.id,
      itemIndex: 1,
      selector: '#wide-coast',
      objectFit: 'cover',
      cornerRadius: 12,
    },
  ]);
  assert.equal('sourceStyles' in request, false);

  const unmountedRequest = normalizeSelectorOpenOptions({
    items: [item],
    initialItemId: item.id,
    sourceBindings: [],
  });
  assert.equal(unmountedRequest.sourceMode, 'identified');
  assert.deepEqual(unmountedRequest.sourceBindings, []);
});

test('identified selector bindings reject ambiguous identities and mixed source modes', () => {
  const second = {
    ...item,
    id: 'second',
    url: 'https://example.com/second.jpg',
  };

  for (const [options, path] of [
    [
      { items: [item], index: 0, initialItemId: item.id },
      '$.initialItemId',
    ],
    [
      { items: [item], initialItemId: 'missing' },
      '$.initialItemId',
    ],
    [
      {
        items: [item],
        sourceSelector: '.source',
        sourceBindings: [{ itemId: item.id, selector: '#source' }],
      },
      '$.sourceBindings',
    ],
    [
      {
        items: [item],
        sourceStyles: [{}],
      },
      '$.sourceStyles',
    ],
    [
      {
        items: [item],
        sourceSelector: '   ',
      },
      '$.sourceSelector',
    ],
    [
      {
        items: [item],
        sourceStyles: [{}],
        sourceBindings: [{ itemId: item.id, selector: '#source' }],
      },
      '$.sourceBindings',
    ],
    [
      {
        items: [item],
        sourceBindings: [{ itemId: 'missing', selector: '#source' }],
      },
      '$.sourceBindings[0].itemId',
    ],
    [
      {
        items: [item, second],
        sourceBindings: [
          { itemId: item.id, selector: '#shared' },
          { itemId: second.id, selector: '#shared' },
        ],
      },
      '$.sourceBindings[1].selector',
    ],
    [
      {
        items: [item],
        sourceBindings: [
          { itemId: item.id, selector: '#first' },
          { itemId: item.id, selector: '#second' },
        ],
      },
      '$.sourceBindings[1].itemId',
    ],
  ]) {
    assert.throws(
      () => normalizeSelectorOpenOptions(options),
      error => error.path === path,
    );
  }
});
