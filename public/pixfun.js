"use strict";
const $ = id => document.getElementById(id);
const state = { jobId: null, busy: false, step: 1, furthestStep: 1, reviewed: false, briefSaved: false, briefDirty: false, creativePlan: null, conversationReady: false, subtitleCues: [], textDirty: false, textConfirmed: false, renderedText: null, notesDirty: false, references: [], segments: [], outputUrl: null };
const timeLabel = seconds => `${Math.floor(Number(seconds || 0) / 60)}:${String(Math.floor(Number(seconds || 0) % 60)).padStart(2, "0")}`;
let timelineAnimationFrame = 0;
function status(id, message, error = false) { $(id).textContent = message; $(id).classList.toggle("error", error); }
function busy(value) {
  state.busy = value;
  ["analyzeBtn", "uploadBtn", "fileInput", "urlInput", "renderBtn", "saveTranscript", "saveBrief", "scriptPrompt", "confirmConversation"].forEach(id => { if ($(id)) $(id).disabled = value; });
  document.querySelectorAll("[data-studio-step], #editBack, #textNext, #exportBack, #changeVideo, #backHome, #resumeStudio, #briefForm input, #briefForm textarea, #briefForm select, #textForm input, #transcriptInput").forEach(element => { element.disabled = value; });
  syncStepNavigation();
  $("create").setAttribute("aria-busy", String(value));
  $("results").setAttribute("aria-busy", String(value));
  if (!value && $("confirmConversation")) $("confirmConversation").disabled = !state.conversationReady;
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
    button.classList.toggle("completed", number === 1 ? state.textConfirmed : Boolean(state.outputUrl && !state.textDirty));
  });
}
function setStep(step, focus = true) {
  const next = Math.max(1, Math.min(2, Number(step)));
  if (next === 2 && !validateText()) return;
  if (next === 2) state.textConfirmed = true;
  state.step = next;
  state.furthestStep = Math.max(state.furthestStep, state.step);
  if (state.step > 1) state.reviewed = true;
  document.querySelectorAll("[data-studio-panel]").forEach(panel => { panel.hidden = Number(panel.dataset.studioPanel) !== state.step; });
  syncStepNavigation();
  $("sourceVideo").pause(); $("outputVideo").pause();
  const exporting = state.step === 2;
  const showResult = exporting && Boolean(state.outputUrl);
  $(exporting ? "resultPreviewSlot" : "reviewPreviewSlot").append($("previewCard"));
  $("previewSwitch").hidden = !showResult;
  $("sourceInfo").hidden = exporting;
  selectPreview(showResult);
  $("studioProgressLabel").textContent = `Step ${state.step} of 2`;
  if (exporting) syncExportState();
  if (focus) {
    const title = $(["reviewTitle", "exportTitle"][state.step - 1]);
    title.focus({ preventScroll: true });
    $("results").scrollIntoView({ block: "start", behavior: "instant" });
  }
}
function textValues() {
  return { hook: $("hookInput").value.trim(), subject: $("subjectInput").value.trim(), cta: $("ctaInput").value.trim() };
}
function validateText() {
  if (state.textConfirmed) return true;
  if (state.step !== 1) setStep(1);
  status("textStatus", "Send at least one direction and confirm the conversation before export.", true);
  $("scriptPrompt").focus();
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
function renderTimelineRuler(duration) {
  $("timelineRuler").replaceChildren();
  for (let index = 0; index < 5; index++) {
    const mark = document.createElement("span");
    mark.textContent = timeLabel(Number(duration || 0) * index / 4);
    $("timelineRuler").append(mark);
  }
}
function renderSubtitleTrack(cues, duration, stateName = "none", message = "") {
  const lane = $("subtitleLane");
  lane.replaceChildren();
  $("subtitleCount").textContent = Array.isArray(cues) && cues.length ? `${cues.length} lines` : "";
  if (!Array.isArray(cues) || !cues.length) {
    const empty = document.createElement("span");
    empty.className = "subtitle-empty";
    empty.textContent = message || (stateName === "unavailable" ? "Speech transcription is unavailable" : stateName === "silent" ? "No speech detected" : "No editable subtitle track detected");
    lane.append(empty);
    return;
  }
  cues.forEach((cue, index) => {
    const start = Math.max(0, Number(cue.start || 0)), end = Math.max(start, Number(cue.end || start));
    const button = document.createElement("button"), time = document.createElement("span"), copy = document.createElement("span");
    button.type = "button"; button.className = "subtitle-cue";
    time.className = "subtitle-cue-time"; time.textContent = `${timeLabel(start)} – ${timeLabel(end)}`;
    copy.className = "subtitle-cue-text"; copy.textContent = cue.text || `Subtitle ${index + 1}`;
    button.append(time, copy);
    button.title = cue.text || "";
    button.setAttribute("aria-label", `${cue.text || `Subtitle ${index + 1}`}, ${timeLabel(start)} to ${timeLabel(end)}`);
    button.addEventListener("click", () => { selectPreview(false); $("sourceVideo").currentTime = start; syncTimelinePosition(); });
    lane.append(button);
  });
}
function renderCreativePlan(plan) {
  state.creativePlan = plan || { items: [], missing: [], ready: false };
}
function resizeDirectionInput() {
  const input = $("extraBrief");
  input.style.height = "50px";
  const contentHeight = Number(input.scrollHeight || 50);
  input.style.height = `${Math.min(120, Math.max(50, contentHeight))}px`;
  input.style.overflowY = contentHeight > 120 ? "auto" : "hidden";
}
function resizeChatInput() {
  const input = $("scriptPrompt");
  input.style.height = "50px";
  const contentHeight = Number(input.scrollHeight || 50);
  input.style.height = `${Math.min(120, Math.max(50, contentHeight))}px`;
  input.style.overflowY = contentHeight > 120 ? "auto" : "hidden";
}
function appendDirectionMessage(role, text) {
  const article = document.createElement("article"), body = document.createElement("p");
  article.className = `conversation-message ${role}`;
  if (role !== "user") { const label = document.createElement("span"); label.className = "conversation-speaker"; label.textContent = "Pixfun"; article.append(label); }
  body.textContent = text; article.append(body);
  $("directionConversation").append(article);
  $("directionConversation").scrollTop = $("directionConversation").scrollHeight;
}
function resetDirectionConversation() {
  const cues = state.subtitleCues || [], midpoint = cues[Math.floor(cues.length / 2)];
  $("hookInput").value = cues[0]?.text || "A stronger opening for your version";
  $("subjectInput").value = midpoint?.text || "Your main message";
  $("ctaInput").value = cues[cues.length - 1]?.text || "Your closing line";
  $("directionConversation").replaceChildren();
  const missing = state.creativePlan?.missing?.join(" ");
  const firstRequest = $("extraBrief").value.trim();
  if (firstRequest) appendDirectionMessage("user", firstRequest);
  appendDirectionMessage("assistant", missing ? `${missing} Add that here when you're ready.` : "Got it. What would you like to refine?");
  $("scriptPrompt").value = "";
  resizeChatInput();
  state.conversationReady = Boolean(firstRequest); state.textConfirmed = false;
  $("confirmConversation").disabled = !state.conversationReady;
}
function applyDirectionInstruction(prompt) {
  const fields = { hook: "hookInput", opening: "hookInput", main: "subjectInput", message: "subjectInput", closing: "ctaInput", cta: "ctaInput" };
  const updated = new Set();
  prompt.split(/[;\n]+/).forEach(part => {
    const match = part.match(/^\s*(hook|opening|main|message|closing|cta)\s*[:=-]\s*(.+)$/i);
    if (!match) return;
    const id = fields[match[1].toLowerCase()];
    $(id).value = match[2].trim().slice(0, 100); updated.add(id);
  });
  if (/shorter|shorten|more concise/i.test(prompt)) {
    ["hookInput", "subjectInput", "ctaInput"].forEach(id => { $(id).value = $(id).value.slice(0, 48); updated.add(id); });
  }
  return updated.size ? "Updated. Anything else?" : "Got it. What else would you like to change?";
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
      if (!images[index].hidden && images[index].src) continue;
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
  Object.assign(state, { furthestStep: 1, reviewed: false, briefSaved: false, briefDirty: false, creativePlan: null, conversationReady: false, subtitleCues: [], textDirty: false, textConfirmed: false, renderedText: null, notesDirty: false, references: [], segments: [], outputUrl: null });
  $("results").hidden = false;
  $("outputBox").hidden = true;
  $("outputVideo").pause(); $("outputVideo").removeAttribute("src"); $("outputVideo").load();
  $("downloadLink").removeAttribute("href");
  $("resultPreview").disabled = true;
  selectPreview(false);
  $("sourceVideo").src = data.sourceUrl || "";
  const analysis = data.analysis;
  state.subtitleCues = analysis.subtitleCues || [];
  $("fileName").textContent = analysis.sourceName;
  const meta = analysis.metadata || {};
  $("metrics").replaceChildren();
  [[timeLabel(meta.duration), "Duration"], [`${meta.width || "—"} × ${meta.height || "—"}`, "Resolution"], [String((analysis.segments || []).length), "Segments"]].forEach(([value, label]) => {
    const item = document.createElement("div"), strong = document.createElement("b");
    strong.textContent = value; item.append(strong, document.createTextNode(label)); $("metrics").append(item);
  });
  $("timeline").replaceChildren();
  state.segments = analysis.segments || [];
  const segmentTotal = state.segments.length, thumbnailImages = [];
  $("segmentCount").textContent = `${segmentTotal} ${segmentTotal === 1 ? "segment" : "segments"}`;
  state.segments.forEach((segment, i) => {
    const button = document.createElement("button"), thumbnail = document.createElement("span"), image = document.createElement("img"), label = document.createElement("span"), time = document.createElement("span");
    button.type = "button"; button.className = "timeline-clip"; button.style.flexGrow = Math.max(1, Number(segment.duration) || 1);
    thumbnail.className = "clip-thumbnail"; image.alt = `Preview frame for scene ${i + 1}`; image.hidden = !segment.thumbnailUrl; image.width = 320; image.height = 180; image.loading = "lazy";
    if (segment.thumbnailUrl) image.src = segment.thumbnailUrl;
    thumbnail.append(image); thumbnailImages.push(image);
    label.className = "clip-label"; label.textContent = `Scene ${String(i + 1).padStart(2, "0")}`;
    time.className = "clip-time"; time.textContent = `${timeLabel(segment.start)} – ${timeLabel(segment.end)}`; button.append(thumbnail, label, time);
    button.setAttribute("aria-label", `Scene ${i + 1}, ${timeLabel(segment.start)} to ${timeLabel(segment.end)}`);
    button.setAttribute("aria-pressed", "false");
    button.addEventListener("click", () => {
      selectPreview(false);
      $("sourceVideo").currentTime = Number(segment.start) || 0;
      syncTimelinePosition();
      $("sourceVideo").focus({ preventScroll: true });
    }); $("timeline").append(button);
  });
  renderTimelineRuler(meta.duration);
  renderSubtitleTrack(analysis.subtitleCues || [], Number(meta.duration || 0), analysis.subtitleState, analysis.subtitleMessage);
  syncTimelinePosition();
  hydrateTimelineThumbnails(data.sourceUrl || "", thumbnailImages, state.segments);
  $("transcriptInput").value = analysis.transcriptState ? analysis.transcript || "" : "";
  $("textForm").reset();
  $("directionConversation").replaceChildren();
  appendDirectionMessage("assistant", "What would you like to change?");
  $("confirmConversation").disabled = true;
  $("renderForm").hidden = false;
  if ($("briefForm")) { $("briefForm").reset(); $("briefForm").hidden = false; }
  $("textForm").hidden = true;
  resizeDirectionInput();
  renderCreativePlan(null);
  $("renderBtn").textContent = "Create video";
  setStep(1, false);
  ["renderStatus", "textStatus", "transcriptStatus", "briefStatus"].forEach(id => { if ($(id)) status(id, ""); });
  setStudioMode(true);
}
async function importVideo(form, link = false) {
  if (state.busy) return;
  if (state.jobId && (state.briefDirty || state.textDirty || state.notesDirty) && !window.confirm("Start a new video? Unsaved edits in this workspace will be replaced after the import succeeds.")) { $("fileInput").value = ""; return; }
  const loadingButton = $(link ? "analyzeBtn" : "uploadBtn");
  const idleLabel = link ? "Analyze" : "Upload video";
  busy(true);
  loadingButton.textContent = "Loading…";
  loadingButton.setAttribute("aria-busy", "true");
  status("importStatus", "");
  try { showAnalysis(await request("/api/import", { method: "POST", body: form })); status("importStatus", ""); }
  catch (error) { status("importStatus", error.message === "Failed to fetch" ? "Cannot connect to the local service. Make sure the server is running." : error.message, true); }
  finally {
    loadingButton.textContent = idleLabel;
    loadingButton.removeAttribute("aria-busy");
    busy(false);
    $("fileInput").value = "";
  }
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
$("textForm").addEventListener("submit", async event => {
  event.preventDefault(); if (state.busy || !state.jobId) return;
  const prompt = $("scriptPrompt").value.trim();
  if (!prompt) { status("textStatus", "Tell Pixfun what you want to refine.", true); $("scriptPrompt").focus(); return; }
  const reply = applyDirectionInstruction(prompt), draft = textValues();
  busy(true); $("textNext").textContent = "Sending…"; status("textStatus", "");
  try {
    await postJSON("/api/direction", { jobId: state.jobId, prompt, draft });
    appendDirectionMessage("user", prompt);
    appendDirectionMessage("assistant", reply);
    $("scriptPrompt").value = "";
    resizeChatInput();
    state.conversationReady = true; state.textConfirmed = false; state.notesDirty = false;
    state.textDirty = JSON.stringify(draft) !== state.renderedText;
    $("confirmConversation").disabled = false;
    status("textStatus", "");
  } catch (error) { status("textStatus", error.message, true); }
  finally { busy(false); $("textNext").textContent = "Send"; }
});
$("confirmConversation").addEventListener("click", () => {
  if (state.busy || !state.conversationReady) return;
  state.textConfirmed = true; status("textStatus", ""); setStep(2);
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
    setStep(2, false);
    status("renderStatus", "Ready. Select Original or Result to compare.");
    $("downloadLink").focus({ preventScroll: true });
    $("resultPreviewSlot").scrollIntoView({ block: "start", behavior: "instant" });
  } catch (error) { status("renderStatus", error.message, true); } finally { busy(false); $("renderBtn").textContent = state.outputUrl ? "Update video" : "Create video"; }
});
if ($("briefForm")) $("briefForm").addEventListener("submit", async event => {
  event.preventDefault(); if (!state.jobId || state.busy) return;
  const instruction = $("extraBrief").value.trim();
  if (!instruction) {
    status("briefStatus", "Describe at least one change, such as the presenter, language, product, setting, or script.", true);
    $("extraBrief").focus();
    return;
  }
  const brief = { material: "", person: "", dialogue: "", language: "keep", instructions: instruction };
  const form = new FormData(); form.append("jobId", state.jobId); form.append("brief", JSON.stringify(brief));
  busy(true); $("saveBrief").textContent = "Preparing…"; status("briefStatus", "");
  try {
    const data = await request("/api/brief", { method: "POST", body: form });
    state.references = data.references || []; state.briefSaved = true; state.briefDirty = false;
    renderCreativePlan(data.plan);
    status("briefStatus", "");
    resetDirectionConversation();
    $("briefForm").hidden = true;
    $("textForm").hidden = false;
    $("scriptPrompt").focus();
    syncStepNavigation();
  }
  catch (error) { status("briefStatus", error.message, true); }
  finally { busy(false); $("saveBrief").textContent = "Continue"; }
});
document.querySelectorAll("[data-studio-step]").forEach(button => button.addEventListener("click", () => { if (!state.busy && Number(button.dataset.studioStep) <= state.furthestStep) setStep(button.dataset.studioStep); }));
$("exportBack").addEventListener("click", () => setStep(1));
$("originalPreview").addEventListener("click", () => selectPreview(false));
$("resultPreview").addEventListener("click", () => selectPreview(true));
$("briefForm").addEventListener("input", () => {
  resizeDirectionInput();
  state.briefDirty = true; state.briefSaved = false;
  status("briefStatus", "");
});
$("sourceVideo").addEventListener("loadedmetadata", () => { renderTimelineRuler($("sourceVideo").duration); syncTimelinePosition(); });
$("sourceVideo").addEventListener("timeupdate", syncTimelinePosition);
$("sourceVideo").addEventListener("seeked", syncTimelinePosition);
$("sourceVideo").addEventListener("play", startTimelineMotion);
$("sourceVideo").addEventListener("pause", stopTimelineMotion);
$("sourceVideo").addEventListener("ended", stopTimelineMotion);
$("textForm").addEventListener("input", () => {
  resizeChatInput();
  state.textConfirmed = false;
  state.notesDirty = Boolean($("scriptPrompt").value.trim());
  status("textStatus", "");
  status("renderStatus", state.outputUrl ? "Direction changed. Send and confirm it to update the video." : "");
  syncStepNavigation();
});
$("backHome").addEventListener("click", () => { if (!state.busy) setStudioMode(false); });
$("changeVideo").addEventListener("click", () => { if (!state.busy) { setStudioMode(false); $("urlInput").focus(); } });
$("resumeStudio").addEventListener("click", () => { if (!state.busy) setStudioMode(true); });
document.querySelector(".header .brand").addEventListener("click", event => { if (document.body.classList.contains("studio-mode")) { event.preventDefault(); if (!state.busy) setStudioMode(false); } });
window.addEventListener("popstate", () => setStudioMode(location.hash === "#studio", false));
window.addEventListener("beforeunload", event => { if (state.briefDirty || state.textDirty || state.notesDirty || state.busy) { event.preventDefault(); event.returnValue = ""; } });
fetch("/api/health").then(response => response.json()).then(data => {
  $("engineText").textContent = data.tools.ffmpeg && data.tools.ffprobe ? (data.tools["yt-dlp"] ? "Local video engine ready" : "Local engine ready · Link imports require yt-dlp") : "Video engine unavailable · Install FFmpeg";
}).catch(() => { $("engineText").textContent = "Local service disconnected"; });
