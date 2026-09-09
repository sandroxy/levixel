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

test('actions copy callbacks and reject ambiguous or malformed configuration', () => {
  const onPress = () => {};
  const actions = [{ id: 'inspect', label: 'Inspect', group: 'tools', onPress }];
  const request = normalizeOpenOptions({ items: [item], actions });
  actions[0].label = 'Changed';
  assert.equal(request.actions[0].label, 'Inspect');
  assert.equal(request.actions[0].onPress, onPress);
  for (const invalid of [null, new Array(1), [{ id: 'x', label: 'X' }, { id: 'x', label: 'Y' }],
    [{ id: 'x', label: ' ' }], [{ id: 'x', label: 'X', disabled: 'true' }],
    [{ id: 'x', label: 'X', onPress: 'callback' }]]) {
    assert.throws(() => normalizeOpenOptions({ items: [item], actions: invalid }));
  }
});

test('drawer layout is explicit and only grid requires icons', () => {
  const actions = Array.from({ length: 10 }, (_, index) => ({ id: `a${index}`, label: `Action ${index}` }));
  const request = normalizeOpenOptions({ items: [item], actions });
  assert.equal(request.actionLayout, 'list');
  assert.equal(request.actionListIcons, false);
  assert.equal(request.actions.length, 10);
  const grid = normalizeOpenOptions({ items: [item], actionLayout: 'grid', actions: [{ ...actions[0], icon: 'https://example.com/icon.png' }] });
  assert.equal(grid.actionLayout, 'grid');
  assert.equal(grid.actions.length, 1);
  const selector = normalizeSelectorOpenOptions({ items: [item], actionLayout: 'list', actionListIcons: true, actions });
  assert.equal(selector.actionLayout, 'list');
  assert.equal(selector.actionListIcons, true);
  for (const [options, path] of [
    [{ actionLayout: 'grid', actions }, '$.actions[0].icon'],
    [{ actionLayout: 'auto' }, '$.actionLayout'],
    [{ actionLayout: null }, '$.actionLayout'],
    [{ actionListIcons: 'true' }, '$.actionListIcons'],
    [{ actionListIcons: null }, '$.actionListIcons'],
  ]) assert.throws(() => normalizeOpenOptions({ items: [item], ...options }), error => error.path === path);
  assert.deepEqual(normalizeOpenOptions({ items: [item], actionLayout: 'grid', actions: [] }).actions, []);
});
