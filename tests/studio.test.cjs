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
const studioFlowCss = fs.readFileSync(path.resolve(__dirname, '../public/studio-flow.css'), 'utf8');
const controlsCss = fs.readFileSync(path.resolve(__dirname, '../public/controls.css'), 'utf8');

assert.match(html, /class="create-split"/, 'Create uses a split workspace');
assert.match(html, /class="media-workspace"/, 'Video, timeline, and subtitles share the media pane');
assert.match(html, /class="chat-workspace"/, 'Natural-language editing stays in a dedicated chat pane');
assert.doesNotMatch(html, /class="workspace-section-heading"|class="chat-toolbar"/, 'Media and chat panes do not repeat internal title bars');
assert.match(html, /id="textForm"[^>]*novalidate[^>]*hidden/, 'Chat composer is revealed after the first direction');
assert.match(html, /id="timelineRuler"/, 'Media pane includes a timeline ruler');
assert.match(html, /id="workspacePlayhead"/, 'Timeline includes a synchronized playhead');
assert.match(html, /id="subtitleLane"/, 'Subtitles render in their own list below the timeline');
assert.match(html, /placeholder="Describe changes…"/, 'The initial direction prompt stays concise');
assert.match(html, /placeholder="Message Pixfun…"/, 'The chat prompt stays concise');
assert.doesNotMatch(html, /id="editBack"|STEP 02 \/ REFINE|Shape your version together|Script notes|id="saveTranscript"/, 'The merged workspace removes the redundant refine page and copy');
assert.doesNotMatch(html, /class="studio-heading"|class="studio-steps"/, 'The redundant studio title and step rail are removed');
assert.match(html, /class="studio-header-actions"[^>]*>[\s\S]*id="changeVideo"[\s\S]*id="confirmConversation"/, 'New video and Export live in the top navigation');
assert.equal((html.match(/data-studio-step=/g) || []).length, 0, 'Studio no longer repeats progress navigation');
assert.equal((html.match(/data-studio-panel=/g) || []).length, 2, 'Review and chat are merged into one Create panel');
assert.match(studioFlowCss, /create-split[^}]*grid-template-columns:\s*minmax\(0,\s*1\.62fr\)\s*minmax\(360px,\s*\.92fr\)/s, 'Desktop layout gives more room to the media pane');
assert.match(studioFlowCss, /chat-workspace[^}]*grid-template-rows:\s*minmax\(0,\s*1fr\) auto/s, 'Chat content and input use a compact two-row layout');
assert.match(studioFlowCss, /quick-direction,[\s\S]*conversation-composer[^{]*\{[^}]*position:\s*static/s, 'Composers no longer float over the video workspace');
assert.match(studioFlowCss, /@media \(max-width:\s*960px\)[\s\S]*create-split[^}]*grid-template-columns:\s*1fr/s, 'The split workspace stacks below the desktop breakpoint');
assert.match(studioFlowCss, /quick-direction textarea,[\s\S]*conversation-composer textarea[^}]*background:\s*#1c1721/s, 'Inputs use a distinct dark surface');
assert.match(studioFlowCss, /quick-direction textarea:focus-visible,[\s\S]*conversation-composer textarea:focus-visible[^}]*outline:\s*none[^}]*box-shadow:\s*none/s, 'Inputs keep a quiet focus state');
assert.match(studioFlowCss, /studio-bottomline[^}]*display:\s*none/, 'The redundant bottom progress label stays hidden');
assert.match(controlsCss, /button\[aria-busy="true"\]/, 'Import buttons expose a visible loading state');

