import assert from 'node:assert/strict';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { chromium } from 'playwright-core';

const adapterRoot = resolve(join(fileURLToPath(new URL('.', import.meta.url)), '..'));
const packageDistRoot = resolve(process.env.LEVIXEL_WEB_DIST_ROOT ?? join(adapterRoot, 'dist'));
const chromeCandidates = [
  process.env.LEVIXEL_CHROME_PATH,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium-browser',
  '/usr/bin/chromium',
].filter(Boolean);
const executablePath = chromeCandidates.find(existsSync);
if (!executablePath)
  throw new Error('Set LEVIXEL_CHROME_PATH to a Chrome or Chromium executable');

const server = createServer((request, response) => {
  const pathname = decodeURIComponent(new URL(request.url ?? '/', 'http://127.0.0.1').pathname);
  if (
    pathname === '/tests/delayed.svg'
    || pathname === '/tests/delayed-full.svg'
    || pathname === '/tests/racing-full.svg'
  ) {
    const isFullImage = pathname.endsWith('delayed-full.svg');
    const isRacingFullImage = pathname.endsWith('racing-full.svg');
    setTimeout(() => {
      response.writeHead(200, {
        'Content-Type': 'image/svg+xml; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      response.end(isFullImage
        ? '<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1600"><rect width="2400" height="1600" fill="#678"/></svg>'
        : (isRacingFullImage
            ? '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1800"><rect width="1200" height="1800" fill="#567"/></svg>'
            : '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#345"/></svg>'));
    }, isRacingFullImage ? 40 : (isFullImage ? 900 : 250));
    return;
  }
  const servesPackagedDist = pathname.startsWith('/dist/');
  const root = servesPackagedDist ? packageDistRoot : adapterRoot;
  const relative = pathname === '/'
    ? 'tests/fixture.html'
    : (servesPackagedDist ? pathname.slice('/dist/'.length) : pathname.replace(/^\/+/, ''));
  const resolved = resolve(root, relative);
  if (
    (resolved !== root && !resolved.startsWith(`${root}${sep}`))
    || !existsSync(resolved)
    || !statSync(resolved).isFile()
  ) {
    response.writeHead(404).end('Not found');
    return;
  }
  const type = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.map': 'application/json; charset=utf-8',
  }[extname(resolved)] ?? 'application/octet-stream';
  response.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  createReadStream(resolved).pipe(response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const address = server.address();
if (!address || typeof address === 'string')
  throw new Error('Unable to start Levixel browser fixture server');

const browser = await chromium.launch({ executablePath, headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1 });
const pageErrors = [];
page.on('pageerror', error => pageErrors.push(error.message));

try {
  await page.goto(`http://127.0.0.1:${address.port}/tests/fixture.html`);
  await page.waitForFunction(() => window.levixelFixture?.events?.length > 0);
  const sourceRects = await page.locator('.source').evaluateAll(elements => elements.map((element) => {
    const rect = element.getBoundingClientRect();
    return { width: rect.width, height: rect.height };
  }));
  assert.equal(
    sourceRects.every(rect => Math.abs(rect.width - rect.height) < 0.01),
    true,
    'browser coverage must exercise uniformly cropped square thumbnails',
  );

  const openingHandoff = await page.evaluate(async () => {
    const samples = [];
    document.querySelector('.source').click();
    while (window.levixelFixture.results.length < 1) {
      await new Promise(resolve => requestAnimationFrame(resolve));
      const host = document.querySelector('[data-levixel-web-root]');
      const shadow = host?.shadowRoot;
      const snapshot = shadow?.querySelector('.snapshot');
      const content = shadow?.querySelector('.content');
      const media = shadow?.querySelector('.page .media-shell');
      samples.push({
        snapshot: Boolean(snapshot),
        contentOpacity: content ? Number.parseFloat(getComputedStyle(content).opacity) : 0,
        mediaOpacity: media ? Number.parseFloat(getComputedStyle(media).opacity) : 0,
      });
    }
    return {
      overlapFrames: samples.filter(sample => sample.snapshot
        && sample.contentOpacity === 1
        && sample.mediaOpacity === 1).length,
    };
  });
  assert.ok(
    openingHandoff.overlapFrames >= 1,
    'settled snapshot must cover at least one painted frame of visible viewer media',
  );
  const openState = await inspect(page);
  assert.equal(openState.counterCount, 0, 'viewer must not render a counter, even hidden');
  assert.equal(openState.currentImageCount, 1, 'current image page must use one rendering layer');
  assert.equal(openState.currentTransform.includes('scale(1)'), true);
  assert.equal(openState.sourceVisibility, 'hidden');
  assert.equal(openState.rootRole, 'dialog');
  assert.equal(openState.bodyOverflow, 'hidden');
  assert.deepEqual(openState.pageAriaHidden, [null, 'true', 'true']);

  const openingEvents = await page.evaluate(() => window.levixelFixture.events);
  assert.deepEqual(openingEvents.map(event => event.type), ['ready', 'sourceVisibilityChange']);
  assert.equal(openingEvents[1].payload.hidden, true);
  assert.equal(typeof openingEvents[1].time, 'number');

  await page.mouse.move(300, 422);
  await page.mouse.down();
  await page.mouse.move(70, 422, { steps: 8 });
  await page.mouse.up();
  await page.waitForFunction(() => window.levixelFixture.events.some(
    event => event.type === 'indexChange' && event.payload.currentIndex === 1,
  ));
  const pagedSources = await page.evaluate(() => ({
    first: document.querySelector('.source[data-index="0"]').style.visibility,
    second: document.querySelector('.source[data-index="1"]').style.visibility,
  }));
  assert.equal(pagedSources.first, '');
  assert.equal(pagedSources.second, 'hidden');

  await page.mouse.move(70, 422);
  await page.mouse.down();
  await page.mouse.move(320, 422, { steps: 8 });
  await page.mouse.up();
  await page.waitForFunction(() => window.levixelFixture.events.filter(
    event => event.type === 'indexChange' && event.payload.currentIndex === 0,
  ).length === 1);

  await page.mouse.dblclick(195, 422, { delay: 70 });
  await page.waitForTimeout(260);
  const zoomedTransform = await page.evaluate(() => {
    const host = document.querySelector('[data-levixel-web-root]');
    return host.shadowRoot.querySelector('.page:nth-child(1) .image').style.transform;
  });
  assert.notEqual(zoomedTransform.includes('scale(1)'), true, 'double tap must zoom the image');

  await page.mouse.move(195, 400);
  await page.mouse.down();
  await page.mouse.move(195, 620, { steps: 8 });
  await page.mouse.up();
  await page.waitForTimeout(80);
  assert.ok(await page.locator('[data-levixel-web-root]').count(), 'zoomed image must not vertically dismiss');

  await page.keyboard.press('Escape');
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  const closedState = await page.evaluate(() => ({
    sourceVisibility: document.querySelector('.source').style.visibility,
    bodyOverflow: document.body.style.overflow,
    events: window.levixelFixture.events,
  }));
  assert.equal(closedState.sourceVisibility, '');
  assert.equal(closedState.bodyOverflow, '');
  assert.deepEqual(closedState.events.slice(-2).map(event => event.type), [
    'sourceVisibilityChange',
    'dismiss',
  ]);
  assert.equal(closedState.events.at(-2).payload.hidden, false);
  assert.deepEqual(closedState.events.at(-1).payload, {});

  await page.locator('.source').nth(1).click();
  await page.waitForFunction(() => window.levixelFixture?.results?.length === 2);
  const wideState = await inspect(page);
  assert.equal(wideState.currentTransform.includes('scale(1)'), true);
  assert.ok(wideState.currentRect.width <= 390.01);
  assert.ok(wideState.currentRect.height < 300, 'landscape image must open aspect-fitted');

  await page.mouse.move(195, 400);
  await page.mouse.down();
  await page.mouse.move(195, 440, { steps: 5 });
  await page.mouse.up();
  await page.waitForTimeout(260);
  const cancelledDrag = await page.evaluate(() => {
    const host = document.querySelector('[data-levixel-web-root]');
    const shadow = host.shadowRoot;
    return {
      transform: shadow.querySelectorAll('.page')[1].style.transform,
      backdropOpacity: shadow.querySelector('.backdrop').style.opacity,
    };
  });
  assert.equal(cancelledDrag.transform, 'none');
  assert.equal(cancelledDrag.backdropOpacity, '1');

  await page.mouse.move(195, 400);
  await page.mouse.down();
  await page.mouse.move(195, 610, { steps: 10 });
  await page.mouse.up();
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  const finalEvents = await page.evaluate(() => window.levixelFixture.events);
  assert.equal(finalEvents.filter(event => event.type === 'dismiss').length, 2);

  await page.evaluate(() => window.levixelFixture.open(0));
  await page.waitForFunction(() => window.levixelFixture.results.length === 3);
  await page.evaluate(() => window.levixelFixture.open(1));
  await page.waitForFunction(() => window.levixelFixture.results.length === 4);
  const replacementState = await page.evaluate(() => ({
    roots: document.querySelectorAll('[data-levixel-web-root]').length,
    first: document.querySelector('.source[data-index="0"]').style.visibility,
    second: document.querySelector('.source[data-index="1"]').style.visibility,
    dismisses: window.levixelFixture.events.filter(event => event.type === 'dismiss').length,
  }));
  assert.deepEqual(replacementState, {
    roots: 1,
    first: '',
    second: 'hidden',
    dismisses: 2,
  });
  await page.evaluate(() => window.levixelFixture.closeLevixel());
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  const replacementEvents = await page.evaluate(() => window.levixelFixture.events);
  assert.equal(replacementEvents.filter(event => event.type === 'dismiss').length, 3);

  await page.evaluate(() => window.levixelFixture.open(2));
  await page.waitForFunction(() => window.levixelFixture.results.length === 5);
  const initialVideoChrome = await page.evaluate(() => {
    const host = document.querySelector('[data-levixel-web-root]');
    const shadow = host.shadowRoot;
    const current = shadow.querySelectorAll('.page')[2];
    return {
      videoCount: current.querySelectorAll('.video').length,
      posterCount: current.querySelectorAll('.poster').length,
      controlsVisible: current.querySelector('.video-controls').dataset.visible,
      controlsAriaHidden: current.querySelector('.video-controls').getAttribute('aria-hidden'),
      closeVisible: shadow.querySelector('.close-button').dataset.visible,
      closeTabIndex: shadow.querySelector('.close-button').tabIndex,
    };
  });
  assert.deepEqual(initialVideoChrome, {
    videoCount: 1,
    posterCount: 1,
    controlsVisible: 'false',
    controlsAriaHidden: 'true',
    closeVisible: 'false',
    closeTabIndex: -1,
  });
  await page.mouse.click(195, 422);
  await page.waitForFunction(() => {
    const host = document.querySelector('[data-levixel-web-root]');
    return host?.shadowRoot.querySelector('.video-controls')?.dataset.visible === 'true';
  });
  const revealedVideoChrome = await page.evaluate(() => {
    const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
    return {
      controlsVisible: shadow.querySelector('.video-controls').dataset.visible,
      controlsAriaHidden: shadow.querySelector('.video-controls').getAttribute('aria-hidden'),
      closeVisible: shadow.querySelector('.close-button').dataset.visible,
      closeTabIndex: shadow.querySelector('.close-button').tabIndex,
      playLabel: shadow.querySelector('.control-button').getAttribute('aria-label'),
      timelineLabel: shadow.querySelector('.timeline').getAttribute('aria-label'),
    };
  });
  assert.deepEqual(revealedVideoChrome, {
    controlsVisible: 'true',
    controlsAriaHidden: 'false',
    closeVisible: 'true',
    closeTabIndex: 0,
    playLabel: 'Play video',
    timelineLabel: 'Video position',
  });
  await page.evaluate(() => {
    document.querySelector('[data-levixel-web-root]').shadowRoot.querySelector('.close-button').click();
  });
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  assert.equal(
    await page.evaluate(() => window.levixelFixture.events.filter(event => event.type === 'dismiss').length),
    4,
  );

  await page.evaluate(() => {
    const url = `${location.origin}/tests/delayed.svg?close=${Date.now()}`;
    const item = { id: 'pending-close', type: 'image', url, thumbnailUrl: url };
    window.levixelFixture.pendingCloseOutcome = 'pending';
    void window.levixelFixture.openLevixel({ items: [item] }).then(
      () => { window.levixelFixture.pendingCloseOutcome = 'opened'; },
      error => { window.levixelFixture.pendingCloseOutcome = error.name; },
    );
    void window.levixelFixture.closeLevixel();
  });
  await page.waitForFunction(() => window.levixelFixture.pendingCloseOutcome !== 'pending');
  assert.equal(
    await page.evaluate(() => window.levixelFixture.pendingCloseOutcome),
    'LevixelCancelledError',
  );
  assert.equal(await page.locator('[data-levixel-web-root]').count(), 0);

  await page.evaluate(() => {
    const slowURL = `${location.origin}/tests/delayed.svg?replace=${Date.now()}`;
    const fastURL = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#567"/></svg>')}`;
    const slow = window.levixelFixture.openLevixel({
      items: [{ id: 'slow-open', type: 'image', url: slowURL, thumbnailUrl: slowURL }],
    });
    const fast = window.levixelFixture.openLevixel({
      items: [{ id: 'latest-open', type: 'image', url: fastURL, thumbnailUrl: fastURL }],
    });
    window.levixelFixture.overlapOutcomes = undefined;
    void Promise.allSettled([slow, fast]).then((outcomes) => {
      window.levixelFixture.overlapOutcomes = outcomes.map(outcome => outcome.status === 'fulfilled'
        ? { status: outcome.status, id: outcome.value.index }
        : { status: outcome.status, name: outcome.reason.name });
    });
  });
  await page.waitForFunction(() => window.levixelFixture.overlapOutcomes?.length === 2);
  assert.deepEqual(await page.evaluate(() => window.levixelFixture.overlapOutcomes), [
    { status: 'rejected', name: 'LevixelCancelledError' },
    { status: 'fulfilled', id: 0 },
  ]);
  assert.equal(await page.locator('[data-levixel-web-root]').count(), 1);
  await page.evaluate(() => window.levixelFixture.closeLevixel());
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  assert.equal(
    await page.evaluate(() => window.levixelFixture.events.filter(event => event.type === 'dismiss').length),
    5,
  );

  await page.evaluate(() => {
    const fullURL = `${location.origin}/tests/delayed-full.svg?handoff=${Date.now()}`;
    const previewURL = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#678"/></svg>')}`;
    window.levixelFixture.loadingHandoffOpen = 'pending';
    void window.levixelFixture.openLevixel({
      items: [{
        id: 'loading-handoff',
        type: 'image',
        url: fullURL,
        thumbnailUrl: previewURL,
        width: 2400,
        height: 1600,
      }],
    }).then(
      () => { window.levixelFixture.loadingHandoffOpen = 'opened'; },
      error => { window.levixelFixture.loadingHandoffOpen = error.name; },
    );
  });
  await page.waitForFunction(() => window.levixelFixture.loadingHandoffOpen === 'opened');
  const loadingState = await page.evaluate(() => {
    const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
    return {
      imageCount: shadow.querySelectorAll('.page .image').length,
      spinnerVisible: shadow.querySelector('.spinner').dataset.visible,
    };
  });
  assert.deepEqual(loadingState, { imageCount: 1, spinnerVisible: 'true' });
  await page.mouse.dblclick(195, 422, { delay: 70 });
  await page.waitForTimeout(260);
  const loadingZoom = await page.evaluate(() => {
    const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
    return shadow.querySelector('.image').style.transform;
  });
  assert.equal(loadingZoom.includes('scale(1)'), false);
  await page.waitForFunction(() => {
    const shadow = document.querySelector('[data-levixel-web-root]')?.shadowRoot;
    const image = shadow?.querySelector('.image');
    return image?.src.includes('/tests/delayed-full.svg') && image.complete;
  });
  const completedHandoff = await page.evaluate(() => {
    const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
    const image = shadow.querySelector('.image');
    return {
      imageCount: shadow.querySelectorAll('.page .image').length,
      transform: image.style.transform,
      spinnerVisible: shadow.querySelector('.spinner').dataset.visible,
      naturalSize: { width: image.naturalWidth, height: image.naturalHeight },
    };
  });
  assert.deepEqual(completedHandoff, {
    imageCount: 1,
    transform: loadingZoom,
    spinnerVisible: 'false',
    naturalSize: { width: 2400, height: 1600 },
  });
  await page.evaluate(() => window.levixelFixture.closeLevixel());
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));

  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.evaluate(() => {
    const url = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#789"/></svg>')}`;
    window.levixelFixture.reducedMotionOpen = 'pending';
    void window.levixelFixture.openLevixel({
      items: [{ id: 'reduced-motion', type: 'image', url, thumbnailUrl: url }],
    }).then(
      () => { window.levixelFixture.reducedMotionOpen = 'opened'; },
      error => { window.levixelFixture.reducedMotionOpen = error.name; },
    );
  });
  await page.waitForFunction(() => window.levixelFixture.reducedMotionOpen === 'opened');
  const reducedMotionState = await page.evaluate(() => {
    const host = document.querySelector('[data-levixel-web-root]');
    const image = host.shadowRoot.querySelector('.image');
    return {
      hostState: host.dataset.reducedMotion,
      transitionDuration: getComputedStyle(image).transitionDuration,
    };
  });
  assert.deepEqual(reducedMotionState, { hostState: 'true', transitionDuration: '0s' });
  await page.evaluate(() => window.levixelFixture.closeLevixel());
  await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  await verifyLiveSourceGeometry(browser, `http://127.0.0.1:${address.port}/tests/fixture.html`);
  await verifySingleTouchReopen(browser, `http://127.0.0.1:${address.port}/tests/fixture.html`);
  await verifyAtomicImageHandoff(browser, `http://127.0.0.1:${address.port}/tests/fixture.html`);
  await verifyKeyboardFocusRestore(browser, `http://127.0.0.1:${address.port}/tests/fixture.html`);
  assert.deepEqual(pageErrors, []);
}
finally {
  await page.close();
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}

console.log('Levixel Web browser interaction checks passed.');

async function verifyLiveSourceGeometry(targetBrowser, fixtureURL) {
  const geometryPage = await targetBrowser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  geometryPage.on('pageerror', error => errors.push(error.message));
  try {
    await geometryPage.goto(fixtureURL);
    await geometryPage.waitForFunction(() => window.levixelFixture?.events?.length > 0);

    const liveLayouts = await geometryPage.evaluate(async () => {
      const { resolveElementSourceLayout } = await import('../dist/dom-geometry.js');
      const container = document.createElement('div');
      Object.assign(container.style, {
        position: 'fixed',
        left: '10px',
        top: '20px',
        width: '100px',
        height: '100px',
        overflow: 'hidden',
      });
      const source = document.createElement('div');
      Object.assign(source.style, {
        position: 'absolute',
        left: '60px',
        top: '10px',
        width: '80px',
        height: '80px',
      });
      container.append(source);
      document.body.append(container);
      const clipped = resolveElementSourceLayout(source);
      container.style.visibility = 'hidden';
      const hiddenAncestor = resolveElementSourceLayout(source);
      container.style.visibility = 'visible';
      source.style.width = '0';
      const zeroSized = resolveElementSourceLayout(source);
      container.remove();
      const disconnected = resolveElementSourceLayout(source);
      return { clipped, hiddenAncestor, zeroSized, disconnected };
    });
    assert.deepEqual(liveLayouts.clipped, {
      rect: { left: 70, top: 30, width: 80, height: 80 },
      clippingRect: { left: 70, top: 30, width: 40, height: 80 },
    });
    assert.equal(liveLayouts.hiddenAncestor, null);
    assert.equal(liveLayouts.zeroSized, null);
    assert.equal(liveLayouts.disconnected, null);

    await geometryPage.locator('.source').first().click();
    await geometryPage.waitForFunction(() => window.levixelFixture.results.length === 1);
    const detachedClose = await geometryPage.evaluate(async () => {
      const source = document.querySelector('.source[data-index="0"]');
      const parent = source.parentElement;
      const nextSibling = source.nextSibling;
      source.remove();
      const closing = window.levixelFixture.closeLevixel();
      const host = document.querySelector('[data-levixel-web-root]');
      const usedStaleSnapshot = Boolean(host?.shadowRoot.querySelector('.snapshot'));
      await closing;
      parent.insertBefore(source, nextSibling);
      return usedStaleSnapshot;
    });
    assert.equal(
      detachedClose,
      false,
      'a detached live source must fall back to a simple dismissal instead of its stale hint',
    );
    assert.deepEqual(errors, []);
  }
  finally {
    await geometryPage.close();
  }
}

async function verifySingleTouchReopen(targetBrowser, fixtureURL) {
  const touchPage = await targetBrowser.newPage({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,
    hasTouch: true,
    isMobile: true,
  });
  const errors = [];
  touchPage.on('pageerror', error => errors.push(error.message));
  try {
    await touchPage.goto(fixtureURL);
    await touchPage.waitForFunction(() => window.levixelFixture?.events?.length > 0);

    const firstSource = await centerOf(touchPage, '.source[data-index="0"]');
    await dragTouch(touchPage, firstSource, { x: firstSource.x + 40, y: firstSource.y });
    await touchPage.waitForTimeout(80);
    assert.equal(
      await touchPage.evaluate(() => window.levixelFixture.results.length),
      0,
      'moving beyond the touch activation tolerance must not open a source',
    );

    await tapCenter(touchPage, '.source[data-index="0"]');
    await touchPage.waitForFunction(() => window.levixelFixture.results.length === 1);

    await dragTouch(touchPage, { x: 195, y: 350 }, { x: 195, y: 650 });
    await touchPage.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
    await tapCenter(touchPage, '.source[data-index="1"]');
    await touchPage.waitForFunction(() => window.levixelFixture.results.length === 2);
    await touchPage.waitForTimeout(80);
    assert.equal(
      await touchPage.evaluate(() => window.levixelFixture.results.length),
      2,
      'the compatibility click following direct touch activation must be deduplicated',
    );
    assert.equal(await touchPage.locator('[data-levixel-web-root]').count(), 1);

    for (const [selector, expectedResults] of [
      ['.source[data-index="0"]', 3],
      ['.source[data-index="1"]', 4],
    ]) {
      await dragTouch(touchPage, { x: 195, y: 350 }, { x: 195, y: 650 });
      await touchPage.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
      await tapCenter(touchPage, selector);
      await touchPage.waitForFunction(expected => (
        window.levixelFixture.results.length === expected
      ), expectedResults);
      assert.equal(await touchPage.locator('[data-levixel-web-root]').count(), 1);
    }
    assert.deepEqual(errors, []);
  }
  finally {
    await touchPage.close();
  }
}

async function verifyAtomicImageHandoff(targetBrowser, fixtureURL) {
  const handoffPage = await targetBrowser.newPage({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 3,
    hasTouch: true,
    isMobile: true,
  });
  const errors = [];
  handoffPage.on('pageerror', error => errors.push(error.message));
  try {
    await handoffPage.goto(fixtureURL);
    await handoffPage.waitForFunction(() => window.levixelFixture?.events?.length > 0);
    await handoffPage.evaluate(() => {
      const nativeDecode = HTMLImageElement.prototype.decode;
      const gate = { calls: 0, waiters: [] };
      HTMLImageElement.prototype.decode = function decodeWithLevixelTestGate() {
        const decoded = typeof nativeDecode === 'function'
          ? nativeDecode.call(this)
          : Promise.resolve();
        if (this.dataset.levixelImageLayer !== 'incoming')
          return decoded;
        gate.calls += 1;
        window.levixelFixture.lastIncomingImage = this;
        return Promise.all([
          decoded,
          new Promise(resolve => gate.waiters.push(resolve)),
        ]).then(() => undefined);
      };
      window.levixelFixture.releaseDecode = () => {
        const waiters = gate.waiters.splice(0);
        waiters.forEach(resolve => resolve());
      };
      window.levixelFixture.decodeGateCalls = () => gate.calls;
      const fullURL = `${location.origin}/tests/racing-full.svg?handoff=${Date.now()}`;
      const previewURL = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="240" height="360"><rect width="240" height="360" fill="#345"/></svg>')}`;
      window.levixelFixture.atomicHandoffOpen = 'pending';
      void window.levixelFixture.openLevixel({
        items: [{
          id: 'atomic-handoff',
          type: 'image',
          url: fullURL,
          thumbnailUrl: previewURL,
          width: 1200,
          height: 1800,
        }],
      }).then(
        () => { window.levixelFixture.atomicHandoffOpen = 'opened'; },
        error => { window.levixelFixture.atomicHandoffOpen = error.name; },
      );
    });

    await handoffPage.waitForFunction(() => window.levixelFixture.decodeGateCalls() > 0);
    await handoffPage.waitForFunction(() => window.levixelFixture.atomicHandoffOpen === 'opened');
    const pendingState = await handoffPage.evaluate(() => {
      const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
      const current = shadow.querySelector('[data-levixel-image-layer="current"]');
      const incoming = shadow.querySelector('[data-levixel-image-layer="incoming"]');
      return {
        imageCount: shadow.querySelectorAll('.page .image').length,
        currentIsPreview: current?.src.startsWith('data:image/svg+xml'),
        incomingIsFull: incoming?.src.includes('/tests/racing-full.svg'),
        incomingBehindCurrent: incoming?.nextElementSibling === current,
        currentTransform: current?.style.transform,
        incomingTransform: incoming?.style.transform,
      };
    });
    assert.deepEqual({
      imageCount: pendingState.imageCount,
      currentIsPreview: pendingState.currentIsPreview,
      incomingIsFull: pendingState.incomingIsFull,
      incomingBehindCurrent: pendingState.incomingBehindCurrent,
    }, {
      imageCount: 2,
      currentIsPreview: true,
      incomingIsFull: true,
      incomingBehindCurrent: true,
    }, 'the decoded full image must be prepared behind an uninterrupted fitted preview');
    assert.equal(pendingState.currentTransform.includes('scale(1)'), true);
    assert.equal(pendingState.incomingTransform, pendingState.currentTransform);

    await pinchTouch(
      handoffPage,
      [{ x: 175, y: 422 }, { x: 215, y: 422 }],
      [{ x: 105, y: 422 }, { x: 285, y: 422 }],
    );
    await handoffPage.waitForTimeout(80);
    const pendingZoom = await handoffPage.evaluate(() => {
      const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
      const current = shadow.querySelector('[data-levixel-image-layer="current"]');
      const incoming = shadow.querySelector('[data-levixel-image-layer="incoming"]');
      return {
        current: current?.style.transform,
        incoming: incoming?.style.transform,
      };
    });
    assert.equal(pendingZoom.current.includes('scale(1)'), false);
    assert.equal(
      pendingZoom.incoming,
      pendingZoom.current,
      'pinch state must keep both temporary layers geometrically identical',
    );

    await handoffPage.evaluate(() => window.levixelFixture.releaseDecode());
    await handoffPage.waitForFunction(() => {
      const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
      const images = shadow.querySelectorAll('.page .image');
      return images.length === 1 && images[0].src.includes('/tests/racing-full.svg');
    });
    const committedState = await handoffPage.evaluate(() => {
      const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
      const current = shadow.querySelector('[data-levixel-image-layer="current"]');
      return {
        imageCount: shadow.querySelectorAll('.page .image').length,
        incomingCount: shadow.querySelectorAll('[data-levixel-image-layer="incoming"]').length,
        transform: current?.style.transform,
        naturalSize: { width: current?.naturalWidth, height: current?.naturalHeight },
      };
    });
    assert.deepEqual(committedState, {
      imageCount: 1,
      incomingCount: 0,
      transform: pendingZoom.current,
      naturalSize: { width: 1200, height: 1800 },
    });

    await handoffPage.evaluate(() => window.levixelFixture.closeLevixel());
    await handoffPage.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));

    const previousDecodeCalls = await handoffPage.evaluate(
      () => window.levixelFixture.decodeGateCalls(),
    );
    await handoffPage.evaluate(() => {
      const fullURL = `${location.origin}/tests/racing-full.svg?cancel=${Date.now()}`;
      const previewURL = `data:image/svg+xml,${encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="240" height="360"><rect width="240" height="360" fill="#456"/></svg>')}`;
      window.levixelFixture.cancelHandoffOpen = 'pending';
      void window.levixelFixture.openLevixel({
        items: [{
          id: 'cancel-handoff',
          type: 'image',
          url: fullURL,
          thumbnailUrl: previewURL,
          width: 1200,
          height: 1800,
        }],
      }).then(
        () => { window.levixelFixture.cancelHandoffOpen = 'opened'; },
        error => { window.levixelFixture.cancelHandoffOpen = error.name; },
      );
    });
    await handoffPage.waitForFunction(expected => (
      window.levixelFixture.decodeGateCalls() > expected
    ), previousDecodeCalls);
    await handoffPage.waitForFunction(() => window.levixelFixture.cancelHandoffOpen === 'opened');
    await handoffPage.evaluate(() => window.levixelFixture.closeLevixel());
    await handoffPage.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
    assert.equal(
      await handoffPage.evaluate(() => window.levixelFixture.lastIncomingImage.isConnected),
      false,
      'destroying a viewer must detach an in-flight incoming image layer',
    );
    await handoffPage.evaluate(() => window.levixelFixture.releaseDecode());
    assert.deepEqual(errors, []);
  }
  finally {
    await handoffPage.close();
  }
}

