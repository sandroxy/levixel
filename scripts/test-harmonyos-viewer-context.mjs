import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

// The registry contains no ArkUI syntax or platform dependencies. Execute its
// actual ArkTS source; only the .ets extension and type syntax need a loader.
const contextUrl = new URL(
  '../native/harmonyos/levixel/src/main/ets/controller/LevixelViewerContext.ets',
  import.meta.url,
);
const modelUrl = new URL(
  '../native/harmonyos/levixel/src/main/ets/model/LevixelModels.ets',
  import.meta.url,
);
const controllerUrl = new URL(
  '../native/harmonyos/levixel/src/main/ets/controller/LevixelController.ets',
  import.meta.url,
);
const geometryUrl = new URL(
  '../native/harmonyos/levixel/src/main/ets/model/LevixelTransitionGeometry.ets',
  import.meta.url,
);
const sourceUrls = new Set([contextUrl.href, modelUrl.href, controllerUrl.href, geometryUrl.href]);
const loader = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (context.parentURL === contextUrl.href && specifier === '../model/LevixelModels') {
      return { url: modelUrl.href, shortCircuit: true };
    }
    if (context.parentURL === controllerUrl.href && specifier === './LevixelViewerContext') {
      return { url: contextUrl.href, shortCircuit: true };
    }
    if (context.parentURL === contextUrl.href && specifier === '../model/LevixelTransitionGeometry') {
      return { url: geometryUrl.href, shortCircuit: true };
    }
    if (context.parentURL === geometryUrl.href && specifier === './LevixelModels') {
      return { url: modelUrl.href, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!sourceUrls.has(url)) {
      return nextLoad(url, context);
    }
    return {
      format: 'module',
      shortCircuit: true,
      source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), {
        mode: 'transform',
        sourceUrl: url,
      }),
    };
  },
});
const { LevixelViewerContext } = await import(contextUrl.href);
const { LevixelSourceImageFit } = await import(modelUrl.href);
const { LevixelController, resolveLevixelContext } = await import(controllerUrl.href);
const { imageContentFrame, intersectRects, resolveImageGeometry, mapSourceSnapshotToTarget } =
  await import(geometryUrl.href);
loader.deregister();

const frame = { left: 12, top: 80, width: 160, height: 120 };
const viewport = { left: 0, top: 60, width: 390, height: 640 };

function registerSource(context, itemId, { viewportId = '', hidden = [] } = {}) {
  const registration = context.registerSource(
    itemId, viewportId, 14, LevixelSourceImageFit.COVER,
    (value) => hidden.push(value),
  );
  return { ...registration, hidden };
}

function mountSource(context, itemId, options) {
  const registration = registerSource(context, itemId, options);
  context.updateSourceFrame(itemId, registration.registrationId, frame);
  context.updateSourceVisibility(itemId, registration.registrationId, true);
  return registration;
}

test('one explicit controller preserves context identity across independent component callers', () => {
  const controller = new LevixelController();
  const viewerContext = resolveLevixelContext(controller);
  const sourceContext = resolveLevixelContext(controller);
  const viewportContext = resolveLevixelContext(controller);
  assert.equal(viewerContext, sourceContext);
  assert.equal(viewerContext, viewportContext);
  const opened = [];
  viewerContext.registerViewer((id) => opened.push(id), () => {});
  mountSource(sourceContext, 'media-a', { viewportId: 'messages' });
  const viewportToken = viewportContext.registerViewport('messages');
  viewportContext.updateViewportFrame('messages', viewportToken, viewport);
  assert.deepEqual(viewerContext.resolveSource('media-a').viewportInWindow, viewport);
  controller.open('media-a');
  assert.deepEqual(opened, ['media-a']);
});

