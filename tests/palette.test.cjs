const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../public');
const css = fs.readFileSync(path.join(root, 'palette.css'), 'utf8');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const tokens = Object.fromEntries([...css.matchAll(/--([\w-]+):\s*(#[\da-f]{6});/gi)].map(([, name, value]) => [name, value]));
function luminance(hex) {
  const channels = hex.slice(1).match(/../g).map(c => parseInt(c, 16) / 255).map(c => c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) ** 2.4);
  return channels[0] * .2126 + channels[1] * .7152 + channels[2] * .0722;
}
function contrast(a, b) {
  const values = [luminance(tokens[a]), luminance(tokens[b])].sort((a, b) => b - a);
  return (values[0] + .05) / (values[1] + .05);
}
for (const background of ['canvas', 'surface', 'raised', 'input-surface', 'brand-soft']) {
  for (const text of ['ink', 'muted', 'subtle']) {
    assert.ok(contrast(text, background) >= 4.5, `${text} on ${background} meets 4.5:1`);
  }
}
for (const status of ['success', 'warning', 'danger', 'info']) assert.ok(contrast(status, 'surface') >= 4.5);
for (const fill of ['accent', 'brand-hover', 'brand-active']) assert.ok(contrast('on-accent', fill) >= 4.5);
assert.ok(contrast('focus-ring', 'input-surface') >= 3);
assert.ok(contrast('control-border', 'input-surface') >= 3, 'Input boundary meets 3:1');
assert.ok(html.indexOf('/assets/palette.css') > html.indexOf('/assets/polish.css'), 'Semantic palette loads last');
assert.match(css, /\.status\.error \{ color: var\(--danger\)/);
assert.match(css, /\.workspace \.preview-screen video \{ background: var\(--preview-surface\)/);
console.log('PASS: Shared palette, text/control contrast, semantic status colors, and neutral preview surround.');
