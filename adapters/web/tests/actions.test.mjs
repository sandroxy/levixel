import assert from 'node:assert/strict';

export async function verifyActions(browser, fixtureURL) {
  await verifyMediaCallbackClose(browser, fixtureURL);
  await verifyDrawerKeyboardFocus(browser, fixtureURL);
  await verifyExplicitLayouts(browser, fixtureURL);
  await verifyDrawerDismissal(browser, fixtureURL);
  await verifyDrawerMediaStability(browser, fixtureURL);
  await verifyTouchActionScrolling(browser, fixtureURL);
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  try {
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    await page.evaluate(async () => {
      const f = window.levixelFixture;
      f.actionCalls = [];
      const actions = Array.from({ length: 9 }, (_, index) => ({ id: `custom-${index}`, label: `Custom ${index}`,
        group: index < 6 ? 'tools' : 'more', disabled: index === 1, destructive: index === 8,
        icon: f.items[0].thumbnailUrl,
        onPress(context) { f.actionCalls.push({ context, sheet: !!document.querySelector('[data-levixel-web-root]')?.shadowRoot.querySelector('.action-sheet'), viewer: !!document.querySelector('[data-levixel-web-root]') }); },
      }));
      await f.openLevixel({ items: [f.items[0]], actions, actionLayout: 'grid' });
      actions[0].onPress = () => { throw new Error('Live action mutated the open session'); };
      actions[0].label = 'Changed';
    });
    assert.equal(await page.evaluate(() => {
      const shadow = document.querySelector('[data-levixel-web-root]').shadowRoot;
      const target = shadow.elementFromPoint(195, 400);
      return target instanceof HTMLElement && target.closest('.media-shell') !== null && target.tagName !== 'IMG';
    }), true, 'media gestures must hit the gesture surface instead of triggering a browser image menu');
    await page.mouse.move(195, 400);
    await page.mouse.down();
    await page.waitForTimeout(570);
    await page.locator('.action-sheet').waitFor();
    await page.mouse.up();
    await page.waitForTimeout(360);
    assert.equal(await page.locator('.action-button').count(), 9);
    assert.equal(await page.locator('.action-row').count(), 2);
    assert.equal(await page.locator('[data-action-id="custom-1"]').isDisabled(), true);
    assert.equal(await page.locator('[data-action-id="custom-0"] .action-label').innerText(), 'Custom 0');
    assert.equal(await page.locator('.action-row').first().evaluate(row => row.scrollWidth > row.clientWidth), true);
    assert.equal(await page.locator('[data-action-id="custom-0"] .action-icon img').evaluate(image => {
      const rect = image.getBoundingClientRect();
      const target = image.getRootNode().elementFromPoint(rect.x + rect.width / 2, rect.y + rect.height / 2);
      return target?.tagName !== 'IMG' && target?.closest('[data-action-id]')?.dataset.actionId === 'custom-0';
    }), true, 'drawer icon taps must still hit their action without targeting a browser image');
    const menus = await page.evaluate(() => {
      const root = document.querySelector('[data-levixel-web-root]').shadowRoot;
      const prevented = target => {
        const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true, composed: true });
        target.dispatchEvent(event);
        return event.defaultPrevented;
      };
      return {
        media: prevented(root.querySelector('.page .image')),
        drawerIcon: prevented(root.querySelector('.action-icon img')),
        hostImage: prevented(document.querySelector('.source img')),
        longPressCount: window.levixelFixture.events.filter(event => event.type === 'longPress').length,
      };
    });
    assert.deepEqual(menus, { media: true, drawerIcon: true, hostImage: false, longPressCount: 1 },
      'late context menus must be suppressed inside the viewer without reopening the drawer or affecting host images');
    await page.locator('[data-action-id="custom-0"]').click();
    await page.waitForFunction(() => window.levixelFixture.actionCalls.length === 1);
    const call = await page.evaluate(() => window.levixelFixture.actionCalls[0]);
    assert.equal(call.context.itemId, 'portrait');
    assert.equal(call.context.actionId, 'custom-0');
    assert.equal(call.sheet, false, 'drawer must disappear before business callbacks');
    assert.equal(call.viewer, true, 'action selection must retain the viewer');
    await page.keyboard.press('Shift+F10');
    await page.keyboard.press('Enter');
    await page.waitForFunction(() => window.levixelFixture.actionCalls.length === 2);
    assert.equal(await page.evaluate(() => window.levixelFixture.actionCalls.length), 2,
      'keyboard selection must work immediately after opening the drawer');
    await page.mouse.move(195, 400);
    await page.mouse.down();
    await page.waitForTimeout(570);
    await page.mouse.up();
    await page.locator('[data-action-id="custom-0"]').click();
    await page.waitForFunction(() => window.levixelFixture.actionCalls.length === 3);
    assert.equal(await page.evaluate(() => window.levixelFixture.actionCalls.length), 3,
      'a fresh button press must not be swallowed by long-press release suppression');
    await page.keyboard.press('Shift+F10');
    await page.locator('.action-sheet').waitFor();
    await page.keyboard.press('Escape');
    await page.locator('.action-sheet').waitFor({ state: 'detached' });
    assert.equal(await page.locator('.action-sheet').count(), 0);
    assert.equal(await page.locator('[data-levixel-web-root]').count(), 1);
    const before = await page.evaluate(() => window.levixelFixture.events.filter(e => e.type === 'longPress').length);
    await page.mouse.move(195, 400);
    await page.mouse.down();
    await page.mouse.move(210, 400);
    await page.waitForTimeout(560);
    await page.mouse.up();
    assert.equal(await page.evaluate(() => window.levixelFixture.events.filter(e => e.type === 'longPress').length), before);
    await page.evaluate(() => window.levixelFixture.closeLevixel());

    // Long press without actions is an event-only integration and cannot turn into tap-to-close.
    await page.evaluate(() => window.levixelFixture.openLevixel({ items: [window.levixelFixture.items[0]] }));
    const eventCount = await page.evaluate(() => window.levixelFixture.events.filter(e => e.type === 'longPress').length);
    await page.mouse.move(195, 400);
    await page.mouse.down();
    await page.waitForTimeout(570);
    await page.locator('.root').dispatchEvent('contextmenu', { button: 2 });
    await page.waitForTimeout(400);
    await page.mouse.up();
    await page.waitForTimeout(360);
    assert.equal(await page.evaluate(() => window.levixelFixture.events.filter(e => e.type === 'longPress').length), eventCount + 1);
    assert.equal(await page.locator('[data-levixel-web-root]').count(), 1);
    assert.equal(await page.locator('.action-sheet').count(), 0);
    await page.evaluate(() => window.levixelFixture.closeLevixel());

    const touch = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
    try {
      await touch.goto(fixtureURL);
      await touch.waitForFunction(() => window.levixelFixture);
      await touch.evaluate(() => window.levixelFixture.openLevixel({ items: [window.levixelFixture.items[0]], actions: [{ id: 'custom', label: 'Custom' }] }));
      const cdp = await touch.context().newCDPSession(touch);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 155, y: 400 }] });
      await touch.waitForTimeout(200);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 155, y: 400 }, { x: 235, y: 400 }] });
      await touch.waitForTimeout(550);
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      assert.equal(await touch.locator('.action-sheet').count(), 0);
      assert.equal(await touch.evaluate(() => window.levixelFixture.events.filter(e => e.type === 'longPress').length), 0);
      assert.equal(await touch.locator('[data-levixel-web-root]').count(), 1);
    } finally { await touch.close(); }

    let attempts = 0;
    await page.route('**/retry-media.svg', route => {
      attempts++;
      if (attempts === 1) return route.fulfill({ status: 503, body: 'Temporary failure' });
      return route.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400"><rect width="600" height="400" fill="navy"/></svg>' });
    });
    await page.evaluate(() => window.levixelFixture.openLevixel({ items: [{ id: 'retry', type: 'image', url: `${location.origin}/retry-media.svg`, thumbnailUrl: window.levixelFixture.items[0].thumbnailUrl }] }));
    await page.locator('.retry-button').waitFor({ state: 'visible' });
    assert.equal(await page.locator('.retry-button').evaluate(button => {
      const event = new MouseEvent('contextmenu', { bubbles: true, cancelable: true });
      button.dispatchEvent(event);
      return event.defaultPrevented;
    }), true, 'viewer controls must suppress browser menus while remaining clickable');
    assert.equal(await page.evaluate(() => window.levixelFixture.events.some(e => e.type === 'mediaLoad' && e.payload.itemId === 'retry')), false);
    await page.locator('.retry-button').click();
    await page.waitForFunction(() => window.levixelFixture.events.some(e => e.type === 'mediaLoad' && e.payload.itemId === 'retry'));
    assert.equal(attempts, 2);
    assert.equal(await page.locator('.retry-button').isVisible(), false);
    await page.keyboard.press('Escape');
    await page.waitForFunction(() => !document.querySelector('[data-levixel-web-root]'));
  } finally { await page.close(); }
}