async function verifyKeyboardFocusRestore(targetBrowser, fixtureURL) {
  const keyboardPage = await targetBrowser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  keyboardPage.on('pageerror', error => errors.push(error.message));
  try {
    await keyboardPage.goto(fixtureURL);
    await keyboardPage.waitForFunction(() => window.levixelFixture?.events?.length > 0);
    await keyboardPage.keyboard.press('Tab');
    const initialFocus = await keyboardPage.evaluate(() => ({
      focusVisible: document.activeElement?.matches(':focus-visible') === true,
      index: document.activeElement?.getAttribute('data-index'),
    }));
    assert.deepEqual(initialFocus, { focusVisible: true, index: '0' });

    await keyboardPage.keyboard.press('Enter');
    await keyboardPage.waitForFunction(() => window.levixelFixture.results.length === 1);
    await keyboardPage.keyboard.press('Escape');
    await keyboardPage.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
    assert.equal(
      await keyboardPage.evaluate(() => document.activeElement?.getAttribute('data-index')),
      '0',
      'keyboard dismissal must restore focus to the invoking source',
    );
    assert.deepEqual(errors, []);
  }
  finally {
    await keyboardPage.close();
  }
}

async function tapCenter(targetPage, selector) {
  const point = await centerOf(targetPage, selector);
  await targetPage.touchscreen.tap(point.x, point.y);
}