const elements = Object.fromEntries([...html.matchAll(/\bid="([^"]+)"/g)].map(([, id]) => [id, new Element(id)]));
const steps = [];
const panels = [1, 2].map(n => { const e = new Element(); e.dataset.studioPanel = String(n); return e; });
const brand = new Element(), skip = new Element(), body = new Element();
const eventHandlers = {};
const document = {
  body,
  getElementById: id => elements[id] || null,
  createElement: tag => new Element('', tag),
  createTextNode: text => ({ textContent: text }),
  querySelector: selector => selector === '.skip' ? skip : selector === '.header .brand' ? brand : null,
  querySelectorAll: selector => selector === '[data-studio-step]' ? steps : selector === '[data-studio-panel]' ? panels : selector.startsWith('[data-studio-step],') ? [...steps, ...Object.values(elements)] : [],
  dispatchEvent() {},
};

let failBrief = false, failRender = false, holdImport = false, releaseImport;
const calls = [];
const context = vm.createContext({
  document, console, URL, FormData, Event, location: { hash: '' }, matchMedia: () => ({ matches: false }),
  history: { pushState(_state, _title, hash) { context.location.hash = hash; } },
  window: { scrollTo() {}, confirm: () => true, addEventListener(name, fn) { eventHandlers[name] = fn; } },
  fetch: async (url, options) => {
    calls.push({ url, options });
    let data = { ok: true };
    if (url === '/api/import') {
      if (holdImport) await new Promise(resolve => { releaseImport = resolve; });
      data = { ok: false, error: 'Import test failure' };
    }
    if (url === '/api/health') data.tools = { ffmpeg: true, ffprobe: true, 'yt-dlp': true };
    if (url === '/api/brief') data = failBrief ? { ok: false, error: 'Brief test failure' } : { ok: true, references: [], plan: { items: [], missing: [], ready: true } };
    if (url === '/api/direction') data = { ok: true, draft: { hook: 'My hook', subject: 'My text', cta: 'My close' } };
    if (url === '/api/render') data = failRender ? { ok: false, error: 'Render test failure' } : { ok: true, outputUrl: '/media/output/test/result.mp4' };
    return { ok: data.ok, json: async () => data };
  },
});

vm.runInContext(fs.readFileSync(path.resolve(__dirname, '../public/pixfun.js'), 'utf8'), context);
const run = code => vm.runInContext(code, context);

(async () => {
  elements.urlInput.value = 'https://www.youtube.com/watch?v=test';
  holdImport = true;
  const pendingImport = elements.urlForm.emit('submit');
  await Promise.resolve(); await Promise.resolve();
  assert.equal(elements.analyzeBtn.textContent, 'Loading…', 'Analyze shows loading inside the button');
  assert.equal(elements.analyzeBtn.attrs['aria-busy'], 'true');
  releaseImport(); await pendingImport; await new Promise(resolve => setImmediate(resolve)); holdImport = false;
  assert.equal(elements.analyzeBtn.textContent, 'Analyze');
  assert.equal(elements.importStatus.textContent, 'Import test failure');

  run(`showAnalysis({jobId:'012345abcdef', sourceUrl:'/media/upload/test/source.mp4', analysis:{sourceName:'sample.mp4', metadata:{duration:12,width:1920,height:1080}, cutCount:1, subtitleState:'embedded', subtitleCues:[{start:.5,end:2.5,text:'First subtitle'},{start:6.5,end:9,text:'Second subtitle'}], segments:[{start:0,end:6,duration:6,thumbnailUrl:'/media/output/test/timeline-01.jpg'},{start:6,end:12,duration:6,thumbnailUrl:'/media/output/test/timeline-02.jpg'}]}})`);
  assert.ok(body.classList.contains('studio-mode'));
  assert.equal(context.location.hash, '#studio');
  assert.deepEqual(panels.map(p => p.hidden), [false, true]);
  assert.equal(elements.confirmConversation.disabled, true);
  assert.equal(elements.previewCard.parentElement, elements.reviewPreviewSlot);
  assert.equal(elements.timeline.children.length, 2);
  assert.equal(elements.subtitleLane.children.length, 2);
  assert.equal(elements.subtitleLane.children[0].children[1].textContent, 'First subtitle');
  assert.equal(elements.directionConversation.children.length, 1, 'Create starts with one short Pixfun prompt');
  assert.equal(elements.briefForm.hidden, false);
  assert.equal(elements.textForm.hidden, true);
  await elements.confirmConversation.emit('click');
  assert.equal(run('state.step'), 1, 'Export cannot open before direction is confirmed');

  elements.extraBrief.value = 'Use a confident presenter and Spanish narration';
  await elements.briefForm.emit('input');
  failBrief = true;
  await elements.briefForm.emit('submit');
  assert.equal(run('state.step'), 1);
  assert.equal(elements.briefStatus.textContent, 'Brief test failure');
  failBrief = false;
  await elements.briefForm.emit('submit');
  assert.equal(run('state.step'), 1, 'First direction continues in the same Create workspace');
  assert.equal(run('state.briefSaved'), true);
  assert.deepEqual(panels.map(p => p.hidden), [false, true]);
  assert.equal(elements.briefForm.hidden, true);
  assert.equal(elements.textForm.hidden, false);
  assert.equal(elements.directionConversation.children.length, 2, 'Initial request becomes a user turn followed by a concise Pixfun reply');
  assert.equal(elements.confirmConversation.disabled, false);

  elements.scriptPrompt.value = 'Opening: My hook; Main: My text; Closing: My close';
  await elements.textForm.emit('input');
  await elements.textForm.emit('submit');
  assert.equal(elements.directionConversation.children.length, 4);
  await elements.confirmConversation.emit('click');
  assert.equal(run('state.step'), 2);
  assert.deepEqual(panels.map(p => p.hidden), [true, false]);
  assert.equal(elements.confirmConversation.disabled, true, 'Top navigation marks Export unavailable while already exporting');
  assert.equal(elements.summaryHook.textContent, 'My hook');
  assert.equal(elements.previewCard.parentElement, elements.resultPreviewSlot);

  await elements.renderForm.emit('submit');
  assert.equal(elements.outputBox.hidden, false);
  assert.equal(elements.sourceVideo.hidden, true);
  assert.equal(elements.outputVideo.hidden, false);
  assert.equal(elements.downloadLink.href, '/media/output/test/result.mp4');
  assert.equal(elements.renderForm.hidden, true);
  await elements.originalPreview.emit('click'); assert.equal(elements.sourceVideo.hidden, false);
  await elements.resultPreview.emit('click'); assert.equal(elements.outputVideo.hidden, false);

  await elements.exportBack.emit('click');
  assert.equal(run('state.step'), 1);
  assert.equal(elements.previewCard.parentElement, elements.reviewPreviewSlot);
  await elements.timeline.children[1].emit('click');
  assert.equal(elements.sourceVideo.currentTime, 6);
  assert.equal(elements.timelineNow.textContent, 'Now · 0:06');

  elements.scriptPrompt.value = 'Opening: Updated text';
  await elements.textForm.emit('input');
  assert.equal(elements.confirmConversation.disabled, true, 'Unsent chat input blocks Export');
  await elements.confirmConversation.emit('click');
  assert.equal(run('state.step'), 1, 'Edited direction must be sent and confirmed before export');
  await elements.textForm.emit('submit');
  await elements.confirmConversation.emit('click');
  assert.equal(elements.outputTitle.textContent, 'Previous version');
  assert.equal(elements.renderForm.hidden, false);
  failRender = true;
  await elements.renderForm.emit('submit');
  assert.equal(elements.outputBox.hidden, false, 'Previous result survives a failed update');
  assert.equal(run('state.step'), 2);
  failRender = false;
  await elements.renderForm.emit('submit');
  assert.equal(elements.renderForm.hidden, true);
  assert.equal(elements.downloadLink.textContent, 'Download MP4');

  await elements.backHome.emit('click'); assert.equal(body.classList.contains('studio-mode'), false);
  await elements.resumeStudio.emit('click'); assert.equal(body.classList.contains('studio-mode'), true);
  await elements.exportBack.emit('click');
  elements.scriptPrompt.value = 'An unsent direction';
  await elements.textForm.emit('input');
  let warned = false; eventHandlers.beforeunload({ preventDefault() { warned = true; } }); assert.equal(warned, true);

  run(`showAnalysis({jobId:'fedcba654321', sourceUrl:'/media/upload/new.mp4', analysis:{sourceName:'new.mp4', metadata:{duration:10}, segments:[]}})`);
  assert.equal(elements.confirmConversation.disabled, true);
  assert.equal(elements.previewCard.parentElement, elements.reviewPreviewSlot);
  assert.equal(elements.briefForm.hidden, false);
  assert.equal(elements.textForm.hidden, true);
  assert.equal(elements.subtitleLane.children[0].textContent, 'No editable subtitle track detected');
  console.log('PASS: Split Create workspace, top-navigation export, inline conversation, timeline, subtitles, export validation, render retry, and project reset.');
})().catch(error => { console.error(error); process.exitCode = 1; });