test('separate controllers isolate source identity, visibility, and open handlers', () => {
  const firstController = new LevixelController();
  const secondController = new LevixelController();
  const first = resolveLevixelContext(firstController);
  const second = resolveLevixelContext(secondController);
  assert.notEqual(first, second);
  const firstSource = mountSource(first, 'shared-item');
  const secondSource = mountSource(second, 'shared-item');
  assert.notEqual(firstSource.snapshotId, secondSource.snapshotId);
  assert.notEqual(first.viewerSnapshotId('shared-item'), second.viewerSnapshotId('shared-item'));
  const firstOpened = [];
  const secondOpened = [];
  first.registerViewer((id) => firstOpened.push(id), () => {});
  second.registerViewer((id) => secondOpened.push(id), () => {});
  firstController.open('shared-item');
  first.setHiddenSource('shared-item');
  assert.deepEqual(firstOpened, ['shared-item']);
  assert.deepEqual(secondOpened, []);
  assert.equal(firstSource.hidden.at(-1), true);
  assert.equal(secondSource.hidden.at(-1), false);
  secondController.open('shared-item');
  assert.deepEqual(secondOpened, ['shared-item']);
});

test('missing, copied, or fabricated controllers cannot obtain another viewer context', () => {
  const controller = new LevixelController();
  assert.throws(() => resolveLevixelContext(null), /require the same LevixelController instance/);
  for (const invalid of [
    undefined,
    {},
    { ...controller },
    Object.create(LevixelController.prototype),
    'controller',
    1,
  ]) {
    assert.throws(() => resolveLevixelContext(invalid), /new LevixelController/);
  }
  assert.throws(() => controller.open('media-a'), /LevixelViewer/);
});

test('source resolution requires the requested stable identity, visibility, and measured frame', () => {
  const context = new LevixelViewerContext();
  const source = registerSource(context, 'media-a');
  assert.equal(context.resolveSource('media-a'), null);
  context.updateSourceVisibility('media-a', source.registrationId, true);
  assert.equal(context.resolveSource('media-a'), null);
  context.updateSourceFrame('media-a', source.registrationId, frame);
  assert.deepEqual(context.resolveSource('media-a'), {
    snapshotId: source.snapshotId,
    frameInWindow: frame,
    viewportInWindow: null,
    cornerRadius: 14,
    imageFit: LevixelSourceImageFit.COVER,
  });
  mountSource(context, 'media-b');
  assert.equal(context.resolveSource('unmounted-media'), null);
  context.updateSourceVisibility('media-a', source.registrationId, false);
  assert.equal(context.resolveSource('media-a'), null);
  assert.ok(context.resolveSource('media-b'));
});

test('snapshot identities stay unique across viewers and remounted sources', () => {
  const firstContext = new LevixelViewerContext();
  const secondContext = new LevixelViewerContext();
  const first = registerSource(firstContext, 'media-a');
  const second = registerSource(secondContext, 'media-a');
  firstContext.unregisterSource('media-a', first.registrationId);
  const remounted = registerSource(firstContext, 'media-a');
  assert.equal(new Set([first.snapshotId, second.snapshotId, remounted.snapshotId]).size, 3);
});

test('recycling may overlap registrations but rejects two visible sources for one item', () => {
  const context = new LevixelViewerContext();
  const oldSource = mountSource(context, 'media-a');
  const newSource = registerSource(context, 'media-a');
  assert.equal(context.resolveSource('media-a').snapshotId, oldSource.snapshotId);
  context.updateSourceFrame('media-a', newSource.registrationId, frame);
  context.updateSourceVisibility('media-a', newSource.registrationId, true);
  assert.throws(() => context.resolveSource('media-a'), /more than one visible mounted source/);
  context.updateSourceVisibility('media-a', oldSource.registrationId, false);
  assert.equal(context.resolveSource('media-a').snapshotId, newSource.snapshotId);
  context.unregisterSource('media-a', oldSource.registrationId);
  assert.equal(context.resolveSource('media-a').snapshotId, newSource.snapshotId);
});

test('stale or mismatched source callbacks cannot modify a replacement cell', () => {
  const context = new LevixelViewerContext();
  const oldSource = mountSource(context, 'media-a');
  context.unregisterSource('media-a', oldSource.registrationId);
  const current = mountSource(context, 'media-a');
  context.updateSourceFrame('media-a', oldSource.registrationId, { ...frame, top: 999 });
  context.updateSourceVisibility('media-a', oldSource.registrationId, false);
  context.updateSourceFrame('media-b', current.registrationId, { ...frame, top: 999 });
  context.updateSourceVisibility('media-b', current.registrationId, false);
  context.unregisterSource('media-b', current.registrationId);
  context.unregisterSource('media-a', oldSource.registrationId);
  assert.equal(context.resolveSource('media-a').snapshotId, current.snapshotId);
  assert.deepEqual(context.resolveSource('media-a').frameInWindow, frame);
});

