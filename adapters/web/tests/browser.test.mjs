import assert from 'node:assert/strict';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

import { chromium } from 'playwright-core';

const adapterRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..');
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
  if (pathname === '/tests/delayed.svg' || pathname === '/tests/delayed-full.svg') {
    const isFullImage = pathname.endsWith('delayed-full.svg');
    setTimeout(() => {
      response.writeHead(200, {
        'Content-Type': 'image/svg+xml; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      response.end(isFullImage
        ? '<svg xmlns="http://www.w3.org/2000/svg" width="2400" height="1600"><rect width="2400" height="1600" fill="#678"/></svg>'
        : '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="#345"/></svg>');
    }, isFullImage ? 900 : 250);
    return;
  }
  const relative = pathname === '/' ? 'tests/fixture.html' : pathname.replace(/^\/+/, '');
  const resolved = normalize(join(adapterRoot, relative));
  if (!resolved.startsWith(adapterRoot) || !existsSync(resolved) || !statSync(resolved).isFile()) {
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
  await verifySingleTouchReopen(browser, `http://127.0.0.1:${address.port}/tests/fixture.html`);
  await verifyKeyboardFocusRestore(browser, `http://127.0.0.1:${address.port}/tests/fixture.html`);
  assert.deepEqual(pageErrors, []);
}
finally {
  await page.close();
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}

console.log('Levixel Web browser interaction checks passed.');

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
    assert.deepEqual(errors, []);
  }
  finally {
    await touchPage.close();
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
