// Checks the public site's pages without serving them.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const site = path.join(__dirname, '../site');
const pages = fs.readdirSync(site).filter(name => name.endsWith('.html'));
const read = name => fs.readFileSync(path.join(site, name), 'utf8');

test('every page has the basics assistive technology relies on', () => {
  assert.ok(pages.length >= 7, pages.join());
  for (const name of pages) {
    const html = read(name);
    assert.match(html, /<html lang="en">/, name);
    assert.match(html, /<title>[^<]+<\/title>/, name);
    assert.match(html, /class="skip-link" href="#main"/, name);
    assert.match(html, /<main id="main"/, name);
    assert.match(html, /name="viewport" content="width=device-width, initial-scale=1"/, `${name} allows zooming`);
    for (const image of html.match(/<img [^>]*>/g) ?? []) assert.match(image, / alt="/, `${name}: ${image}`);
  }
});

test('no forms, no Google Fonts, and scripts only from the site itself', () => {
  for (const name of pages) {
    const html = read(name);
    assert.doesNotMatch(html, /<form/i, name);
    assert.doesNotMatch(html, /fonts\.(googleapis|gstatic)\.com/, name);
    for (const script of html.match(/<script [^>]*src="[^"]+"/g) ?? []) {
      assert.match(script, /src="\/[^/]/, `${name}: ${script}`);
    }
  }
});

test('the footer keeps legal and help links; account deletion lives in the account menu', () => {
  const footer = read('index.html').split('<footer')[1];
  for (const href of ['/privacy', '/terms', '/cookies', '/accessibility', '/support']) {
    assert.ok(footer.includes(`href="${href}"`), href);
  }
  assert.ok(!footer.includes('delete-account'));
  assert.ok(pages.includes('delete-account.html'), 'the deletion help page still exists for the stores');
});

test('the site policy blocks framing and inline scripts', () => {
  const config = JSON.parse(fs.readFileSync(path.join(__dirname, '../firebase.production.json'), 'utf8'));
  const policies = config.hosting.headers.filter(rule => rule.source === '/' || rule.source.startsWith('/@(privacy'))
    .map(rule => rule.headers.find(header => header.key === 'Content-Security-Policy').value);
  assert.equal(policies.length, 2);
  for (const policy of policies) {
    assert.match(policy, /frame-ancestors 'none'/);
    assert.match(policy, /script-src 'self' https:\/\/www\.gstatic\.com;/);
    assert.doesNotMatch(policy, /unsafe-eval/);
    // Fonts come from the site itself, never Google Fonts.
    assert.match(policy, /font-src 'self';/);
    assert.doesNotMatch(policy, /fonts\.(googleapis|gstatic)\.com/);
  }
});

test("the web app's files revalidate, so a new release never mixes with cached ones", () => {
  // Flutter keeps the same names across releases (the icon font is trimmed to
  // the icons in use), so a cached copy can be missing a new release's glyphs.
  // Browsers check every visit; the CDN may keep a copy because each deploy
  // clears it. Only folders named after a version may be kept for good.
  const revalidate = 'public, max-age=0, must-revalidate, s-maxage=31536000';
  const versioned = ['/app/canvaskit-*/**', '/app/fonts/**'];
  for (const file of ['firebase.production.json', 'firebase.staging.json']) {
    const config = JSON.parse(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'));
    const appRules = config.hosting.headers.filter(rule => rule.source.startsWith('/app'));
    assert.ok(appRules.length > 0, file);
    for (const rule of appRules) {
      const cache = rule.headers.find(header => header.key === 'Cache-Control');
      if (!cache) continue;
      const expected = versioned.includes(rule.source) ? 'public, max-age=31536000, immutable' : revalidate;
      assert.equal(cache.value, expected, `${file}: ${rule.source}`);
    }
    const shared = config.hosting.headers.find(rule => rule.source === '**/*.@(html|json|css|js)');
    assert.equal(shared.headers.find(header => header.key === 'Cache-Control').value, revalidate, file);
  }
});

test('the hosting build names the engine folder after its version', () => {
  const script = fs.readFileSync(path.join(__dirname, '../scripts/build-hosting.mjs'), 'utf8');
  assert.match(script, /`canvaskit-\$\{revision\}`/);
  assert.match(script, /canvasKitBaseUrl: "\$\{engineFolder\}\/"/);
});

test('the hero friends are three different people on every load', () => {
  const html = read('index.html');
  assert.match(html, /data-wdyw-scene="duo"/);
  assert.match(html, /data-wdyw-scene="solo"/);
  assert.match(html, /<script src="\/avatars.js" defer><\/script>/);

  const avatars = require('../site/avatars.js');
  const fakeElement = scene => ({ scene, getAttribute: name => (name === 'data-wdyw-scene' ? scene : null) });
  // mountAll only runs where a document exists.
  global.document = {};
  try {
    const seen = new Set();
    for (let seed = 1; seed <= 200; seed++) {
      const els = [fakeElement('duo'), fakeElement('solo')];
      avatars.mountAll({ querySelectorAll: () => els }, { seed });
      const [duo, solo] = els.map(el => /aria-label="([^"]+)"/.exec(el.innerHTML)[1]);
      const [, a, b] = /^(\w+) and (\w+) /.exec(duo);
      const [, c] = /^(\w+) /.exec(solo);
      assert.equal(new Set([a, b, c]).size, 3, `seed ${seed}: ${duo} / ${solo}`);
      seen.add(`${a}+${b}`);
    }
    assert.ok(seen.size > 40, `only ${seen.size} different pairs`);
  } finally {
    delete global.document;
  }
});

test("the hero phone's screens exist and each has a matching dot", () => {
  const html = read('index.html');
  const shots = [...html.matchAll(/<img class="shot[^"]*" src="\/media\/demo\/([a-z-]+)\.png"[^>]* data-shot="([a-z-]+)"/g)];
  assert.deepEqual(shots.map(([, file]) => file), ['home', 'lobby', 'swipe', 'results']);
  for (const [, file, shot] of shots) {
    assert.equal(file, shot);
    assert.ok(fs.existsSync(path.join(site, 'media/demo', `${file}.png`)), file);
    assert.match(html, new RegExp(`<button type="button" data-shot="${shot}" aria-pressed="(true|false)" aria-label="[A-Z][a-z]+"></button>`), shot);
  }
  assert.match(html, /class="demo-pause"/);
});

test('the site notice is checked, shows only between its dates, and links within the site', async () => {
  const { parseNotice, noticeShowsOn, addNotice } = await import('../scripts/site-notice.mjs');
  const notice = parseNotice(JSON.parse(fs.readFileSync(path.join(site, 'notice.json'), 'utf8')));
  if (notice?.link) {
    const [page, anchor] = notice.link.href.slice(1).split('#');
    const html = read(`${page || 'index'}.html`);
    if (anchor) assert.ok(html.includes(`id="${anchor}"`), `${notice.link.href} points at a real section`);
  }
  assert.equal(parseNotice({ notice: null }), null);
  const sample = parseNotice({ notice: { message: 'Terms <changing> soon.', showFrom: '2026-12-01', showUntil: '2026-12-31',
    link: { text: 'Read them', href: '/terms#changes' } } });
  assert.equal(noticeShowsOn(sample, '2026-11-30'), false);
  assert.equal(noticeShowsOn(sample, '2026-12-01'), true);
  assert.equal(noticeShowsOn(sample, '2026-12-31'), true);
  assert.equal(noticeShowsOn(sample, '2027-01-01'), false);
  const page = addNotice(read('terms.html'), sample);
  const header = page.indexOf('</header>');
  const added = page.indexOf('<aside class="site-notice"');
  assert.ok(header > 0 && added > header && added < page.indexOf('<main'), 'between the top bar and the content');
  assert.ok(page.includes('Terms &lt;changing&gt; soon. <a href="/terms#changes">Read them</a>'), 'text is escaped');
  const bad = fields => () => parseNotice({ notice: { message: 'Hi', showFrom: '2026-12-01', showUntil: '2026-12-31', ...fields } });
  assert.throws(bad({ link: { text: 'Elsewhere', href: 'https://example.com' } }), /link/);
  assert.throws(bad({ link: { text: 'Elsewhere', href: '//example.com' } }), /link/);
  assert.throws(bad({ link: { text: 'Script', href: '/x" onclick="y' } }), /link/);
  assert.throws(bad({ showUntil: '2026-11-01' }), /dates/);
  assert.throws(bad({ message: 'x'.repeat(241) }), /message/);
  assert.throws(() => parseNotice({}), /notice/);
});