test('declared viewport must be mounted and measured, and stale callbacks cannot remove its replacement', () => {
  const context = new LevixelViewerContext();
  mountSource(context, 'media-a', { viewportId: 'messages' });
  assert.equal(context.resolveSource('media-a'), null);
  const oldViewport = context.registerViewport('messages');
  assert.equal(context.resolveSource('media-a'), null);
  assert.throws(() => context.registerViewport('messages'), /mounted more than once/);
  context.updateViewportFrame('messages', oldViewport, viewport);
  assert.deepEqual(context.resolveSource('media-a').viewportInWindow, viewport);
  context.unregisterViewport('messages', oldViewport);
  assert.equal(context.resolveSource('media-a'), null);
  const currentViewport = context.registerViewport('messages');
  context.updateViewportFrame('messages', currentViewport, viewport);
  context.updateViewportFrame('messages', oldViewport, { ...viewport, top: 999 });
  context.unregisterViewport('messages', oldViewport);
  assert.deepEqual(context.resolveSource('media-a').viewportInWindow, viewport);
});

test('source and viewport geometry are isolated from caller mutation', () => {
  const context = new LevixelViewerContext();
  const source = mountSource(context, 'media-a', { viewportId: 'messages' });
  const viewportToken = context.registerViewport('messages');
  const mutableFrame = { ...frame };
  const mutableViewport = { ...viewport };
  context.updateSourceFrame('media-a', source.registrationId, mutableFrame);
  context.updateViewportFrame('messages', viewportToken, mutableViewport);
  mutableFrame.top = 999;
  mutableViewport.height = 0;
  const resolved = context.resolveSource('media-a');
  assert.deepEqual(resolved.frameInWindow, frame);
  assert.deepEqual(resolved.viewportInWindow, viewport);
  resolved.frameInWindow.left = -999;
  resolved.viewportInWindow.top = -999;
  assert.deepEqual(context.resolveSource('media-a').frameInWindow, frame);
  assert.deepEqual(context.resolveSource('media-a').viewportInWindow, viewport);
});

test('hidden source follows media identity through registration, switching, and removal', () => {
  const context = new LevixelViewerContext();
  const first = mountSource(context, 'media-a');
  const second = mountSource(context, 'media-b');
  context.setHiddenSource('media-a');
  assert.equal(first.hidden.at(-1), true);
  assert.equal(second.hidden.at(-1), false);
  const replacement = registerSource(context, 'media-a');
  assert.deepEqual(replacement.hidden, [true]);
  const callbackCount = first.hidden.length;
  context.setHiddenSource('media-a');
  assert.equal(first.hidden.length, callbackCount);
  context.unregisterSource('media-a', first.registrationId);
  assert.equal(first.hidden.at(-1), false);
  assert.equal(replacement.hidden.at(-1), true);
  context.setHiddenSource('media-b');
  assert.equal(replacement.hidden.at(-1), false);
  assert.equal(second.hidden.at(-1), true);
  context.setHiddenSource('');
  assert.equal(second.hidden.at(-1), false);
});