async function verifyMediaCallbackClose(browser, fixtureURL) {
  const page = await browser.newPage();
  try {
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    const result = await page.evaluate(async () => {
      const f = window.levixelFixture;
      const { onLevixelEvent } = await import('/dist/index.js');
      await f.openLevixel({ items: [f.items[2]] });
      const video = document.querySelector('[data-levixel-web-root]').shadowRoot.querySelector('video');
      const play = video.play.bind(video);
      let closing;
      let playbackRequestsAfterClose = 0;
      video.play = () => {
        if (closing) playbackRequestsAfterClose++;
        return play();
      };
      const unsubscribe = onLevixelEvent(event => {
        if (event.type === 'mediaLoad') closing = f.closeLevixel();
      });
      try {
        // Deliver first-frame readiness deterministically; the regression is
        // reentry from the public event, independent of video/network timing.
        video.dispatchEvent(new Event('loadeddata'));
        await closing;
        return { playbackRequestsAfterClose, closed: !document.querySelector('[data-levixel-web-root]') };
      } finally { unsubscribe(); }
    });
    assert.deepEqual(result, { playbackRequestsAfterClose: 0, closed: true },
      'closing in mediaLoad must not resume video playback during dismissal');
  } finally { await page.close(); }
}

async function verifyDrawerKeyboardFocus(browser, fixtureURL) {
  const page = await browser.newPage({ viewport: { width: 390, height: 320 } });
  try {
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    for (const layout of ['grid', 'list']) {
      await page.evaluate(actionLayout => {
        const f = window.levixelFixture;
        return f.openLevixel({ items: [f.items[0]], actionLayout,
          actions: Array.from({ length: 12 }, (_, index) => ({
            id: `focus-${index}`, label: `Action ${index}`, disabled: index === 2,
            group: index < 6 ? 'first' : 'second', icon: f.items[0].thumbnailUrl,
          })),
        });
      }, layout);
      await page.waitForFunction(() => window.levixelFixture.events.some(event => event.type === 'mediaLoad'));
      const image = page.locator('.page .image[data-levixel-image-layer="current"]');
      const before = await image.boundingBox();
      await page.keyboard.press('Shift+F10');
      await page.locator('.action-sheet').evaluate(sheet => Promise.all(sheet.getAnimations().map(animation => animation.finished)));
      const enabled = [0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11];
      for (const index of enabled) {
        if (index !== 0) await page.keyboard.press('Tab');
        const visibleFocus = await page.locator(`[data-action-id="focus-${index}"]`).evaluate(button => {
          const rect = button.getBoundingClientRect();
          const content = button.closest('.action-content').getBoundingClientRect();
          const row = button.closest('.action-row').getBoundingClientRect();
          return button.getRootNode().activeElement === button
            && rect.left >= Math.max(content.left, row.left) - .5
            && rect.right <= Math.min(content.right, row.right) + .5
            && rect.top >= content.top - .5 && rect.bottom <= content.bottom + .5;
        });
        assert.equal(visibleFocus, true, `${layout}: keyboard-focused action ${index} must remain inside the scrolling drawer`);
      }
      await page.keyboard.press('Tab');
      assert.equal(await page.locator('.action-cancel').evaluate(button => button.getRootNode().activeElement === button), true);
      await page.keyboard.press('Tab');
      assert.equal(await page.locator('[data-action-id="focus-0"]').evaluate(button => {
        const rect = button.getBoundingClientRect();
        const content = button.closest('.action-content').getBoundingClientRect();
        const row = button.closest('.action-row').getBoundingClientRect();
        return button.getRootNode().activeElement === button
          && rect.left >= Math.max(content.left, row.left) - .5
          && rect.right <= Math.min(content.right, row.right) + .5
          && rect.top >= content.top - .5 && rect.bottom <= content.bottom + .5;
      }), true, 'wrapping the focus must reveal the first action again');
      const after = await image.boundingBox();
      for (const key of ['x', 'y', 'width', 'height']) assert.ok(Math.abs(after[key] - before[key]) < .5,
        `${layout}: keyboard navigation must not move the viewer media`);
      await page.evaluate(() => window.levixelFixture.closeLevixel());
    }
  } finally { await page.close(); }
}

