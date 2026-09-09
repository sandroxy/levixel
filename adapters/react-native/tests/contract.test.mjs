import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { pathToFileURL } from 'node:url';

const contractModule = process.env.LEVIXEL_RN_CONTRACT_PATH
  ? pathToFileURL(path.resolve(process.env.LEVIXEL_RN_CONTRACT_PATH)).href
  : new URL('../src/contract.ts', import.meta.url).href;
const {
  normalizeActions,
  normalizeActionOptions,
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

test('actions remain business-neutral and validate IDs, flags, and callbacks', () => {
  const callback = () => {};
  const source = [{ id: 'inspect', label: 'Inspect', group: 'tools', onPress: callback }];
  const actions = normalizeActions(source);
  source[0].label = 'Changed';
  assert.equal(actions[0].label, 'Inspect');
  assert.equal(actions[0].onPress, callback);
  assert.deepEqual(normalizeActions(undefined), []);
  for (const invalid of [[{ id: 'a', label: 'A' }, { id: 'a', label: 'B' }],
    [{ id: 'a', label: ' ' }], [{ id: 'a', label: 'A', disabled: 'true' }],
    [{ id: 'a', label: 'A', onPress: 'save' }], [{ id: 'a', label: 'A', save: true }]]) {
    assert.throws(() => normalizeActions(invalid), TypeError);
  }
});

const { LevixelSessions } = await import(new URL('./session.ts', contractModule));

test('layout stays independent of action count and list icons are opt-in', () => {
  const actions = Array.from({ length: 10 }, (_, index) => ({ id: `a${index}`, label: `Action ${index}` }));
  const list = normalizeActionOptions(actions);
  assert.equal(list.actionLayout, 'list');
  assert.equal(list.actionListIcons, false);
  assert.equal(list.actions.length, 10);
  assert.equal(normalizeActionOptions(actions, 'list', true).actionListIcons, true);
  assert.equal(normalizeActionOptions([{ ...actions[0], icon: 'https://example.com/icon.png' }], 'grid').actionLayout, 'grid');
  assert.throws(() => normalizeActionOptions(actions, 'grid'), /actions\[0\]\.icon/);
  assert.throws(() => normalizeActionOptions(actions, 'auto'), /actionLayout/);
  assert.throws(() => normalizeActionOptions(actions, 'list', 'true'), /actionListIcons/);
});
test('callbacks belong to their opening snapshot and are released on dismiss', () => {
  const sessions = new LevixelSessions();
  const calls = [];
  const actions = [{ id: 'custom', label: 'Custom', onPress: context => calls.push(['old', context.itemId]) }];
  sessions.begin('one', actions);
  actions[0].onPress = context => calls.push(['new', context.itemId]);
  sessions.begin('two', actions);
  const event = { type: 'action', payload: { sessionId: 's1', galleryId: 'g', index: 0,
    itemId: 'original', mediaType: 'image', actionId: 'custom' }, time: 1 };
  sessions.dispatch('one', event, event => { event.payload.itemId = 'mutated'; });
  sessions.dispatch('two', { ...event, payload: { ...event.payload, itemId: 'second' } });
  sessions.dispatch('one', { ...event, type: 'dismiss' });
  sessions.dispatch('one', event);
  assert.deepEqual(calls, [['old', 'original'], ['new', 'second']]);
});

test('ending a replaced request preserves the new session and ignores late old events', () => {
  const sessions = new LevixelSessions();
  const calls = [];
  const received = [];
  const action = { id: 'inspect', label: 'Inspect', onPress: context => calls.push(context.sessionId) };
  sessions.begin('old-request', [action]);
  sessions.begin('new-request', [action]);
  const event = { type: 'action', payload: { sessionId: 'new-session', galleryId: 'g', index: 0,
    itemId: 'image-1', mediaType: 'image', actionId: 'inspect' }, time: 1 };
  sessions.dispatch('old-request', { ...event, type: 'dismiss', payload: { ...event.payload, sessionId: 'old-session' } });
  sessions.dispatch('old-request', event, value => received.push(value.type));
  sessions.dispatch('new-request', event, value => received.push(value.type));
  assert.deepEqual(calls, ['new-session']);
  assert.deepEqual(received, ['action']);
});

test('disabled actions and cancelled requests never invoke business callbacks', () => {
  const sessions = new LevixelSessions();
  const calls = [];
  const action = { id: 'inspect', label: 'Inspect', disabled: true, onPress: () => calls.push('called') };
  const event = { type: 'action', payload: { sessionId: 's', galleryId: 'g', index: 0,
    itemId: 'image-1', mediaType: 'image', actionId: 'inspect' }, time: 1 };
  sessions.begin('disabled', [action]);
  sessions.dispatch('disabled', event);
  sessions.begin('cancelled', [{ ...action, disabled: false }]);
  sessions.end('cancelled');
  sessions.dispatch('cancelled', event);
  assert.deepEqual(calls, []);
});