test('viewer registration dispatches once, restores sources on removal, and ignores stale removal', () => {
  const context = new LevixelViewerContext();
  const source = mountSource(context, 'media-a');
  const opened = [];
  const prepared = [];
  assert.throws(() => context.open('media-a'), /mounted LevixelViewer using the same controller/);
  context.prepare('media-a');
  const oldViewer = context.registerViewer((id) => opened.push(id), (id) => prepared.push(id));
  assert.throws(() => context.registerViewer(() => {}, () => {}), /more than one mounted LevixelViewer/);
  context.open('media-a');
  context.prepare('media-a');
  assert.deepEqual(opened, ['media-a']);
  assert.deepEqual(prepared, ['media-a']);
  context.setHiddenSource('media-a');
  context.unregisterViewer(oldViewer);
  assert.equal(source.hidden.at(-1), false);
  assert.throws(() => context.open('media-a'), /mounted LevixelViewer using the same controller/);
  context.prepare('media-a');
  assert.deepEqual(prepared, ['media-a']);
  const newViewer = context.registerViewer((id) => opened.push(id), (id) => prepared.push(id));
  assert.notEqual(oldViewer, newViewer);
  context.unregisterViewer(oldViewer);
  context.open('media-b');
  assert.deepEqual(opened, ['media-a', 'media-b']);
});

test('live source configuration changes preserve identity, frame, and visibility', () => {
  const context = new LevixelViewerContext();
  const source = mountSource(context, 'media-a');
  const viewportToken = context.registerViewport('messages');
  context.updateViewportFrame('messages', viewportToken, viewport);
  context.updateSourceConfiguration(
    'media-a', source.registrationId, 'messages', 20, LevixelSourceImageFit.CONTAIN,
  );
  assert.deepEqual(context.resolveSource('media-a'), {
    snapshotId: source.snapshotId,
    frameInWindow: frame,
    viewportInWindow: viewport,
    cornerRadius: 20,
    imageFit: LevixelSourceImageFit.CONTAIN,
  });
  context.updateSourceConfiguration(
    'media-a', source.registrationId, '', 0, LevixelSourceImageFit.FILL,
  );
  assert.equal(context.resolveSource('media-a').viewportInWindow, null);
  assert.equal(context.resolveSource('media-a').imageFit, LevixelSourceImageFit.FILL);
});

test('invalid live configuration fails without partially changing the registered source', () => {
  const context = new LevixelViewerContext();
  const source = mountSource(context, 'media-a');
  const original = context.resolveSource('media-a');
  for (const [viewportId, radius, imageFit] of [
    ['  ', 14, LevixelSourceImageFit.COVER],
    ['missing-viewport', -1, LevixelSourceImageFit.CONTAIN],
    ['missing-viewport', 20, 'unknown-fit'],
  ]) {
    assert.throws(() => context.updateSourceConfiguration(
      'media-a', source.registrationId, viewportId, radius, imageFit,
    ));
    assert.deepEqual(context.resolveSource('media-a'), original);
  }
});

test('stale source configuration cannot overwrite a newly mounted source', () => {
  const context = new LevixelViewerContext();
  const oldSource = mountSource(context, 'media-a');
  context.unregisterSource('media-a', oldSource.registrationId);
  const current = mountSource(context, 'media-a');
  const original = context.resolveSource('media-a');
  context.updateSourceConfiguration(
    'media-a', oldSource.registrationId, 'missing-viewport', 0, LevixelSourceImageFit.FILL,
  );
  context.updateSourceConfiguration(
    'media-b', current.registrationId, 'missing-viewport', 0, LevixelSourceImageFit.FILL,
  );
  assert.deepEqual(context.resolveSource('media-a'), original);
});

test('public identifiers, image fit, and corner radius reject invalid values', () => {
  const context = new LevixelViewerContext();
  for (const itemId of ['', ' \t\n']) {
    assert.throws(() => registerSource(context, itemId), /itemId must be/);
    assert.throws(() => context.open(itemId), /itemId must be/);
    assert.throws(() => context.prepare(itemId), /itemId must be/);
  }
  for (const viewportId of ['', ' \t\n']) {
    assert.throws(() => context.registerViewport(viewportId), /viewportId must be/);
  }
  assert.throws(() => registerSource(context, 'media-a', { viewportId: '  ' }), /viewportId must be/);
  for (const radius of [-1, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY]) {
    assert.throws(() => context.registerSource(
      'media-a', '', radius, LevixelSourceImageFit.COVER, () => {},
    ), /cornerRadius must be/);
  }
  assert.throws(() => context.registerSource(
    'media-a', '', 14, 'unknown-fit', () => {},
  ), /imageFit must be/);
});

