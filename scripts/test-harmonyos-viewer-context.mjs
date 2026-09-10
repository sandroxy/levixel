import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import test from 'node:test';

// Execute the actual ArkTS logic. Component builders are excluded from these
// unit tests; the ArkUI compiler and simulator validate rendering separately.
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
const hostUrl = new URL(
  '../native/harmonyos/levixel/src/main/ets/components/LevixelViewerHost.ets',
  import.meta.url,
);
const videoUrl = new URL(
  '../native/harmonyos/levixel/src/main/ets/components/LevixelVideoPlayer.ets',
  import.meta.url,
);
const componentUrls = new Set([hostUrl.href, videoUrl.href]);
const sourceUrls = new Set([contextUrl.href, modelUrl.href, controllerUrl.href, geometryUrl.href, ...componentUrls]);

function componentLogic(source) {
  return source
    .replace(/^import .+ from '@[^']+';\n/gm, '')
    .replace(/^import .+ from '\.\/Levixel(?:ImageViewer|VideoPlayer)';\n/gm, '')
    .replace(/^  @Builder\n[\s\S]*?^  }\n/gm, '')
    .replace(/^  build\(\) \{[\s\S]*?^  }\n/gm, '')
    .replace(/^@Component\n/gm, '')
    .replace(/export struct /g, 'export class ')
    .replace(/@(State|Prop)\s+/g, '')
    .replace(/@Watch\('[^']+'\)\s*/g, '');
}

const loader = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (sourceUrls.has(context.parentURL) && specifier.startsWith('.')) {
      const url = new URL(`${specifier}.ets`, context.parentURL).href;
      if (sourceUrls.has(url)) return { url, shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (!sourceUrls.has(url)) {
      return nextLoad(url, context);
    }
    let source = readFileSync(new URL(url), 'utf8');
    if (componentUrls.has(url)) {
      source = 'const Curve = { EaseOut: 0 }; class XComponentController {}\n' + componentLogic(source);
    }
    return {
      format: 'module',
      shortCircuit: true,
      source: stripTypeScriptTypes(source, {
        mode: 'transform',
        sourceUrl: url,
      }),
    };
  },
});
const { LevixelViewerContext } = await import(contextUrl.href);
const { LevixelSourceImageFit, clampLevixelPan, snapshotLevixelActions } = await import(modelUrl.href);
const { LevixelController, resolveLevixelContext } = await import(controllerUrl.href);
const { LevixelViewerHost } = await import(hostUrl.href);
const { LevixelVideoPlayer } = await import(videoUrl.href);
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

test('zoomed pan clamps to actual contained image edges on each axis', () => {
  assert.deepEqual(clampLevixelPan(1, 90, -90, 390, 260, 390, 844), { x: 0, y: 0 });
  assert.deepEqual(clampLevixelPan(2, 999, -999, 390, 260, 390, 844), { x: 195, y: 0 });
  assert.deepEqual(clampLevixelPan(3, -999, 999, 300, 600, 390, 844), { x: -255, y: 478 });
});

test('drawer configuration is snapshotted and cannot use duplicate action IDs', () => {
  const actions = [{ id: 'inspect', label: 'Inspect', group: 'tools', onPress() {} }];
  const copy = snapshotLevixelActions(actions);
  actions[0].label = 'Changed';
  actions.push({ id: 'other', label: 'Other' });
  assert.equal(copy.length, 1);
  assert.equal(copy[0].label, 'Inspect');
  assert.throws(() => snapshotLevixelActions([copy[0], copy[0]]), /unique/);
});

test('controller close, retry, Back, and event subscriptions follow mounted viewer lifetime', () => {
  const controller = new LevixelController();
  const context = resolveLevixelContext(controller);
  const calls = [];
  const unsubscribe = controller.onEvent(event => calls.push(event.type));
  const registration = context.registerViewer(() => {}, () => {}, () => calls.push('close'), () => true, () => true);
  context.emit({ type: 'opened', payload: {}, time: 1 });
  assert.equal(controller.retry(), true);
  assert.equal(controller.handleBack(), true);
  controller.close();
  unsubscribe();
  context.emit({ type: 'dismiss', payload: {}, time: 2 });
  context.unregisterViewer(registration);
  assert.equal(controller.retry(), false);
  assert.equal(controller.handleBack(), false);
  controller.close();
  assert.deepEqual(calls, ['opened', 'close']);
});

