import assert from 'node:assert/strict';

export async function verifySources(browser, fixtureURL) {
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, reducedMotion: 'no-preference' });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  try {
    await page.goto(fixtureURL);
    await page.waitForFunction(() => window.levixelFixture);
    await page.evaluate(async () => {
      const api = await import('/dist/index.js');
      const items = window.levixelFixture.items.slice(0, 2);
      const row = document.createElement('div');
      row.style.cssText = 'position:fixed;left:10px;top:300px;display:flex;gap:10px';
      const bindings = ['cover', 'thumbnail', 'alternate'].map((sourceId, index) => {
        const node = document.createElement('div');
        node.id = `multi-${sourceId}`;
        node.style.cssText = `width:100px;height:${120 - index * 20}px;opacity:${[.8, .6, 1][index]};overflow:hidden`;
        const image = document.createElement('img');
        image.src = items[0].thumbnailUrl;
        image.style.cssText = 'width:100%;height:100%;object-fit:cover';
        node.append(image); row.append(node);
        return { itemId: items[0].id, sourceId, selector: `#${node.id}`, cornerRadius: index * 8 };
      });
      document.body.append(row);
      await Promise.all([...row.querySelectorAll('img')].map(image => image.decode()));
      const result = await api.openLevixelFromSelector({ items, sourceBindings: bindings, initialSourceId: 'thumbnail' });
      window.multiSource = { api, items, bindings, result };
    });
    const visibility = () => page.evaluate(() => ['cover', 'thumbnail', 'alternate'].map(id =>
      document.getElementById(`multi-${id}`)?.style.visibility ?? null));
    assert.deepEqual(await visibility(), ['', 'hidden', '']);
    const styleRefresh = await page.evaluate(async () => {
      const { api, bindings, result } = window.multiSource;
      const selected = document.querySelector('#multi-thumbnail');
      const eventsBefore = window.levixelFixture.events.filter(event => event.type === 'sourceVisibilityChange').length;
      for (let i = 0; i < 3; i++) {
        // A renderer can replace the inline style without replacing its DOM node.
        selected.style.cssText = 'width:100px;height:100px;opacity:.6;overflow:hidden';
        if (i === 0) await api.updateLevixelSources({ galleryId: result.galleryId, sourceBindings: bindings });
        // Later updates exercise the observer without another API call. Reasserting
        // visibility must settle instead of producing an observer feedback loop.
        await new Promise(resolve => requestAnimationFrame(resolve));
        if (getComputedStyle(selected).visibility !== 'hidden') return { hidden: false };
      }
      return { hidden: true, opacity: selected.style.opacity,
        priority: selected.style.getPropertyPriority('visibility'),
        extraEvents: window.levixelFixture.events.filter(event => event.type === 'sourceVisibilityChange').length - eventsBefore };
    });
    assert.deepEqual(styleRefresh, { hidden: true, opacity: '0.6', priority: 'important', extraEvents: 0 });
    assert.deepEqual(await visibility(), ['', 'hidden', '']);
    await page.evaluate(async () => {
      const { api, bindings, result } = window.multiSource;
      document.querySelector('#multi-thumbnail img').replaceWith(document.querySelector('#multi-thumbnail img').cloneNode());
      document.querySelector('#multi-cover').style.borderRadius = '30px';
      await api.updateLevixelSources({ galleryId: result.galleryId, sourceBindings: bindings.toReversed() });
    });
    assert.deepEqual(await visibility(), ['', 'hidden', ''], 'child replacement and sibling updates must retain the selected container');
    await page.keyboard.press('ArrowRight');
    await page.waitForFunction(() => window.levixelFixture.events.some(event => event.type === 'indexChange' && event.payload.index === 1));
    await page.keyboard.press('ArrowLeft');
    await page.waitForFunction(() => document.querySelector('#multi-thumbnail').style.visibility === 'hidden');
    assert.deepEqual(await visibility(), ['', 'hidden', '']);
    await page.evaluate(async () => {
      const { api, bindings, result } = window.multiSource;
      document.querySelector('#multi-thumbnail').remove();
      await api.updateLevixelSources({ galleryId: result.galleryId, sourceBindings: [bindings[2], bindings[0]] });
    });
    assert.deepEqual(await visibility(), ['hidden', null, ''], 'fallback must use original registration order');
    await page.evaluate(async () => {
      const { api, result } = window.multiSource;
      document.querySelector('#multi-cover').remove();
      document.querySelector('#multi-alternate').remove();
      await api.updateLevixelSources({ galleryId: result.galleryId, sourceBindings: [] });
      await api.closeLevixel();
    });
    assert.equal(await page.locator('[data-levixel-web-root]').count(), 0);
    assert.deepEqual(await page.evaluate(async () => {
      const { api, result } = window.multiSource;
      return api.updateLevixelSources({ galleryId: result.galleryId, sourceBindings: [] });
    }), { updated: false });
    const visibilityEvents = await page.evaluate(() => window.levixelFixture.events
      .filter(event => event.type === 'sourceVisibilityChange').map(event => event.payload));
    assert.ok(visibilityEvents.some(event => event.sourceId === 'thumbnail' && event.hidden));
    assert.ok(visibilityEvents.some(event => event.sourceId === 'thumbnail' && !event.hidden));
    assert.ok(visibilityEvents.some(event => event.sourceId === 'cover' && event.hidden));
    const unavailableOpening = await page.evaluate(async () => {
      const { api, items } = window.multiSource;
      const source = document.createElement('div');
      source.id = 'restored-cover';
      source.style.cssText = 'position:fixed;left:20px;top:300px;width:120px;height:100px;opacity:.4;visibility:visible!important';
      const image = document.createElement('img');
      image.src = items[0].thumbnailUrl;
      image.style.cssText = 'width:100%;height:100%;object-fit:cover';
      source.append(image); document.body.append(source);
      await image.decode();
      let finished = false;
      let sawSnapshot = false;
      const opening = api.openLevixelFromSelector({ items,
        initialSourceId: 'missing', sourceBindings: [
          { itemId: items[0].id, sourceId: 'cover', selector: '#restored-cover' },
          { itemId: items[0].id, sourceId: 'missing', selector: '#not-mounted' },
        ],
      }).finally(() => { finished = true; });
      while (!finished) {
        await new Promise(resolve => requestAnimationFrame(resolve));
        sawSnapshot ||= !!document.querySelector('[data-levixel-web-root]')?.shadowRoot.querySelector('.snapshot');
      }
      await opening;
      source.style.cssText = 'position:fixed;left:20px;top:300px;width:120px;height:100px;opacity:.4;visibility:visible!important';
      await new Promise(resolve => requestAnimationFrame(resolve));
      const hidden = getComputedStyle(source).visibility;
      await api.closeLevixel();
      return { sawSnapshot, hidden, opacity: source.style.opacity, visibility: source.style.visibility,
        priority: source.style.getPropertyPriority('visibility') };
    });
    assert.deepEqual(unavailableOpening, { sawSnapshot: false, hidden: 'hidden', opacity: '0.4',
      visibility: 'visible', priority: 'important' });
    const transitionStyleRefresh = await page.evaluate(async () => {
      const { api, items } = window.multiSource;
      const source = document.querySelector('#restored-cover');
      let opened = false;
      const opening = api.openLevixelFromSelector({ items, initialSourceId: 'cover', sourceBindings: [
        { itemId: items[0].id, sourceId: 'cover', selector: '#restored-cover' },
      ] }).then(() => { opened = true; });
      while (!opened && source.style.visibility !== 'hidden') {
        await new Promise(resolve => requestAnimationFrame(resolve));
      }
      const duringOpening = !opened;
      source.style.setProperty('visibility', 'visible', 'important');
      await new Promise(resolve => requestAnimationFrame(resolve));
      const openingHidden = getComputedStyle(source).visibility;
      await opening;
      const closing = api.closeLevixel();
      source.style.removeProperty('visibility');
      await new Promise(resolve => requestAnimationFrame(resolve));
      const closingHidden = getComputedStyle(source).visibility;
      await closing;
      return { duringOpening, openingHidden, closingHidden, restored: source.style.visibility,
        priority: source.style.getPropertyPriority('visibility') };
    });
    assert.deepEqual(transitionStyleRefresh, { duringOpening: true, openingHidden: 'hidden', closingHidden: 'hidden',
      restored: 'visible', priority: 'important' });
    assert.deepEqual(errors, []);
  } finally { await page.close(); }
}
