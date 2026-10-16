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
  for (const file of ['firebase.production.json', 'firebase.staging.json']) {
    const config = JSON.parse(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'));
    const appRules = config.hosting.headers.filter(rule => rule.source.startsWith('/app'));
    assert.ok(appRules.length > 0, file);
    for (const rule of appRules) {
      const cache = rule.headers.find(header => header.key === 'Cache-Control');
      if (cache) assert.equal(cache.value, 'no-cache', `${file}: ${rule.source}`);
    }
  }
});