async function verifyTouchActionScrolling(browser, fixtureURL) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
  try {
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    await page.evaluate(() => window.levixelFixture.openLevixel({
      items: [window.levixelFixture.items[0]],
      actionLayout: 'grid',
      actions: Array.from({ length: 8 }, (_, index) => ({ id: `scroll-${index}`, label: `Action ${index}`, icon: window.levixelFixture.items[0].thumbnailUrl })),
    }));
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 195, y: 400 }] });
    await page.waitForTimeout(570);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.locator('.action-sheet').waitFor();
    await page.waitForTimeout(350);
    const row = page.locator('.action-row');
    const bounds = await row.boundingBox();
    assert.ok(bounds);
    const y = bounds.y + 35;
    const initialScroll = await row.evaluate(element => element.scrollLeft);
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 340, y }] });
    for (let step = 1; step <= 10; step++) {
      await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: 340 - step * 27, y }] });
      await page.waitForTimeout(20);
    }
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForFunction(initial => document.querySelector('[data-levixel-web-root]').shadowRoot
      .querySelector('.action-row').scrollLeft > initial + 40, initialScroll);
    await page.keyboard.press('Escape');
    await page.locator('.action-sheet').waitFor({ state: 'detached' });
    assert.equal(await page.locator('.action-sheet').count(), 0);
    assert.equal(await page.locator('[data-levixel-web-root]').count(), 1);
  } finally { await page.close(); }
}

