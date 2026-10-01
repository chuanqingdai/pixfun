const state = { jobId: null, sourceUrl: null, analysis: null };

const $ = (id) => document.getElementById(id);

function setStatus(id, text, kind = "") {
  const el = $(id);
  el.textContent = text;
  el.className = `status ${kind}`;
}

function durationLabel(seconds) {
  const total = Math.round(Number(seconds || 0));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

async function checkHealth() {
  try {
    const res = await fetch("/api/health");
    const data = await res.json();
    const good = data.tools.ffmpeg && data.tools.ffprobe;
    $("engineDot").style.background = good ? "var(--green)" : "var(--amber)";
    $("engineText").textContent = good ? "Local FFmpeg engine ready" : "Some local tools are unavailable";
  } catch {
    $("engineText").textContent = "Local service disconnected";
  }
}

function showVideo(url, badge = "Imported") {
  const frame = $("videoFrame");
  frame.className = "video-frame";
  frame.innerHTML = `<video controls playsinline src="${url}"></video>`;
  $("previewBadge").textContent = badge;
}

function renderAnalysis(analysis) {
  state.analysis = analysis;
  $("results").classList.remove("hidden");
  const meta = analysis.metadata || {};
  $("fileName").textContent = analysis.sourceName || "Reference video";
  $("fileDuration").textContent = meta.durationLabel || durationLabel(meta.duration);
  const metrics = [
    ["Duration", meta.durationLabel || durationLabel(meta.duration), `${meta.orientation || ""} · ${meta.width || 0}×${meta.height || 0}`],
    ["Scene changes", `${analysis.cutCount || 0} cuts`, "Initial detection"],
    ["Hook strength", `${analysis.hookScore || 0}`, "/ 100 · Heuristic estimate"],
    ["Structure clarity", `${analysis.structureScore || 0}`, "/ 100 · Editable estimate"],
  ];
  $("metrics").innerHTML = metrics.map(([label, value, small]) => `<div class="metric"><span class="label">${label}</span><strong>${value}</strong><small>${small}</small></div>`).join("");
  $("timeline").innerHTML = (analysis.segments || []).map(seg => `<div class="timeline-seg" style="flex-grow:${Math.max(1, seg.duration)}"><span class="seg-label">${seg.label}</span><span class="seg-time">${durationLabel(seg.start)} — ${durationLabel(seg.end)}</span><span class="seg-note">${seg.note}</span></div>`).join("");
  $("variables").innerHTML = (analysis.suggestedVariables || []).map(v => `<div class="variable"><div class="variable-head"><span class="variable-key">${v.key.toUpperCase()}</span><strong>${v.label}</strong><span>↗</span></div><p>${v.value}</p></div>`).join("");
  $("transcriptInput").value = analysis.transcript || "";
  window.location.hash = "results";
}

async function importVideo(formData) {
  setStatus("importStatus", "Reading video metadata and detecting scene changes…");
  $("importStatus").classList.remove("hidden");
  $("analyzeBtn").disabled = true;
  try {
    const res = await fetch("/api/import", { method: "POST", body: formData });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || "Import failed");
    state.jobId = data.jobId;
    state.sourceUrl = data.sourceUrl;
    if (data.sourceUrl) showVideo(data.sourceUrl);
    renderAnalysis(data.analysis);
    setStatus("importStatus", "Import complete. Review and refine the initial analysis below.", "ok");
  } catch (err) {
    setStatus("importStatus", err.message || "Import failed", "error");
  } finally {
    $("analyzeBtn").disabled = false;
  }
}

$("analyzeBtn").addEventListener("click", () => {
  const url = $("urlInput").value.trim();
  if (!url) return setStatus("importStatus", "Enter a video link or choose a local video.", "error");
  const form = new FormData();
  form.append("url", url);
  importVideo(form);
});

$("fileInput").addEventListener("change", (event) => {
  const file = event.target.files[0];
  if (!file) return;
  const form = new FormData();
  form.append("file", file);
  importVideo(form);
});

$("pathBtn").addEventListener("click", () => {
  const localPath = $("pathInput").value.trim();
  if (!localPath) return setStatus("importStatus", "Enter a local video path.", "error");
  const form = new FormData();
  form.append("localPath", localPath);
  importVideo(form);
});

$("dropzone").addEventListener("dragover", (event) => { event.preventDefault(); });
$("dropzone").addEventListener("drop", (event) => {
  event.preventDefault();
  const file = event.dataTransfer.files[0];
  if (!file) return;
  const form = new FormData();
  form.append("file", file);
  importVideo(form);
});

$("saveTranscript").addEventListener("click", async () => {
  if (!state.jobId) return;
  const res = await fetch("/api/analyze", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jobId: state.jobId, transcript: $("transcriptInput").value }) });
  const data = await res.json();
  $("transcriptState").textContent = data.ok ? "Saved to the local project" : (data.error || "Save failed");
});

$("renderBtn").addEventListener("click", async () => {
  if (!state.jobId) return setStatus("renderStatus", "Import a video first.", "error");
  setStatus("renderStatus", "Creating your version with local FFmpeg…");
  $("renderStatus").classList.remove("hidden");
  $("renderBtn").disabled = true;
  try {
    const res = await fetch("/api/render", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jobId: state.jobId, hook: $("hookInput").value, subject: $("subjectInput").value, cta: $("ctaInput").value }) });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || "Generation failed");
    $("outputBadge").textContent = "Created";
    $("outputBox").innerHTML = `<video controls playsinline src="${data.outputUrl}"></video><a class="download-link" href="${data.outputUrl}" download>Download this version ↓</a>`;
    setStatus("renderStatus", "Your version has been saved to data/outputs/.", "ok");
  } catch (err) {
    setStatus("renderStatus", err.message || "Generation failed", "error");
  } finally {
    $("renderBtn").disabled = false;
  }
});

$("newBtn").addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));
checkHealth();
