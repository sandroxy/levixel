import assert from 'node:assert/strict';
import test from 'node:test';

import {
  captureZoomedViewport,
  imageLayout,
  resolveSourceGeometry,
  restoreZoomedViewport,
} from '../dist/geometry.js';

test('Wide Coast always starts fitted in an iPhone 11 sized viewport', () => {
  const layout = imageLayout(
    { width: 2400, height: 1600 },
    { width: 414, height: 896 },
  );
  assert.ok(Math.abs(layout.width - 414) < 0.001);
  assert.ok(Math.abs(layout.height - 276) < 0.001);
  assert.ok(layout.maximumRelativeZoom > 4);
});

test('cover source geometry preserves clipping and visible content offsets', () => {
  const geometry = resolveSourceGeometry(
    {
      rect: { left: 20, top: 40, width: 200, height: 300 },
      imageSize: { width: 2400, height: 1600 },
      objectFit: 'cover',
      coordinateSpace: 'viewport',
      cornerRadius: 14,
    },
    undefined,
    { left: 0, top: 0, width: 414, height: 896 },
  );
  assert.ok(geometry);
  assert.deepEqual(geometry.visible, { left: 20, top: 40, width: 200, height: 300 });
  assert.equal(geometry.content.left, -125);
  assert.equal(geometry.content.top, 0);
  assert.equal(geometry.content.width, 450);
  assert.equal(geometry.content.height, 300);
  assert.equal(geometry.cornerRadius, 14);
});

test('full-image handoff preserves relative zoom and normalized visual center', () => {
  const previewLayout = imageLayout(
    { width: 400, height: 600 },
    { width: 390, height: 844 },
  );
  const state = captureZoomedViewport(2.4, { x: -60, y: 15 }, previewLayout);
  assert.ok(state);
  const fullLayout = imageLayout(
    { width: 1600, height: 2400 },
    { width: 390, height: 844 },
  );
  const restored = restoreZoomedViewport(state, fullLayout, { width: 390, height: 844 });
  assert.equal(restored.zoom, 2.4);
  const recaptured = captureZoomedViewport(restored.zoom, restored.pan, fullLayout);
  assert.ok(recaptured);
  assert.ok(Math.abs(recaptured.normalizedCenter.x - state.normalizedCenter.x) < 0.0001);
  assert.ok(Math.abs(recaptured.normalizedCenter.y - state.normalizedCenter.y) < 0.0001);
});