async function verifyDrawerMediaStability(browser, fixtureURL) {
  for (const scenario of [
    { name: 'desktop long press', viewport: { width: 1440, height: 900 }, input: 'mouse' },
    { name: 'desktop keyboard with zoom', viewport: { width: 1440, height: 900 }, input: 'keyboard' },
    { name: 'mobile long press', viewport: { width: 390, height: 844 }, input: 'touch' },
  ]) {
    const page = await browser.newPage({ viewport: scenario.viewport, deviceScaleFactor: 2,
      hasTouch: scenario.input === 'touch', isMobile: scenario.input === 'touch' });
    try {
      await page.goto(fixtureURL);
      await page.waitForFunction(() => window.levixelFixture);
      await page.evaluate(() => window.levixelFixture.openLevixel({
        items: [window.levixelFixture.items[0]],
        actionLayout: 'grid',
        actions: Array.from({ length: 9 }, (_, index) => ({ id: `action-${index}`, label: `Action ${index}`,
          group: index < 6 ? 'tools' : 'more', icon: window.levixelFixture.items[0].thumbnailUrl })),
      }));
      await page.waitForFunction(() => window.levixelFixture.events.some(event => event.type === 'mediaLoad'));
      const x = scenario.viewport.width / 2;
      const y = scenario.viewport.height / 2;
      if (scenario.input === 'keyboard') {
        await page.mouse.dblclick(x, y, { delay: 70 });
        await page.waitForTimeout(300);
      }
      await page.evaluate(() => {
        const host = document.querySelector('[data-levixel-web-root]');
        const root = host.shadowRoot.querySelector('.root');
        const frames = [];
        window.levixelFixture.drawerMotion = frames;
        const sample = () => {
          const rect = root.querySelector('.page .image').getBoundingClientRect();
          const sheet = root.querySelector('.action-sheet');
          frames.push({ x: rect.x, y: rect.y, width: rect.width, height: rect.height,
            scrollX: root.scrollLeft, scrollY: root.scrollTop,
            animating: sheet?.getAnimations().some(animation => animation.playState === 'running') ?? false });
          window.levixelFixture.motionFrame = requestAnimationFrame(sample);
        };
        sample();
      });
      if (scenario.input === 'keyboard') await page.keyboard.press('Shift+F10');
      else if (scenario.input === 'touch') {
        const cdp = await page.context().newCDPSession(page);
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
        await page.waitForTimeout(570);
        await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
      } else {
        await page.mouse.move(x, y);
        await page.mouse.down();
        await page.waitForTimeout(570);
        await page.mouse.up();
      }
      await page.locator('.action-sheet').waitFor();
      await page.waitForTimeout(250);
      const frames = await page.evaluate(() => {
        cancelAnimationFrame(window.levixelFixture.motionFrame);
        return window.levixelFixture.drawerMotion;
      });
      assert.ok(frames.some(frame => frame.animating), `${scenario.name}: sample the drawer during its animation`);
      const baseline = frames[0];
      const displacement = Math.max(...frames.flatMap(frame =>
        ['x', 'y', 'width', 'height', 'scrollX', 'scrollY'].map(key => Math.abs(frame[key] - baseline[key]))));
      assert.ok(displacement < 0.5, `${scenario.name}: opening the drawer moved the image/viewer by ${displacement}px`);
      if (scenario.input === 'keyboard') {
        assert.equal(await page.locator('.action-button').first().evaluate(button =>
          button.getRootNode().activeElement === button && button.matches(':focus-visible')), true,
          'keyboard opening must still visibly focus the first action');
      } else {
        assert.equal(await page.locator('.action-sheet').evaluate(sheet =>
          sheet.getRootNode().activeElement === sheet && getComputedStyle(sheet).outlineStyle === 'none'), true,
          `${scenario.name}: focus must enter the dialog without highlighting an action`);
        await page.keyboard.press('Shift+Tab');
        assert.equal(await page.locator('.action-cancel').evaluate(button =>
          button.getRootNode().activeElement === button && button.matches(':focus-visible')), true,
          'backward keyboard navigation from the dialog must visibly focus Cancel');
        await page.keyboard.press('Tab');
        assert.equal(await page.locator('.action-button').first().evaluate(button =>
          button.getRootNode().activeElement === button && button.matches(':focus-visible')), true,
          'keyboard navigation after pointing input must visibly focus the first action');
      }
      await page.keyboard.press('Escape');
      await page.locator('.action-sheet').waitFor({ state: 'detached' });
      assert.equal(await page.locator('.action-sheet').count(), 0);
      assert.equal(await page.locator('[data-levixel-web-root]').count(), 1);
      assert.equal(await page.locator('.root').evaluate(root => root.getRootNode().activeElement === root), true,
        'dismissing the drawer must restore focus to the viewer');
    } finally { await page.close(); }
  }
}

