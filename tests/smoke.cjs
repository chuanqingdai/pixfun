/* Run with: node tests/smoke.cjs /absolute/path/to/test-video.mp4 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const base = 'http://127.0.0.1:8765';
async function json(url, options) {
  const response = await fetch(base + url, options);
  const data = await response.json();
  assert.ok(response.ok && data.ok, JSON.stringify(data));
  return data;
}
(async () => {
  const health = await json('/api/health');
  assert.ok(health.tools.ffmpeg && health.tools.ffprobe);
  for (const asset of ['/', '/assets/pixfun.css', '/assets/studio.css', '/assets/pixfun.js', '/assets/motion.js', '/assets/images/pixfun-logo.png', '/assets/images/speaker-medium.png', '/assets/images/speaker-wide.png', '/assets/images/speaker-audience.png', '/assets/images/speaker-close.png']) {
    const response = await fetch(base + asset); assert.equal(response.status, 200, asset);
    assert.ok((await response.arrayBuffer()).byteLength > 0, asset);
  }
  const upload = new FormData();
  upload.append('file', new Blob([fs.readFileSync(process.argv[2])], { type: 'video/mp4' }), 'pixfun-smoke.mp4');
  const imported = await json('/api/import', { method: 'POST', body: upload });
  assert.ok(imported.analysis.metadata.duration >= 6);
  assert.equal((await fetch(base + imported.sourceUrl)).status, 200);
  const split = await json('/api/split', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jobId: imported.jobId }) });
  assert.equal(split.count, imported.analysis.segments.length);
  for (const clip of split.clips) {
    const clipResponse = await fetch(base + clip.url); assert.equal(clipResponse.status, 200);
    assert.ok((await clipResponse.arrayBuffer()).byteLength > 1000);
  }
  const brief = new FormData(); brief.append('jobId', imported.jobId);
  brief.append('brief', JSON.stringify({ person: 'Use my authorized reference', language: 'es', dialogue: 'Cambia de perspectiva.', material: 'Keep original footage', instructions: 'Keep the rhythm' }));
  brief.append('references', new Blob([fs.readFileSync(path.resolve(__dirname, '../public/images/pixfun-logo.png'))], { type: 'image/png' }), 'test-reference.png');
  const saved = await json('/api/brief', { method: 'POST', body: brief });
  assert.equal(saved.brief.language, 'es'); assert.equal(saved.applied, false); assert.equal(saved.references.length, 1);
  const persisted = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../data/jobs', imported.jobId + '.json'), 'utf8'));
  assert.equal(persisted.creativeBrief.person, 'Use my authorized reference');
  assert.ok(fs.existsSync(path.resolve(__dirname, '../data/uploads', imported.jobId, 'references', persisted.references[0].storedName)));
  for (const transcript of ['A sample script.', '']) {
    const result = await json('/api/analyze', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jobId: imported.jobId, transcript }) });
    assert.equal(result.analysis.transcript, transcript);
  }
  const rendered = await json('/api/render', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ jobId: imported.jobId, hook: 'Cambia de perspectiva.', subject: 'El mundo te espera.', cta: 'Tu proximo destino.' }) });
  const output = await fetch(base + rendered.outputUrl); assert.equal(output.status, 200);
  assert.ok((await output.arrayBuffer()).byteLength > 1000);
  const invalid = await fetch(base + '/api/import', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url: 'file:///private/etc/hosts' }) }); assert.equal(invalid.status, 400);
  console.log(JSON.stringify({ ok: true, jobId: imported.jobId, outputUrl: rendered.outputUrl, clipCount: split.count, checks: ['assets', 'video upload', 'metadata', 'scene split MP4 files', 'creative brief', 'reference file persistence', 'notes and clearing notes', 'Spanish text MP4 export', 'invalid URL rejection'] }, null, 2));
})().catch(error => { console.error(error); process.exitCode = 1; });