test('clipped or unmounted sources do not make a visible replacement ambiguous', () => {
  const context = new LevixelViewerContext();
  const viewportToken = context.registerViewport('messages');
  context.updateViewportFrame('messages', viewportToken, viewport);
  const clipped = mountSource(context, 'media-a', { viewportId: 'messages' });
  context.updateSourceFrame('media-a', clipped.registrationId, { ...frame, top: 700 });
  mountSource(context, 'media-a', { viewportId: 'removed-viewport' });
  const current = mountSource(context, 'media-a', { viewportId: 'messages' });
  assert.equal(context.resolveSource('media-a').snapshotId, current.snapshotId);
  context.updateSourceFrame('media-a', clipped.registrationId, { ...frame, top: 699.5 });
  assert.throws(() => context.resolveSource('media-a'), /more than one visible mounted source/);
});

test('any positive viewport intersection is a source; touching an edge is not', () => {
  const context = new LevixelViewerContext();
  const viewportToken = context.registerViewport('messages');
  context.updateViewportFrame('messages', viewportToken, viewport);
  const source = mountSource(context, 'media-a', { viewportId: 'messages' });
  context.updateSourceFrame('media-a', source.registrationId, { ...frame, top: 699.999 });
  assert.ok(context.resolveSource('media-a'));
  context.updateSourceFrame('media-a', source.registrationId, { ...frame, top: 700 });
  assert.equal(context.resolveSource('media-a'), null);
});

test('empty and non-finite geometry cannot become a source or create false duplicates', () => {
  const context = new LevixelViewerContext();
  const invalid = mountSource(context, 'media-a');
  const current = mountSource(context, 'media-a');
  for (const invalidFrame of [
    { ...frame, width: 0 },
    { ...frame, height: -1 },
    { ...frame, left: Number.NaN },
    { ...frame, top: Number.POSITIVE_INFINITY },
    { ...frame, width: Number.POSITIVE_INFINITY },
    { ...frame, left: Number.MAX_VALUE, width: Number.MAX_VALUE },
  ]) {
    context.updateSourceFrame('media-a', invalid.registrationId, invalidFrame);
    assert.equal(context.resolveSource('media-a').snapshotId, current.snapshotId);
  }
  const viewportToken = context.registerViewport('messages');
  context.updateSourceConfiguration(
    'media-a', current.registrationId, 'messages', 14, LevixelSourceImageFit.COVER,
  );
  context.updateViewportFrame('messages', viewportToken, { ...viewport, height: 0 });
  assert.equal(context.resolveSource('media-a'), null);
  context.updateViewportFrame('messages', viewportToken, viewport);
  assert.equal(context.resolveSource('media-a').snapshotId, current.snapshotId);
});

function assertRect(actual, expected) {
  assert.ok(actual);
  for (const key of ['left', 'top', 'width', 'height']) {
    assert.ok(Math.abs(actual[key] - expected[key]) < 0.000001,
      `${key}: expected ${expected[key]}, received ${actual[key]}`);
  }
}

test('a cold square cover snapshot expands without changing the crop aspect ratio', () => {
  const source = { left: 20, top: 100, width: 180, height: 180 };
  const target = { left: 0, top: 250, width: 390, height: 260 };
  const snapshotAtTarget = mapSourceSnapshotToTarget(
    2400, 1600, source, target, LevixelSourceImageFit.COVER,
  );
  assertRect(snapshotAtTarget, { left: 65, top: 250, width: 260, height: 260 });
  assert.equal(snapshotAtTarget.width / snapshotAtTarget.height, source.width / source.height);
  const geometry = resolveImageGeometry(
    540, 540, snapshotAtTarget, LevixelSourceImageFit.FILL, target,
  );
  assertRect(geometry.visibleFrame, snapshotAtTarget);
  assertRect(geometry.contentFrame, { left: 0, top: 0, width: 260, height: 260 });
});

test('a cold portrait crop keeps vertical framing when its full image is revealed', () => {
  const source = { left: 30, top: 120, width: 180, height: 180 };
  const target = { left: 80, top: 0, width: 260, height: 390 };
  assertRect(mapSourceSnapshotToTarget(
    1600, 2400, source, target, LevixelSourceImageFit.COVER,
  ), { left: 80, top: 65, width: 260, height: 260 });
});