async function verifyExplicitLayouts(browser, fixtureURL) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  let iconRequests = 0;
  try {
    await page.route('**/optional-action-icon.svg', route => {
      iconRequests++;
      return route.fulfill({ contentType: 'image/svg+xml', body: '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><circle cx="12" cy="12" r="10"/></svg>' });
    });
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    for (const scenario of [
      { count: 10 },
      { count: 3, layout: 'list', icons: true },
      { count: 1, layout: 'grid' },
    ]) {
      await page.evaluate(scenario => {
        const f = window.levixelFixture;
        return f.openLevixel({ items: [f.items[0]], actionLayout: scenario.layout, actionListIcons: scenario.icons,
          actions: Array.from({ length: scenario.count }, (_, index) => ({ id: `explicit-${index}`, label: `Action ${index}`,
            icon: scenario.icons && index === 2 ? undefined : `${location.origin}/optional-action-icon.svg` })) });
      }, scenario);
      await page.keyboard.press('Shift+F10');
      await page.locator('.action-sheet').waitFor();
      await page.waitForTimeout(350);
      const sheet = page.locator('.action-sheet');
      assert.equal(await sheet.getAttribute('data-layout'), scenario.layout ?? 'list');
      assert.equal(await page.locator('.action-button').count(), scenario.count);
      const button = await page.locator('.action-button').first().boundingBox();
      if (!scenario.layout) {
        assert.equal(await page.locator('.action-icon').count(), 0);
        assert.equal(iconRequests, 0, 'Default list must not fetch provided icons');
        assert.ok(button.width > 300, 'Ten actions must still use full list rows');
        assert.equal(await page.locator('.action-content').evaluate(content => content.scrollHeight > content.clientHeight), true);
        const cancel = await page.locator('.action-cancel').boundingBox();
        assert.ok(cancel.y + cancel.height <= 844, 'Cancel must stay visible outside the scrolling list');
        await page.locator('.action-content').evaluate(content => { content.scrollTop = content.scrollHeight; });
        assert.equal(await page.locator('.action-cancel').isVisible(), true);
      } else if (scenario.icons) {
        assert.equal(await page.locator('.action-icon img').count(), 2);
        assert.equal(await page.locator('[data-action-id="explicit-2"] .action-icon').innerText(), '');
      } else {
        assert.ok(button.width < 100, 'A single grid action must retain its tile width');
        assert.equal(await page.locator('.action-icon img').count(), 1);
      }
      await page.locator('.action-cancel').click();
      await page.evaluate(() => window.levixelFixture.closeLevixel());
    }
  } finally { await page.close(); }
}

