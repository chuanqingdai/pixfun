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
// Retain legacy motion geometry; current landing checks follow the travel design.
require('./travel.test.cjs');
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