test('a contained snapshot expands its existing letterbox outside the target image', () => {
  const source = { left: 20, top: 100, width: 180, height: 180 };
  const target = { left: 0, top: 250, width: 390, height: 260 };
  const snapshotAtTarget = mapSourceSnapshotToTarget(
    2400, 1600, source, target, LevixelSourceImageFit.CONTAIN,
  );
  assertRect(snapshotAtTarget, { left: 0, top: 185, width: 390, height: 390 });
  const geometry = resolveImageGeometry(
    540, 540, snapshotAtTarget, LevixelSourceImageFit.FILL, target,
  );
  assertRect(geometry.visibleFrame, target);
  assertRect(geometry.contentFrame, { left: 0, top: -65, width: 390, height: 390 });
});

test('fill snapshots intentionally remove host stretching when mapped to the full media', () => {
  const source = { left: 20, top: 100, width: 180, height: 180 };
  const target = { left: 0, top: 250, width: 390, height: 260 };
  assertRect(mapSourceSnapshotToTarget(
    2400, 1600, source, target, LevixelSourceImageFit.FILL,
  ), target);
});

test('partial source clipping retains the original image scale and crop offsets', () => {
  const source = { left: 20, top: 100, width: 180, height: 180 };
  const clipping = { left: 20, top: 279.5, width: 180, height: 0.5 };
  const geometry = resolveImageGeometry(
    2400, 1600, source, LevixelSourceImageFit.COVER, clipping,
  );
  assertRect(geometry.visibleFrame, clipping);
  assertRect(geometry.contentFrame, { left: -45, top: -179.5, width: 270, height: 180 });
  assert.equal(resolveImageGeometry(
    2400, 1600, source, LevixelSourceImageFit.COVER,
    { left: 20, top: 280, width: 180, height: 100 },
  ), null);
});

test('image containment does not fabricate content in an empty letterbox region', () => {
  const source = { left: 20, top: 100, width: 180, height: 180 };
  assert.equal(resolveImageGeometry(
    2400, 1600, source, LevixelSourceImageFit.CONTAIN,
    { left: 20, top: 100, width: 180, height: 30 },
  ), null);
  const geometry = resolveImageGeometry(
    2400, 1600, source, LevixelSourceImageFit.CONTAIN,
    { left: 20, top: 100, width: 180, height: 30.5 },
  );
  assertRect(geometry.visibleFrame, { left: 20, top: 130, width: 180, height: 0.5 });
});

test('viewport intersections preserve fractional visible edges and reject invalid rectangles', () => {
  assertRect(intersectRects(
    { left: 0, top: 0, width: 390, height: 844 },
    { left: 389.75, top: 843.5, width: 180, height: 180 },
  ), { left: 389.75, top: 843.5, width: 0.25, height: 0.5 });
  for (const invalid of [
    { left: 390, top: 100, width: 180, height: 180 },
    { left: 0, top: 0, width: 0, height: 180 },
    { left: Number.NaN, top: 0, width: 180, height: 180 },
    { left: 0, top: 0, width: Number.POSITIVE_INFINITY, height: 180 },
  ]) {
    assert.equal(intersectRects({ left: 0, top: 0, width: 390, height: 844 }, invalid), null);
  }
});

test('invalid media dimensions cannot produce infinite or stretched image geometry', () => {
  for (const invalidDimension of [0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    assert.throws(() => imageContentFrame(
      invalidDimension, 1600, frame, LevixelSourceImageFit.COVER,
    ), /finite positive dimensions/);
    assert.throws(() => mapSourceSnapshotToTarget(
      2400, invalidDimension, frame, viewport, LevixelSourceImageFit.COVER,
    ), /finite positive dimensions/);
  }
  assert.throws(() => imageContentFrame(2400, 1600, frame, 'unknown-fit'), /imageFit must be/);
  assert.throws(() => imageContentFrame(
    Number.MIN_VALUE, Number.MAX_VALUE, frame, LevixelSourceImageFit.COVER,
  ), /finite positive content frame/);
});