async function verifyDrawerDismissal(browser, fixtureURL) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    const open = () => page.evaluate(() => {
      const f = window.levixelFixture;
      f.actionCalls = [];
      return f.openLevixel({ items: [f.items[0]], actions: [
        { id: 'inspect', label: 'Inspect', onPress: context => f.actionCalls.push(context) },
      ] });
    });
    await open();
    await page.keyboard.press('Shift+F10');
    await page.locator('.action-sheet').evaluate(sheet => Promise.all(sheet.getAnimations().map(animation => animation.finished)));
    const immediate = await page.locator('[data-action-id="inspect"]').evaluate(button => {
      button.click();
      button.click();
      const root = button.getRootNode();
      return {
        callbacks: window.levixelFixture.actionCalls.length,
        sheetConnected: button.isConnected,
        mediaInert: root.querySelector('.content').inert,
      };
    });
    assert.deepEqual(immediate, { callbacks: 0, sheetConnected: true, mediaInert: true },
      'selection must keep the viewer blocked until the drawer finishes dismissing');
    await page.waitForFunction(() => window.levixelFixture.actionCalls.length === 1);
    assert.equal(await page.locator('.action-sheet').count(), 0);
    assert.equal(await page.locator('.content').evaluate(content => content.inert), false);

    // Replacing a session during the exit must not dispatch its pending action.
    await open();
    await page.keyboard.press('Shift+F10');
    await page.locator('[data-action-id="inspect"]').evaluate(button => {
      button.click();
      const f = window.levixelFixture;
      return f.openLevixel({ items: [f.items[1]] });
    });
    assert.equal(await page.evaluate(() => window.levixelFixture.actionCalls.length), 0);
    assert.equal(await page.locator('[data-levixel-web-root]').count(), 1);
    assert.equal(await page.locator('.action-sheet').count(), 0);

    // Every close caller must wait for the same complete viewer dismissal.
    await open();
    await page.keyboard.press('Shift+F10');
    const resolvedWithViewer = await page.evaluate(() => {
      const f = window.levixelFixture;
      return Promise.all([f.closeLevixel(), f.closeLevixel()].map(closing =>
        closing.then(() => Boolean(document.querySelector('[data-levixel-web-root]')))));
    });
    assert.deepEqual(resolvedWithViewer, [false, false]);
    assert.deepEqual(errors, [], 'interrupted entry/exit animations must not leak rejected promises');

    await page.emulateMedia({ reducedMotion: 'reduce' });
    await open();
    await page.keyboard.press('Shift+F10');
    assert.equal(await page.locator('.action-overlay').evaluate(overlay => overlay.getAnimations({ subtree: true }).length), 0);
    await page.locator('[data-action-id="inspect"]').click();
    await page.waitForFunction(() => window.levixelFixture.actionCalls.length === 1);
    assert.equal(await page.locator('.action-sheet').count(), 0);
    await page.evaluate(() => window.levixelFixture.closeLevixel());
  } finally { await page.close(); }
}