test('an event listener cannot corrupt another listener media identity', () => {
  const controller = new LevixelController();
  const context = resolveLevixelContext(controller);
  const identities = [];
  controller.onEvent(event => { event.payload.itemId = 'changed'; });
  controller.onEvent(event => identities.push(event.payload.itemId));
  const event = { type: 'action', payload: { sessionId: 'one', galleryId: 'one', index: 0,
    itemId: 'original', mediaType: 'image', actionId: 'inspect' }, time: 1 };
  context.emit(event);
  assert.equal(event.payload.itemId, 'original');
  assert.deepEqual(identities, ['original']);
});

test('action layout is explicit and grid icons are required', () => {
  const actions = Array.from({ length: 10 }, (_, index) => ({ id: `a${index}`, label: `Action ${index}` }));
  assert.equal(snapshotLevixelActions(actions).length, 10);
  assert.throws(() => snapshotLevixelActions(actions, 'grid'), /actions\[0\]\.icon/);
  assert.equal(snapshotLevixelActions([{ ...actions[0], icon: 'https://example.com/icon.png' }], 'grid').length, 1);
  assert.throws(() => snapshotLevixelActions(actions, 'auto'), /actionLayout/);
});

test('subscriptions added during dispatch start with the next event', () => {
  const context = new LevixelViewerContext();
  const calls = [];
  const second = () => calls.push('second');
  context.onEvent(() => { calls.push('first'); context.onEvent(second); });
  const event = { type: 'opened', payload: { sessionId: 'one', galleryId: 'one', index: 0,
    itemId: 'media-a', mediaType: 'image' }, time: 1 };
  context.emit(event);
  assert.deepEqual(calls, ['first']);
  context.emit(event);
  assert.deepEqual(calls, ['first', 'first', 'second']);
});

test('simultaneous viewers and remounts cannot share a session identity', t => {
  t.mock.method(Date, 'now', () => 123);
  const first = new LevixelViewerContext();
  const second = new LevixelViewerContext();
  const ids = [first.createSessionId(), second.createSessionId(), first.createSessionId()];
  const mounted = first.registerViewer(() => {}, () => {});
  first.unregisterViewer(mounted);
  first.registerViewer(() => {}, () => {});
  ids.push(first.createSessionId());
  assert.equal(new Set(ids).size, 4);
});

function openedHost() {
  const host = new LevixelViewerHost();
  host.controller = new LevixelController();
  host.items = [{ id: 'media-a', mediaType: 'image', sourceUrl: 'https://example.com/full.jpg',
    thumbnailUrl: 'https://example.com/preview.jpg', aspectWidth: 400, aspectHeight: 300 }];
  host.aboutToAppear();
  host.rootWidth = 400;
  host.rootHeight = 800;
  host.sessionItems = host.items.slice();
  host.sessionId = 'one';
  host.viewerOpen = true;
  host.contentVisible = true;
  return host;
}

test('repeated close preserves the first in-flight transition and emits one dismiss', async () => {
  const host = openedHost();
  const events = [];
  host.onEvent = event => events.push(event.type);
  let resolveCapture;
  host.captureViewerState = () => new Promise(resolve => { resolveCapture = resolve; });
  host.performCloseFadeFallback = () => host.finishClose();
  const closing = host.closeViewer();
  const token = host.transitionToken;
  await host.closeViewer();
  assert.equal(host.viewerOpen, true);
  assert.equal(host.transitionToken, token);
  assert.deepEqual(events, []);
  resolveCapture(null);
  await closing;
  assert.equal(host.viewerOpen, false);
  assert.deepEqual(events, ['dismiss']);
});

