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
    $("engineText").textContent = good ? "FFmpeg 本地引擎就绪" : "部分本地引擎未就绪";
  } catch {
    $("engineText").textContent = "本地服务未连接";
  }
}

function showVideo(url, badge = "已导入") {
  const frame = $("videoFrame");
  frame.className = "video-frame";
  frame.innerHTML = `<video controls playsinline src="${url}"></video>`;
  $("previewBadge").textContent = badge;
}

function renderAnalysis(analysis) {
  state.analysis = analysis;
  $("results").classList.remove("hidden");
  const meta = analysis.metadata || {};
  $("fileName").textContent = analysis.sourceName || "参考视频";
  $("fileDuration").textContent = meta.durationLabel || durationLabel(meta.duration);
  const metrics = [
    ["视频时长", meta.durationLabel || durationLabel(meta.duration), `${meta.orientation || ""} · ${meta.width || 0}×${meta.height || 0}`],
    ["镜头切换", `${analysis.cutCount || 0} 次`, "初步识别"],
    ["Hook 强度", `${analysis.hookScore || 0}`, "/ 100 · 规则估算"],
    ["结构清晰度", `${analysis.structureScore || 0}`, "/ 100 · 可继续校准"],
  ];
  $("metrics").innerHTML = metrics.map(([label, value, small]) => `<div class="metric"><span class="label">${label}</span><strong>${value}</strong><small>${small}</small></div>`).join("");
  $("timeline").innerHTML = (analysis.segments || []).map(seg => `<div class="timeline-seg" style="flex-grow:${Math.max(1, seg.duration)}"><span class="seg-label">${seg.label}</span><span class="seg-time">${durationLabel(seg.start)} — ${durationLabel(seg.end)}</span><span class="seg-note">${seg.note}</span></div>`).join("");
  $("variables").innerHTML = (analysis.suggestedVariables || []).map(v => `<div class="variable"><div class="variable-head"><span class="variable-key">${v.key.toUpperCase()}</span><strong>${v.label}</strong><span>↗</span></div><p>${v.value}</p></div>`).join("");
  $("transcriptInput").value = analysis.transcript || "";
  window.location.hash = "results";
}

async function importVideo(formData) {
  setStatus("importStatus", "正在读取视频、分析元数据和镜头变化……");
  $("importStatus").classList.remove("hidden");
  $("analyzeBtn").disabled = true;
  try {
    const res = await fetch("/api/import", { method: "POST", body: formData });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || "导入失败");
    state.jobId = data.jobId;
    state.sourceUrl = data.sourceUrl;
    if (data.sourceUrl) showVideo(data.sourceUrl);
    renderAnalysis(data.analysis);
    setStatus("importStatus", "导入完成。下面是可编辑的初步结构分析。", "ok");
  } catch (err) {
    setStatus("importStatus", err.message || "导入失败", "error");
  } finally {
    $("analyzeBtn").disabled = false;
  }
}

$("analyzeBtn").addEventListener("click", () => {
  const url = $("urlInput").value.trim();
  if (!url) return setStatus("importStatus", "请先输入一个视频链接，或选择本地视频。", "error");
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
  if (!localPath) return setStatus("importStatus", "请输入本地视频路径。", "error");
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
  $("transcriptState").textContent = data.ok ? "已保存到本地任务" : (data.error || "保存失败");
});

$("renderBtn").addEventListener("click", async () => {
  if (!state.jobId) return setStatus("renderStatus", "请先导入一个视频。", "error");
  setStatus("renderStatus", "正在使用本地 FFmpeg 生成变体……");
  $("renderStatus").classList.remove("hidden");
  $("renderBtn").disabled = true;
  try {
    const res = await fetch("/api/render", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jobId: state.jobId, hook: $("hookInput").value, subject: $("subjectInput").value, cta: $("ctaInput").value }) });
    const data = await res.json();
    if (!res.ok || !data.ok) throw new Error(data.error || "生成失败");
    $("outputBadge").textContent = "已生成";
    $("outputBox").innerHTML = `<video controls playsinline src="${data.outputUrl}"></video><a class="download-link" href="${data.outputUrl}" download>下载这个变体 ↓</a>`;
    setStatus("renderStatus", "变体已经写入本地 data/outputs/。", "ok");
  } catch (err) {
    setStatus("renderStatus", err.message || "生成失败", "error");
  } finally {
    $("renderBtn").disabled = false;
  }
});

$("newBtn").addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));
checkHealth();