async function centerOf(targetPage, selector) {
  const source = targetPage.locator(selector);
  await source.scrollIntoViewIfNeeded();
  const box = await source.boundingBox();
  assert.ok(box, `touch target must have geometry: ${selector}`);
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

async function dragTouch(targetPage, from, to) {
  const session = await targetPage.context().newCDPSession(targetPage);
  const touchPoint = (x, y) => ({ x, y, id: 1, radiusX: 1, radiusY: 1, force: 1 });
  try {
    await session.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: [touchPoint(from.x, from.y)],
    });
    for (let step = 1; step <= 8; step += 1) {
      const progress = step / 8;
      await session.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: [touchPoint(
          from.x + (to.x - from.x) * progress,
          from.y + (to.y - from.y) * progress,
        )],
      });
    }
    await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  }
  finally {
    await session.detach();
  }
}

async function pinchTouch(targetPage, from, to) {
  const session = await targetPage.context().newCDPSession(targetPage);
  const touchPoint = (point, id) => ({
    x: point.x,
    y: point.y,
    id,
    radiusX: 1,
    radiusY: 1,
    force: 1,
  });
  try {
    await session.send('Input.dispatchTouchEvent', {
      type: 'touchStart',
      touchPoints: from.map((point, index) => touchPoint(point, index + 1)),
    });
    for (let step = 1; step <= 6; step += 1) {
      const points = from.map((point, index) => ({
        x: point.x + (to[index].x - point.x) * step / 6,
        y: point.y + (to[index].y - point.y) * step / 6,
      }));
      await session.send('Input.dispatchTouchEvent', {
        type: 'touchMove',
        touchPoints: points.map((point, index) => touchPoint(point, index + 1)),
      });
    }
    await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  }
  finally {
    await session.detach();
  }
}

async function inspect(targetPage) {
  return await targetPage.evaluate(() => {
    const host = document.querySelector('[data-levixel-web-root]');
    const shadow = host.shadowRoot;
    const index = window.levixelFixture.results.at(-1).index;
    const current = shadow.querySelectorAll('.page')[index];
    const image = current.querySelector('.image');
    const rect = image.getBoundingClientRect();
    return {
      counterCount: shadow.querySelectorAll('[class*="counter"]').length,
      currentImageCount: current.querySelectorAll('.image').length,
      currentTransform: image.style.transform,
      currentRect: { width: rect.width, height: rect.height },
      sourceVisibility: document.querySelector(`.source[data-index="${index}"]`).style.visibility,
      rootRole: shadow.querySelector('.root').getAttribute('role'),
      bodyOverflow: document.body.style.overflow,
      pageAriaHidden: [...shadow.querySelectorAll('.page')].map(page => page.getAttribute('aria-hidden')),
    };
  });
}