test('zoomed close captures the current image scale and viewport crop without a reset', async () => {
  const host = openedHost();
  host.zoomScale = 2;
  host.panX = -75;
  const pixelMap = {};
  host.imageResourceCache.set(host.items[0].thumbnailUrl, { pixelMap, width: 400, height: 300 });
  let captured;
  const capture = host.captureViewerState.bind(host);
  host.captureViewerState = async item => { captured = await capture(item); return captured; };
  host.resolveCloseTargetState = async () => null;
  host.performCloseFadeFallback = () => {};
  await host.closeViewer();
  assert.equal(host.zoomScale, 2);
  assert.equal(host.panX, -75);
  assertRect(captured.geometry.visibleFrame, { left: 0, top: 100, width: 400, height: 600 });
  assertRect(captured.geometry.contentFrame, { left: -275, top: 0, width: 800, height: 600 });
  host.finishClose();
  assert.equal(host.zoomScale, 1);
});

test('host removal cannot reopen a session from its dismiss callback', async () => {
  const host = openedHost();
  host.captureSourceState = async () => null;
  const events = [];
  host.onEvent = event => {
    events.push(event.type);
    if (event.type === 'dismiss') host.controller.open('media-a');
  };
  host.aboutToDisappear();
  await Promise.resolve();
  assert.deepEqual(host.sessionItems, []);
  assert.equal(host.viewerOpen, false);
  assert.equal(host.controller.handleBack(), false);
  assert.deepEqual(events, ['dismiss']);
});

test('media callbacks stop as soon as a session starts closing', () => {
  const host = openedHost();
  const events = [];
  host.onEvent = event => events.push(event.type);
  host.closing = true;
  host.mediaState('media-a', 'one', false);
  assert.deepEqual(host.failedIds, []);
  assert.deepEqual(events, []);
});

test('programmatic close waits for the action sheet to finish dismissing', async () => {
  const host = openedHost();
  host.actionsVisible = true;
  host.actionSheetActive = true;
  let closeCount = 0;
  host.performCloseViewer = async () => { closeCount += 1; host.finishClose(); };
  await host.closeViewer();
  assert.equal(host.actionsVisible, false);
  assert.equal(closeCount, 0);
  assert.equal(host.controller.handleBack(), true);
  assert.equal(closeCount, 0);
  host.finishAction();
  assert.equal(closeCount, 1);
  assert.equal(host.viewerOpen, false);
});

test('an action dispatches once after dismissal and keeps its original media context', () => {
  const host = openedHost();
  host.actionsVisible = true;
  host.actionSheetActive = true;
  const callbacks = [];
  host.onEvent = event => { event.payload.itemId = 'changed-by-listener'; };
  const action = { id: 'inspect', label: 'Inspect', onPress: event => callbacks.push(event.payload) };
  host.selectAction(action);
  assert.deepEqual(callbacks, []);
  host.finishAction();
  host.finishAction();
  assert.equal(callbacks.length, 1);
  assert.equal(callbacks[0].itemId, 'media-a');
  assert.equal(host.viewerOpen, true);
});

test('an opening keeps its theme and rejects unknown theme values', () => {
  const host = openedHost();
  host.finishClose();
  host.continueOpeningViewer = () => {};
  host.theme = 'unknown';
  assert.throws(() => host.openViewer('media-a'), /theme must be/);
  host.theme = 'light';
  host.openViewer('media-a');
  host.theme = 'dark';
  assert.equal(host.sessionTheme, 'light');
  host.finishClose();
});

for (const [command, state] of [['playPlayer', 'prepared'], ['pausePlayer', 'playing']]) {
  test(`a late ${command} rejection cannot fail a replacement video player`, async () => {
    const video = new LevixelVideoPlayer();
    let rejectCommand;
    const pending = new Promise((_resolve, reject) => { rejectCommand = reject; });
    video.active = true;
    video.player = { state, play: () => pending, pause: () => pending };
    video.playbackGeneration = 1;
    const states = [];
    video.onMediaState = loaded => states.push(loaded);
    video[command]();
    video.playbackGeneration = 2;
    video.player = { state: 'prepared' };
    rejectCommand(new Error('Old player was released'));
    await Promise.resolve();
    assert.equal(video.playbackFailed, false);
    assert.deepEqual(states, []);
  });
}
