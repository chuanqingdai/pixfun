const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../public');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const footer = name => read(name).match(/<footer class="footer site-footer wrap"[\s\S]*?<\/footer>/)?.[0];
test('public child pages retain the homepage footer, including working home anchors', () => {
  const home = footer('index.html').replace('href="#"', 'href="/"')
    .replace('href="#how"', 'href="/#how"').replace('href="#faq"', 'href="/#faq"')
    .replace(/<small id="engineText"[^>]*>[\s\S]*?<\/small>\s*/, '');
  for (const page of ['footage-case.html', 'mac-early-access.html']) {
    assert.equal(footer(page), home);
    assert.equal((read(page).match(/<footer\b/g) || []).length, 1);
    assert.match(read(page), /\/assets\/site-footer\.css\?v=1/);
    assert.doesNotMatch(footer(page), /href="#/);
  }
  assert.match(read('index.html'), /\/assets\/site-footer\.css\?v=1/);
  assert.match(read('site-footer.css'), /@media\(max-width:700px\)/);
});
