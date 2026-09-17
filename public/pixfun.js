"use strict";
const $ = id => document.getElementById(id);
const state = { jobId: null, busy: false, step: 1, furthestStep: 1, reviewed: false, briefSaved: false, briefDirty: false, textDirty: false, textConfirmed: false, renderedText: null, notesDirty: false, references: [], segments: [], clips: [], outputUrl: null };
const timeLabel = seconds => `${Math.floor(Number(seconds || 0) / 60)}:${String(Math.floor(Number(seconds || 0) % 60)).padStart(2, "0")}`;
let timelineAnimationFrame = 0;
function status(id, message, error = false) { $(id).textContent = message; $(id).classList.toggle("error", error); }
function busy(value) {
  state.busy = value;
  ["analyzeBtn", "uploadBtn", "fileInput", "urlInput", "renderBtn", "saveTranscript", "saveBrief", "splitBtn"].forEach(id => { if ($(id)) $(id).disabled = value; });
  document.querySelectorAll("[data-studio-step], #editBack, #textNext, #exportBack, #changeVideo, #backHome, #resumeStudio, #briefForm input, #briefForm textarea, #briefForm select, #textForm input, #transcriptInput").forEach(element => { element.disabled = value; });
  syncStepNavigation();
  $("create").setAttribute("aria-busy", String(value));
  $("results").setAttribute("aria-busy", String(value));
}
function setStudioMode(active, updateHistory = true) {
  active = Boolean(active && state.jobId);
  document.body.classList.toggle("studio-mode", active);
  $("results").hidden = !active;
  $("resumeStudio").hidden = !state.jobId;
  document.querySelector(".skip").href = active ? "#results" : "#create";
  document.querySelector(".skip").textContent = active ? "Skip to workspace" : "Skip to video upload";
  if (!active) { $("sourceVideo").pause(); $("outputVideo").pause(); }
  if (updateHistory) history.pushState(null, "", active ? "#studio" : "#create");
  document.dispatchEvent(new Event("pixfun:viewchange"));
  window.scrollTo({ top: 0, behavior: "instant" });
  if (active) $("studioTitle").focus({ preventScroll: true });
}
function syncStepNavigation() {
  document.querySelectorAll("[data-studio-step]").forEach(button => {
    const number = Number(button.dataset.studioStep);
    button.disabled = state.busy || number > state.furthestStep;
    if (number === state.step) button.setAttribute("aria-current", "step"); else button.removeAttribute("aria-current");
    button.classList.toggle("completed", number === 1 ? state.briefSaved && !state.briefDirty : number === 2 ? state.textConfirmed : Boolean(state.outputUrl && !state.textDirty));
  });
}
function setStep(step, focus = true) {
  const next = Math.max(1, Math.min(3, Number(step)));
  if (next === 3 && !validateText()) return;
  if (next === 3) state.textConfirmed = true;
  state.step = next;
  state.furthestStep = Math.max(state.furthestStep, state.step);
  if (state.step > 1) state.reviewed = true;
  document.querySelectorAll("[data-studio-panel]").forEach(panel => { panel.hidden = Number(panel.dataset.studioPanel) !== state.step; });
  syncStepNavigation();
  $("sourceVideo").pause(); $("outputVideo").pause();
  const exporting = state.step === 3;
  const showResult = exporting && Boolean(state.outputUrl);
  $(exporting ? "resultPreviewSlot" : "reviewPreviewSlot").append($("previewCard"));
  $("previewSwitch").hidden = !showResult;
  $("sourceInfo").hidden = exporting;
  selectPreview(showResult);
  $("studioProgressLabel").textContent = `Step ${state.step} of 3`;
  if (exporting) syncExportState();
  if (state.step === 2) {
    $("briefSummary").hidden = !state.briefSaved && !state.briefDirty;
    $("briefSummary").textContent = state.briefDirty ? "Your direction has unsaved changes." : "Direction saved.";
  }
  if (focus) {
    const title = $(["reviewTitle", "editTitle", "exportTitle"][state.step - 1]);
    title.focus({ preventScroll: true });
    $("results").scrollIntoView({ block: "start", behavior: "instant" });
  }
}
function textValues() {
  return { hook: $("hookInput").value.trim(), subject: $("subjectInput").value.trim(), cta: $("ctaInput").value.trim() };
}
function validateText() {
  const fields = ["hookInput", "subjectInput", "ctaInput"];
  fields.forEach(id => { $(id).setAttribute("aria-invalid", String(!$(id).value.trim())); $(id).setAttribute("aria-describedby", "textStatus"); });
  const missing = fields.find(id => !$(id).value.trim());
  if (!missing) return true;
  if (state.step !== 2) setStep(2);
  status("textStatus", "Add an opening hook, a main message, and a closing line to continue.", true);
  $(missing).focus();
  return false;
}
function syncExportState() {
  const values = textValues();
  $("summaryHook").textContent = values.hook;
  $("summaryMessage").textContent = values.subject;
  $("summaryCta").textContent = values.cta;
  const stale = Boolean(state.outputUrl && state.textDirty);
  const ready = Boolean(state.outputUrl && !state.textDirty);
  $("renderForm").hidden = ready;
  $("outputBox").hidden = !state.outputUrl;
  $("exportDescription").textContent = ready ? "Play your finished video or compare it with the original." : stale ? "Your text has changed. Create an updated video to apply your edits." : "Check your original footage and text, then create your video.";
  $("outputTitle").textContent = stale ? "Previous version" : "Your video is ready.";
  $("outputDescription").textContent = stale ? "This version does not include your latest text changes." : "Play the result above, then download your video.";
  $("downloadLink").textContent = stale ? "Download previous version" : "Download MP4";
  $("downloadLink").classList.toggle("primary", !stale);
  $("downloadLink").classList.toggle("secondary", stale);
  $("renderBtn").textContent = state.outputUrl ? "Update video" : "Create video";
}
function selectPreview(result) {
  result = Boolean(result && state.outputUrl);
  $("sourceVideo").hidden = result;
  $("outputVideo").hidden = !result;
  $(result ? "sourceVideo" : "outputVideo").pause();
  $("originalPreview").setAttribute("aria-pressed", String(!result));
  $("resultPreview").setAttribute("aria-pressed", String(result));
  $("previewLabel").textContent = result ? (state.textDirty ? "Previous result" : "Your new video") : "Source video";
}
function renderClipOutputs() {
  $("clipOutputList").replaceChildren();
  $("clipOutputs").hidden = !state.clips.length;
  $("clipOutputCount").textContent = `${state.clips.length} MP4 file${state.clips.length === 1 ? "" : "s"}`;
  state.clips.forEach((clip, index) => {
    const item = document.createElement("div"), copy = document.createElement("div"), title = document.createElement("b"), meta = document.createElement("span"), link = document.createElement("a");
    item.className = "clip-output";
    title.textContent = clip.label || `Scene ${String(index + 1).padStart(2, "0")}`;
    meta.textContent = `${timeLabel(clip.start)} – ${timeLabel(clip.end)} · ${Number(clip.duration || 0).toFixed(1)}s`;
    copy.append(title, meta);
    link.className = "button secondary"; link.textContent = "Download MP4"; link.href = clip.url; link.download = clip.filename || `clip-${index + 1}.mp4`;
    item.append(copy, link); $("clipOutputList").append(item);
  });
}
function renderTimelineRuler(duration) {
  $("timelineRuler").replaceChildren();
  for (let index = 0; index < 5; index++) {
    const mark = document.createElement("span");
    mark.textContent = timeLabel(Number(duration || 0) * index / 4);
    $("timelineRuler").append(mark);
  }
}
function syncTimelinePosition() {
  const video = $("sourceVideo"), duration = Number(video.duration || 0), current = Math.max(0, Number(video.currentTime || 0));
  const percent = duration > 0 ? Math.min(100, current / duration * 100) : 0;
  $("workspacePlayhead").style.left = `calc(7px + (100% - 14px) * ${percent / 100})`;
  $("workspacePlayhead").classList.toggle("near-end", percent > 82);
  $("timelineCurrentTime").textContent = timeLabel(current);
  $("timelineNow").textContent = `Now · ${timeLabel(current)}`;
  const activeIndex = state.segments.findIndex((segment, index) => current >= Number(segment.start || 0) && (current < Number(segment.end || 0) || index === state.segments.length - 1));
  $("timeline").querySelectorAll("button").forEach((button, index) => button.setAttribute("aria-pressed", String(index === Math.max(0, activeIndex))));
  const editor = $("timelineEditor");
  if (!video.paused && editor && editor.scrollWidth > editor.clientWidth) {
    const target = editor.scrollWidth * percent / 100 - editor.clientWidth * .56;
    editor.scrollLeft = Math.max(0, Math.min(editor.scrollWidth - editor.clientWidth, target));
  }
}
function stopTimelineMotion() {
  if (timelineAnimationFrame && typeof cancelAnimationFrame === "function") cancelAnimationFrame(timelineAnimationFrame);
  timelineAnimationFrame = 0;
  $("timelineTrack").classList.remove("is-playing");
  syncTimelinePosition();
}
function runTimelineMotion() {
  syncTimelinePosition();
  if ($("sourceVideo").paused || $("sourceVideo").ended || typeof requestAnimationFrame !== "function") return stopTimelineMotion();
  timelineAnimationFrame = requestAnimationFrame(runTimelineMotion);
}
function startTimelineMotion() {
  if (timelineAnimationFrame || typeof requestAnimationFrame !== "function") return;
  $("timelineTrack").classList.add("is-playing");
  timelineAnimationFrame = requestAnimationFrame(runTimelineMotion);
}
async function hydrateTimelineThumbnails(sourceUrl, images, segments) {
  if (typeof HTMLCanvasElement === "undefined" || !sourceUrl || !images.length) return;
  const media = document.createElement("video"), canvas = document.createElement("canvas"), context = canvas.getContext("2d");
  if (!context) return;
  media.muted = true; media.playsInline = true; media.preload = "auto"; media.src = sourceUrl;
  const waitFor = event => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timed out waiting for ${event}`)), 6000);
    const done = () => { clearTimeout(timer); resolve(); };
    const failed = () => { clearTimeout(timer); reject(new Error("Could not read preview frames")); };
    media.addEventListener(event, done, { once: true }); media.addEventListener("error", failed, { once: true });
  });
  try {
    if (media.readyState < 1) await waitFor("loadedmetadata");
    const scale = Math.min(1, 320 / Math.max(media.videoWidth || 320, media.videoHeight || 180));
    canvas.width = Math.max(1, Math.round((media.videoWidth || 320) * scale));
    canvas.height = Math.max(1, Math.round((media.videoHeight || 180) * scale));
    for (let index = 0; index < images.length; index++) {
      const segment = segments[index] || {}, target = Math.min(Math.max(0, Number(segment.end || media.duration) - .05), Number(segment.start || 0) + Math.max(.05, Number(segment.duration || 0) * .45));
      if (Math.abs(media.currentTime - target) > .02 || media.readyState < 2) { media.currentTime = target; await waitFor("seeked"); }
      context.drawImage(media, 0, 0, canvas.width, canvas.height);
      images[index].src = canvas.toDataURL("image/jpeg", .78); images[index].hidden = false;
    }
  } catch { /* The timeline remains usable if a browser cannot extract frames. */ }
  finally { media.removeAttribute("src"); media.load(); }
}
async function request(url, options) {
  const response = await fetch(url, options);
  let data;
  try { data = await response.json(); } catch { throw new Error("The service returned an invalid response. Check that your local server is running."); }
  if (!response.ok || !data.ok) throw new Error(data.error || "Processing failed. Please try again.");
  return data;
}
const postJSON = (url, data) => request(url, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(data) });
function showAnalysis(data) {
  state.jobId = data.jobId;
  Object.assign(state, { furthestStep: 1, reviewed: false, briefSaved: false, briefDirty: false, textDirty: false, textConfirmed: false, renderedText: null, notesDirty: false, references: [], segments: [], clips: [], outputUrl: null });
  $("results").hidden = false;
  $("outputBox").hidden = true;
  $("outputVideo").pause(); $("outputVideo").removeAttribute("src"); $("outputVideo").load();
  $("downloadLink").removeAttribute("href");
  $("resultPreview").disabled = true;
  selectPreview(false);
  $("sourceVideo").src = data.sourceUrl || "";
  const analysis = data.analysis;
  $("fileName").textContent = analysis.sourceName;
  const meta = analysis.metadata || {};
  $("metrics").replaceChildren();
  [[timeLabel(meta.duration), "Duration"], [`${meta.width || "—"} × ${meta.height || "—"}`, "Resolution"], [String(analysis.cutCount || 0), "Scene changes"]].forEach(([value, label]) => {
    const item = document.createElement("div"), strong = document.createElement("b");
    strong.textContent = value; item.append(strong, document.createTextNode(label)); $("metrics").append(item);
  });
  $("timeline").replaceChildren();
  state.segments = analysis.segments || [];
  const segmentTotal = state.segments.length, thumbnailImages = [];
  $("segmentCount").textContent = `${segmentTotal} ${segmentTotal === 1 ? "segment" : "segments"}`;
  $("splitBtn").textContent = `Create ${segmentTotal} clip${segmentTotal === 1 ? "" : "s"}`;
  state.segments.forEach((segment, i) => {
    const button = document.createElement("button"), thumbnail = document.createElement("span"), image = document.createElement("img"), label = document.createElement("span"), time = document.createElement("span");
    button.type = "button"; button.className = "timeline-clip"; button.style.flexGrow = Math.max(1, Number(segment.duration) || 1);
    thumbnail.className = "clip-thumbnail"; image.alt = ""; image.hidden = true; image.width = 320; image.height = 180; thumbnail.append(image); thumbnailImages.push(image);
    label.className = "clip-label"; label.textContent = `Scene ${String(i + 1).padStart(2, "0")}`;
    time.className = "clip-time"; time.textContent = `${timeLabel(segment.start)} – ${timeLabel(segment.end)}`; button.append(thumbnail, label, time);
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => {
      selectPreview(false);
      $("sourceVideo").currentTime = Number(segment.start) || 0;
      syncTimelinePosition();
      $("sourceVideo").focus({ preventScroll: true });
    }); $("timeline").append(button);
  });
  renderTimelineRuler(meta.duration);
  syncTimelinePosition();
  hydrateTimelineThumbnails(data.sourceUrl || "", thumbnailImages, state.segments);
  renderClipOutputs();
  $("transcriptInput").value = analysis.transcriptState ? analysis.transcript || "" : "";
  $("textForm").reset();
  $("renderForm").hidden = false;
  if ($("briefForm")) $("briefForm").reset();
  $("renderBtn").textContent = "Create video";
  setStep(1, false);
  ["renderStatus", "textStatus", "transcriptStatus", "briefStatus", "splitStatus"].forEach(id => { if ($(id)) status(id, ""); });
  setStudioMode(true);
}
async function importVideo(form, link = false) {
  if (state.busy) return;
  if (state.jobId && (state.briefDirty || state.textDirty || state.notesDirty) && !window.confirm("Start a new video? Unsaved edits in this workspace will be replaced after the import succeeds.")) { $("fileInput").value = ""; return; }
  busy(true);
  status("importStatus", link ? "Downloading the YouTube video and detecting scenes. This may take a few minutes." : "Uploading the video and detecting scenes. Keep this page open.");
  try { showAnalysis(await request("/api/import", { method: "POST", body: form })); status("importStatus", "Video imported. Open your studio to continue."); }
  catch (error) { status("importStatus", error.message === "Failed to fetch" ? "Cannot connect to the local service. Make sure the server is running." : error.message, true); }
  finally { busy(false); $("fileInput").value = ""; }
}
function uploadFile(file) {
  if (!file || state.busy) return;
  if (!/\.(mp4|mov|mkv|webm|m4v|avi|mpeg|mpg|ogv|mts|m2ts)$/i.test(file.name) && !file.type.startsWith("video/")) return status("importStatus", "Choose a video file such as MP4, MOV, or WebM.", true);
  if (file.size > 500 * 1024 * 1024) return status("importStatus", "The upload limit is 500 MB per video. Compress your file and try again.", true);
  const form = new FormData(); form.append("file", file); importVideo(form);
}
$("urlForm").addEventListener("submit", event => {
  event.preventDefault(); let url;
  try { url = new URL($("urlInput").value.trim()); } catch { return status("importStatus", "Enter a complete video URL.", true); }
  if (!["http:", "https:"].includes(url.protocol)) return status("importStatus", "Use an http or https video link.", true);
  const form = new FormData(); form.append("url", url.href); importVideo(form, true);
});
$("uploadBtn").addEventListener("click", () => $("fileInput").click());
$("fileInput").addEventListener("change", event => uploadFile(event.target.files[0]));
let dragDepth = 0;
$("create").addEventListener("dragenter", event => { event.preventDefault(); dragDepth++; if (!state.busy) $("create").classList.add("dragging"); });
$("create").addEventListener("dragover", event => event.preventDefault());
$("create").addEventListener("dragleave", () => { if (--dragDepth <= 0) $("create").classList.remove("dragging"); });
$("create").addEventListener("drop", event => {
  event.preventDefault(); dragDepth = 0; $("create").classList.remove("dragging");
  if (event.dataTransfer.files.length > 1) return status("importStatus", "Import one video at a time.", true);
  uploadFile(event.dataTransfer.files[0]);
});
$("saveTranscript").addEventListener("click", async () => {
  if (!state.jobId || state.busy) return; busy(true);
  try { await postJSON("/api/analyze", { jobId: state.jobId, transcript: $("transcriptInput").value }); state.notesDirty = false; status("transcriptStatus", "Notes saved locally."); }
  catch (error) { status("transcriptStatus", error.message, true); } finally { busy(false); }
});
$("splitBtn").addEventListener("click", async () => {
  if (!state.jobId || state.busy || !state.segments.length) return;
  busy(true); status("splitStatus", `Creating ${state.segments.length} MP4 clip${state.segments.length === 1 ? "" : "s"}…`);
  try {
    const result = await postJSON("/api/split", { jobId: state.jobId });
    state.clips = result.clips || [];
    renderClipOutputs();
    $("splitBtn").textContent = `Recreate ${state.clips.length} clip${state.clips.length === 1 ? "" : "s"}`;
    status("splitStatus", `${state.clips.length} clip${state.clips.length === 1 ? " is" : "s are"} ready to download.`);
    $("clipOutputs").scrollIntoView({ block: "nearest", behavior: "smooth" });
  } catch (error) { status("splitStatus", error.message, true); }
  finally { busy(false); }
});
$("textForm").addEventListener("submit", event => {
  event.preventDefault(); if (state.busy || !state.jobId || !validateText()) return;
  state.textConfirmed = true;
  status("textStatus", "");
  setStep(3);
});
$("renderForm").addEventListener("submit", async event => {
  event.preventDefault(); if (!state.jobId || state.busy) return;
  if (!validateText()) return;
  const values = textValues();
  busy(true); status("renderStatus", "Creating your video… This may take a few minutes.");
  $("renderBtn").textContent = "Creating video…";
  try {
    const result = await postJSON("/api/render", { jobId: state.jobId, ...values });
    state.outputUrl = result.outputUrl;
    state.renderedText = JSON.stringify(values);
    state.textDirty = false;
    $("outputVideo").src = result.outputUrl; $("downloadLink").href = result.outputUrl; $("outputBox").hidden = false;
    $("resultPreview").disabled = false;
    selectPreview(true);
    setStep(3, false);
    status("renderStatus", "Ready. Select Original or Result to compare.");
    $("downloadLink").focus({ preventScroll: true });
    $("resultPreviewSlot").scrollIntoView({ block: "start", behavior: "instant" });
  } catch (error) { status("renderStatus", error.message, true); } finally { busy(false); $("renderBtn").textContent = state.outputUrl ? "Update video" : "Create video"; }
});
if ($("briefForm")) $("briefForm").addEventListener("submit", async event => {
  event.preventDefault(); if (!state.jobId || state.busy) return;
  const brief = { material: "", person: "", dialogue: "", language: "keep", instructions: $("extraBrief").value.trim() };
  const form = new FormData(); form.append("jobId", state.jobId); form.append("brief", JSON.stringify(brief));
  busy(true); status("briefStatus", "Saving your direction…");
  try {
    const data = await request("/api/brief", { method: "POST", body: form });
    state.references = []; state.briefSaved = true; state.briefDirty = false;
    status("briefStatus", "Direction saved.");
    setStep(2);
  }
  catch (error) { status("briefStatus", error.message, true); } finally { busy(false); }
});
document.querySelectorAll("[data-studio-step]").forEach(button => button.addEventListener("click", () => { if (!state.busy && Number(button.dataset.studioStep) <= state.furthestStep) setStep(button.dataset.studioStep); }));
$("editBack").addEventListener("click", () => setStep(1));
$("exportBack").addEventListener("click", () => setStep(2));
$("originalPreview").addEventListener("click", () => selectPreview(false));
$("resultPreview").addEventListener("click", () => selectPreview(true));
$("briefForm").addEventListener("input", () => { state.briefDirty = true; status("briefStatus", "Unsaved changes"); });
$("sourceVideo").addEventListener("loadedmetadata", () => { renderTimelineRuler($("sourceVideo").duration); syncTimelinePosition(); });
$("sourceVideo").addEventListener("timeupdate", syncTimelinePosition);
$("sourceVideo").addEventListener("seeked", syncTimelinePosition);
$("sourceVideo").addEventListener("play", startTimelineMotion);
$("sourceVideo").addEventListener("pause", stopTimelineMotion);
$("sourceVideo").addEventListener("ended", stopTimelineMotion);
$("textForm").addEventListener("input", () => {
  state.textDirty = JSON.stringify(textValues()) !== state.renderedText;
  state.textConfirmed = false;
  status("textStatus", "");
  ["hookInput", "subjectInput", "ctaInput"].forEach(id => $(id).removeAttribute("aria-invalid"));
  status("renderStatus", state.outputUrl && state.textDirty ? "Text changed. Update the video to apply your edits." : "");
  syncStepNavigation();
});
$("transcriptInput").addEventListener("input", () => { state.notesDirty = true; status("transcriptStatus", "Unsaved notes"); });
$("backHome").addEventListener("click", () => { if (!state.busy) setStudioMode(false); });
$("changeVideo").addEventListener("click", () => { if (!state.busy) { setStudioMode(false); $("urlInput").focus(); } });
$("resumeStudio").addEventListener("click", () => { if (!state.busy) setStudioMode(true); });
document.querySelector(".header .brand").addEventListener("click", event => { if (document.body.classList.contains("studio-mode")) { event.preventDefault(); if (!state.busy) setStudioMode(false); } });
window.addEventListener("popstate", () => setStudioMode(location.hash === "#studio", false));
window.addEventListener("beforeunload", event => { if (state.briefDirty || state.textDirty || state.notesDirty || state.busy) { event.preventDefault(); event.returnValue = ""; } });
fetch("/api/health").then(response => response.json()).then(data => {
  $("engineText").textContent = data.tools.ffmpeg && data.tools.ffprobe ? (data.tools["yt-dlp"] ? "Local video engine ready" : "Local engine ready · Link imports require yt-dlp") : "Video engine unavailable · Install FFmpeg";
}).catch(() => { $("engineText").textContent = "Local service disconnected"; });
