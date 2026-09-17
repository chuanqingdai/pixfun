const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { sceneState, sceneGeometry } = require('../public/motion.js');
for (let i = 0; i <= 4; i++) assert.equal(sceneState(i / 4).chapter, i);
assert.deepEqual(sceneState(-1), sceneState(0));
assert.deepEqual(sceneState(2), sceneState(1));
const forward = [];
for (let n = 0; n <= 1000; n++) {
  const scene = sceneState(n / 1000);
  for (const key of ['source', 'timeline', 'brief', 'edit', 'caption', 'person', 'finish', 'export']) assert.ok(scene[key] >= 0 && scene[key] <= 1, key);
  assert.ok(!(scene.brief > 0 && scene.edit > 0), 'Brief and script never overlap');
  assert.ok(!(scene.edit > 0 && scene.export > 0), 'Script leaves before export enters');
  assert.ok(scene.person === 0 || scene.person === 1, 'Presenter is never a ghosted blend');
  if (scene.caption > 0) assert.equal(scene.person, 1, 'Spanish caption follows the new presenter');
  for (const key of ['width', 'height', 'x', 'y']) assert.ok(scene[key] > 0 && scene[key] < 1, key);
  forward.push(scene);
}
for (let n = 1000; n >= 0; n--) assert.deepEqual(sceneState(n / 1000), forward[n]);
const root = path.resolve(__dirname, '../public');
assert.equal(sceneState(.5).person, 0, 'Original remains during customization');
assert.equal(sceneState(.75).person, 1, 'Male presenter appears during editing');
assert.equal(sceneState(1).person, 1, 'Male presenter persists through export');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const motionSource = fs.readFileSync(path.join(root, 'motion.js'), 'utf8');
const storyStyles = fs.readFileSync(path.join(root, 'story-layout.css'), 'utf8');
assert.match(html, /VIRAL VIDEO BLUEPRINT/, 'Landing page leads with the creative-blueprint positioning');
assert.match(html, /Decode what works\. Rebuild it as your own\./, 'Hero explains strategy deconstruction and original rebuilding');
assert.match(html, /Does Pixfun copy the original video\?/, 'FAQ clearly distinguishes strategy reuse from copying');
assert.match(html, /id="useCases"/, 'Landing page includes a dedicated use-case section');
assert.match(html, /FITNESS CREATOR/, 'Use cases include presenter-led content');
assert.match(html, /LOCALIZED VERSIONS/, 'Use cases include video localization');
assert.match(html, /PERFORMANCE ADS/, 'Use cases include performance advertising');
assert.match(html, /AI CHARACTER SERIES/, 'Use cases include AI character variations');
for (const asset of ['case-talking-head-v1.png', 'case-localized-v1.png', 'case-performance-ad-v1.png', 'case-ai-character-v1.png']) assert.match(html, new RegExp(asset.replace('.', '\\.')), `Use-case section includes new asset ${asset}`);
assert.ok(html.indexOf('id="useCases"') > html.indexOf('id="story"') && html.indexOf('id="useCases"') < html.indexOf('id="how"'), 'Use cases sit between the blueprint and workflow sections');
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.match(html, /id="originalScene" src="\/assets\/images\/speaker-medium.png"/);
assert.match(html, /id="replacementScene" src="\/assets\/images\/speaker-male-suit.png"/);
assert.equal(ids.length, new Set(ids).size, 'Duplicate IDs');
for (const file of ['index.html', 'pixfun.js', 'motion.js']) {
  const source = fs.readFileSync(path.join(root, file), 'utf8');
  assert.ok(!/[\u3400-\u9fff]/.test(source), `Non-English UI copy in ${file}`);
  if (file.endsWith('.js')) for (const [, id] of source.matchAll(/(?:\$|getElementById)\("([^"]+)"\)/g)) assert.ok(ids.includes(id), `Missing #${id}`);
}
for (const file of ['index.html', 'pixfun.css', 'studio.css', 'studio-flow.css', 'hero.css', 'theme.css', 'typography.css', 'sections.css', 'story-layout.css', 'controls.css']) {
  for (const [, asset] of fs.readFileSync(path.join(root, file), 'utf8').matchAll(/\/assets\/([^'"\s)]+)/g)) assert.ok(fs.existsSync(path.join(root, asset)), `Missing asset ${asset}`);
}
for (const [, id] of html.matchAll(/href="#([^"]+)"/g)) assert.ok(ids.includes(id), `Missing anchor ${id}`);
const filmstrip = html.match(/<div class="filmstrip">([\s\S]*?)<div class="audio-track"/)[1];
const trackImages = [...filmstrip.matchAll(/src="([^"]+)"/g)].map(match => match[1]);
assert.equal(trackImages.length, 4, 'Four timeline shots');
assert.equal(new Set(trackImages).size, 4, 'Each shot needs its own image');
assert.match(filmstrip, /class="is-current" aria-current="true"[\s\S]*?src="\/assets\/images\/speaker-medium\.png"/, 'Scene 02 is the current timeline shot');
assert.match(html, /id="originalScene" src="\/assets\/images\/speaker-medium\.png"/, 'Preview and current timeline shot use the same image');
assert.match(motionSource, /playhead\.style\.left = "25%"/, '00:08 playhead sits at 25% of a 32-second track');
assert.match(motionSource, /min-width: 900px\) and \(min-height: 650px/, 'Pinned story supports common MacBook browser heights');
assert.match(motionSource, /render\(staticChapter \/ 4\)/, 'Static fallback renders one selected chapter');
assert.match(storyStyles, /chapter\.active \{ display: block !important; \}/, 'Static fallback shows only the active chapter');
assert.doesNotMatch(storyStyles, /grid-template-columns:\s*repeat\(2/, 'Static fallback does not stack all chapters above the preview');
assert.match(storyStyles, /motion-enabled \.capability-note \{ display: none; \}/, 'Pinned story removes the long prototype note from the compact stage');
assert.doesNotMatch(html, /id="storyProgress"/, 'Story does not duplicate the chapter rail with a second progress bar');
const hashes = trackImages.map(url => require('node:crypto').createHash('sha256').update(fs.readFileSync(path.join(root, url.replace('/assets/', '')))).digest('hex'));
assert.equal(new Set(hashes).size, 4, 'Timeline images must have different contents');
assert.ok(html.indexOf('<nav class="chapter-nav"') < html.indexOf('<div class="story-copy"'), 'Separate vertical chapter rail');
console.log('PASS: 5 scenes, 1,001 reversible scroll states, English UI, DOM IDs, local assets, and anchors.');
console.log('PASS: Four distinct speaker-scene images and a separate vertical chapter rail.');
for (const [width, height] of [[700,400],[850,450],[1050,550]]) {
  for (let n = 0; n <= 1000; n++) {
    const g = sceneGeometry(n / 1000, width, height);
    assert.ok(g.width > 0 && g.height > 64);
    assert.ok(g.x - g.width / 2 >= 0 && g.x + g.width / 2 <= width, 'Horizontal stage bounds');
    assert.ok(g.y - g.height / 2 >= 0 && g.y + g.height / 2 <= height, 'Vertical stage bounds');
  }
  for (const progress of [.5, .75]) {
    const g = sceneGeometry(progress, width, height);
    assert.ok(Math.abs(g.y - g.height / 2 - g.cardTop) < .001, 'Video and side panel align at the top');
    assert.ok(g.x + g.width / 2 + 24 <= width - g.cardWidth, 'Video clears editing card');
    assert.ok(Math.abs(g.x - g.width / 2) < .001, 'Editing video aligns with the stage left edge');
  }
  const final = sceneGeometry(1, width, height);
  const analyzed = sceneGeometry(.25, width, height);
  assert.ok(analyzed.y + analyzed.height / 2 + 12 <= height - 210, 'Analysis preview clears the timeline');
  assert.ok(Math.abs(final.width / (final.height - 64) - 9 / 16) < .0001, 'Portrait video ratio');
}
console.log('PASS: Top-to-bottom media geometry stays within the stage and clears side cards.');
