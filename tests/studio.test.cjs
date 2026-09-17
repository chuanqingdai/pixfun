/* DOM-independent controller regression checks. Not a browser/visual test. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
class Element {
  constructor(id = '', tag = 'div') {
    this.id = id; this.tagName = tag; this.children = []; this.handlers = {}; this.attrs = {}; this.dataset = {}; this.style = {}; this.value = ''; this.files = []; this.hidden = false; this.disabled = false; this.textContent = '';
    const classes = new Set();
    this.classList = { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c), toggle: (c, value) => { const on = value === undefined ? !classes.has(c) : value; if (on) classes.add(c); else classes.delete(c); return on; } };
  }
  addEventListener(name, handler) { (this.handlers[name] ||= []).push(handler); }
  async emit(name, payload = {}) { for (const handler of this.handlers[name] || []) await handler({ preventDefault() {}, target: this, ...payload }); }
  setAttribute(name, value) { this.attrs[name] = String(value); }
  removeAttribute(name) { delete this.attrs[name]; }
  append(...children) { children.forEach(child => { if (child.parentElement) child.parentElement.children = child.parentElement.children.filter(item => item !== child); child.parentElement = this; this.children.push(child); }); }
  replaceChildren(...children) { this.children = children; }
  querySelectorAll(selector) { return selector === 'button' ? this.children.filter(child => child.tagName === 'button') : []; }
  pause() { this.paused = true; }
  load() {}
  focus() { this.focused = true; }
  scrollIntoView() {}
  reset() {}
}
const html = fs.readFileSync(path.resolve(__dirname, '../public/index.html'), 'utf8');
assert.match(html, /id="textForm"[^>]*novalidate/, 'Use the English inline validation instead of OS-language bubbles');
assert.doesNotMatch(html, /id="chooseReferences"|id="languageBrief"|<summary>More options<\/summary>/, 'Direction composer only shows the request and action');
assert.match(html, /id="timelineRuler"/, 'Review includes a timeline ruler');
assert.match(html, /id="workspacePlayhead"/, 'Review includes a synchronized playhead');
assert.match(html, /id="timelineEditor"/, 'Timeline can follow the playhead in a narrow viewport');
assert.match(html, /id="splitBtn"/, 'Review can render detected segments as separate MP4 clips');
assert.match(html, /class="quick-direction studio-brief-form" id="briefForm"/, 'Review includes the merged direction composer');
assert.equal((html.match(/data-studio-step=/g) || []).length, 3, 'Studio has three progressive steps');
const elements = Object.fromEntries([...html.matchAll(/\bid="([^"]+)"/g)].map(([, id]) => [id, new Element(id)]));
const steps = [1, 2, 3].map(n => { const e = new Element(); e.dataset.studioStep = String(n); return e; });
const panels = [1, 2, 3].map(n => { const e = new Element(); e.dataset.studioPanel = String(n); return e; });
const brand = new Element(), skip = new Element(), body = new Element();
const eventHandlers = {};
const document = {
  body, getElementById: id => elements[id] || null, createElement: tag => new Element('', tag), createTextNode: text => ({ textContent: text }),
  querySelector: selector => selector === '.skip' ? skip : selector === '.header .brand' ? brand : null,
  querySelectorAll: selector => selector === '[data-studio-step]' ? steps : selector === '[data-studio-panel]' ? panels : selector.startsWith('[data-studio-step],') ? [...steps, ...Object.values(elements)] : [],
  dispatchEvent() {},
};
let failBrief = false, failRender = false, failSplit = false;
const calls = [];
const context = vm.createContext({ document, console, URL, FormData, Event, location: { hash: '' }, matchMedia: () => ({ matches: false }),
  history: { pushState(_state, _title, hash) { context.location.hash = hash; } },
  window: { scrollTo() {}, confirm: () => true, addEventListener(name, fn) { eventHandlers[name] = fn; } },
  fetch: async (url, options) => {
    calls.push({ url, options });
    let data = { ok: true };
    if (url === '/api/health') data.tools = { ffmpeg: true, ffprobe: true, 'yt-dlp': true };
    if (url === '/api/brief') data = failBrief ? { ok: false, error: 'Brief test failure' } : { ok: true, references: [] };
    if (url === '/api/split') data = failSplit ? { ok: false, error: 'Split test failure' } : { ok: true, clips: [
      { label: 'Scene 01', start: 0, end: 6, duration: 6, filename: 'clip-01.mp4', url: '/media/output/test/clip-01.mp4' },
      { label: 'Scene 02', start: 6, end: 12, duration: 6, filename: 'clip-02.mp4', url: '/media/output/test/clip-02.mp4' },
    ] };
    if (url === '/api/render') data = failRender ? { ok: false, error: 'Render test failure' } : { ok: true, outputUrl: '/media/output/test/result.mp4' };
    return { ok: data.ok, json: async () => data };
  },
});
vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../public/pixfun.js'), 'utf8'), context);
const run = code => vm.runInContext(code, context);
(async () => {
  run(`showAnalysis({jobId:'012345abcdef', sourceUrl:'/media/upload/test/source.mp4', analysis:{sourceName:'sample.mp4', metadata:{duration:12,width:1920,height:1080}, cutCount:1, segments:[{start:0,end:6,duration:6},{start:6,end:12,duration:6}]}})`);
  assert.ok(body.classList.contains('studio-mode'));
  assert.equal(context.location.hash, '#studio');
  assert.deepEqual(panels.map(p => p.hidden), [false, true, true]);
  assert.deepEqual(steps.map(p => p.disabled), [false, true, true]);
  assert.equal(elements.previewSwitch.hidden, true);
  assert.equal(elements.previewCard.parentElement, elements.reviewPreviewSlot);
  assert.equal(elements.resultPreview.disabled, true);
  assert.equal(elements.timeline.children.length, 2);
  assert.equal(elements.timeline.children[0].children[0].children[0].tagName, 'img', 'Each timeline clip has a video thumbnail image');
  assert.equal(elements.splitBtn.textContent, 'Create 2 clips');
  failSplit = true; await elements.splitBtn.emit('click'); assert.equal(elements.splitStatus.textContent, 'Split test failure');
  failSplit = false; await elements.splitBtn.emit('click');
  assert.equal(elements.clipOutputs.hidden, false); assert.equal(elements.clipOutputList.children.length, 2);
  assert.equal(elements.clipOutputList.children[0].children[1].href, '/media/output/test/clip-01.mp4');
  await steps[2].emit('click'); assert.equal(run('state.step'), 1, 'Future step cannot be opened');
  elements.extraBrief.value = 'Use a confident presenter and Spanish narration';
  await elements.briefForm.emit('input');
  failBrief = true;
  await elements.briefForm.emit('submit');
  assert.equal(run('state.step'), 1); assert.equal(elements.briefStatus.textContent, 'Brief test failure');
  assert.equal(elements.extraBrief.value, 'Use a confident presenter and Spanish narration');
  assert.equal(elements.saveBrief.disabled, false);
  failBrief = false;
  await elements.briefForm.emit('submit');
  assert.equal(run('state.step'), 2); assert.equal(run('state.briefSaved'), true);
  assert.deepEqual(panels.map(p => p.hidden), [true, false, true]);
  assert.deepEqual(steps.map(p => p.disabled), [false, false, true]);
  assert.equal(elements.briefSummary.hidden, false);
  await elements.textForm.emit('submit');
  assert.equal(run('state.step'), 2, 'Empty text cannot advance');
  assert.equal(elements.hookInput.attrs['aria-invalid'], 'true');
  assert.equal(steps[2].disabled, true);
  for (const id of ['hookInput', 'subjectInput', 'ctaInput']) elements[id].value = 'My text';
  await elements.textForm.emit('input');
  await elements.textForm.emit('submit');
  assert.equal(run('state.step'), 3);
  assert.deepEqual(panels.map(p => p.hidden), [true, true, false]);
  assert.equal(elements.summaryHook.textContent, 'My text');
  assert.equal(elements.previewSwitch.hidden, true, 'Result selector is absent before generation');
  assert.equal(elements.previewCard.parentElement, elements.resultPreviewSlot);
  assert.equal(elements.renderForm.hidden, false);
  assert.equal(elements.outputBox.hidden, true);
  await elements.renderForm.emit('submit');
  assert.equal(elements.outputBox.hidden, false); assert.equal(elements.sourceVideo.hidden, true); assert.equal(elements.outputVideo.hidden, false);
  assert.equal(elements.downloadLink.href, '/media/output/test/result.mp4');
  assert.equal(elements.previewSwitch.hidden, false);
  assert.equal(elements.renderForm.hidden, true, 'Successful export has one primary download action');
  await elements.originalPreview.emit('click'); assert.equal(elements.sourceVideo.hidden, false);
  await elements.resultPreview.emit('click'); assert.equal(elements.outputVideo.hidden, false);
  await steps[0].emit('click');
  assert.equal(elements.previewSwitch.hidden, true);
  assert.equal(elements.previewCard.parentElement, elements.reviewPreviewSlot);
  await elements.timeline.children[1].emit('click'); assert.equal(elements.sourceVideo.currentTime, 6); assert.equal(elements.sourceVideo.hidden, false); assert.equal(elements.timeline.children[1].attrs['aria-pressed'], 'true');
  assert.equal(elements.timelineNow.textContent, 'Now · 0:06');
  assert.equal(elements.sourceVideo.handlers.play.length, 1, 'Playback starts the smooth playhead loop');
  await steps[1].emit('click');
  elements.hookInput.value = 'Updated text';
  await elements.textForm.emit('input');
  await elements.textForm.emit('submit');
  assert.equal(elements.outputTitle.textContent, 'Previous version');
  assert.equal(elements.downloadLink.textContent, 'Download previous version');
  assert.equal(elements.renderForm.hidden, false);
  failRender = true;
  await elements.renderForm.emit('submit');
  assert.equal(elements.outputBox.hidden, false, 'Preserve previous result on failure');
  assert.equal(elements.renderBtn.disabled, false); assert.equal(elements.hookInput.value, 'Updated text');
  assert.equal(run('state.step'), 3);
  failRender = false;
  await elements.renderForm.emit('submit');
  assert.equal(elements.renderForm.hidden, true);
  assert.equal(elements.downloadLink.textContent, 'Download MP4');
  assert.equal(run('state.textDirty'), false);
  await elements.backHome.emit('click'); assert.equal(body.classList.contains('studio-mode'), false);
  await elements.resumeStudio.emit('click'); assert.equal(body.classList.contains('studio-mode'), true); assert.equal(elements.hookInput.value, 'Updated text');
  await elements.exportBack.emit('click');
  elements.hookInput.value = ' ';
  await elements.textForm.emit('input');
  await steps[2].emit('click');
  assert.equal(run('state.step'), 2, 'Revisiting export still validates edited text');
  await elements.editBack.emit('click');
  elements.extraBrief.value = 'Unsaved direction';
  await elements.briefForm.emit('input');
  await steps[1].emit('click');
  assert.match(elements.briefSummary.textContent, /unsaved/i);
  let warned = false; eventHandlers.beforeunload({ preventDefault() { warned = true; } }); assert.equal(warned, true);
  run(`showAnalysis({jobId:'fedcba654321', sourceUrl:'/media/upload/new.mp4', analysis:{sourceName:'new.mp4', metadata:{duration:10}, segments:[]}})`);
  assert.deepEqual(steps.map(p => p.disabled), [false, true, true]);
  assert.equal(elements.previewCard.parentElement, elements.reviewPreviewSlot);
  assert.equal(elements.outputBox.hidden, true);
  console.log('PASS: Three progressive steps, merged direction input, validation, preview placement, preserved drafts, stale-result labeling, render retry, scene seeking, home/resume, and new-project reset.');
})().catch(error => { console.error(error); process.exitCode = 1; });
