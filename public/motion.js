/* Deterministic, reversible scroll choreography. No wheel interception or timers. */
"use strict";
const clamp01 = value => Math.max(0, Math.min(1, value));
const smoothRange = (value, start, end) => {
  const t = clamp01((value - start) / (end - start));
  return t * t * (3 - 2 * t);
};
function sceneState(progress) {
  const p = clamp01(progress);
  const analysis = smoothRange(p, .09, .23);
  const brief = smoothRange(p, .31, .43);
  const edit = smoothRange(p, .56, .68);
  const finish = smoothRange(p, .80, .94);
  return {
    chapter: Math.min(4, Math.floor(p * 4 + .5)),
    width: .86 - .08 * analysis - .12 * brief - .06 * edit - .23 * finish,
    height: .60 - .14 * analysis + .04 * brief + .02 * edit + .31 * finish,
    x: .50 - .05 * analysis - .08 * brief + .16 * finish,
    y: .50 - .16 * analysis + .09 * brief + .03 * finish,
    rotate: 2 * (1 - analysis),
    source: 1 - analysis,
    timeline: analysis * (1 - brief),
    // Panels leave completely before the next one enters. A paused scroll
    // must never leave two translucent sets of text stacked together.
    brief: brief * (1 - smoothRange(p, .565, .61)),
    edit: smoothRange(p, .635, .68) * (1 - smoothRange(p, .83, .87)),
    caption: smoothRange(p, .635, .68),
    // A clean shot change avoids superimposing two different presenters.
    person: p >= .625 ? 1 : 0,
    export: smoothRange(p, .89, .94),
    finish,
  };
}
// Size the media independently of the wide stage, reserving space for the side card.
function sceneGeometry(progress, stageWidth, stageHeight) {
  const p = clamp01(progress);
  const analysis = smoothRange(p, .09, .23);
  const brief = smoothRange(p, .31, .43);
  const finish = smoothRange(p, .80, .94);
  const cardWidth = Math.min(310, Math.max(260, stageWidth * .36));
  const available = stageWidth - cardWidth - 28;
  const sourceHeight = Math.min(stageHeight - 108, stageWidth * .78 * 9 / 16 + 64);
  const analysisHeight = Math.min(sourceHeight, stageHeight - 250);
  const editHeight = Math.min(stageHeight - 62, Math.max(100, available) * 9 / 16 + 64);
  const landscapeHeight = sourceHeight + (analysisHeight - sourceHeight) * analysis + (editHeight - analysisHeight) * brief;
  const finalHeight = stageHeight - 58;
  const height = landscapeHeight + (finalHeight - landscapeHeight) * finish;
  const width = (landscapeHeight - 64) * 16 / 9 * (1 - finish) + (finalHeight - 64) * 9 / 16 * finish;
  const x = stageWidth / 2 + (available / 2 - stageWidth / 2) * brief * (1 - finish);
  const cardTop = 24;
  const sourceY = stageHeight * .55 + (cardTop + analysisHeight / 2 - stageHeight * .55) * analysis;
  const editY = cardTop + landscapeHeight / 2;
  const y = (sourceY + (editY - sourceY) * brief) * (1 - finish) + stageHeight * .5 * finish;
  return { width, height, x, y, cardWidth, cardTop };
}
if (typeof module !== "undefined") module.exports = { sceneState, sceneGeometry, clamp01, smoothRange };
if (typeof document !== "undefined") (() => {
  const story = document.getElementById("story");
  const sticky = story.querySelector(".story-sticky");
  const stage = document.getElementById("stage");
  const frame = document.getElementById("mediaFrame");
  const originalScene = document.getElementById("originalScene");
  const replacementScene = document.getElementById("replacementScene");
  const replacementBadge = document.getElementById("replacementBadge");
  const chapters = [...document.querySelectorAll("[data-chapter]")];
  const navigation = [...document.querySelectorAll("[data-go]")];
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  // Keep the pinned story available in normal MacBook browser windows. The
  // previous 800px height gate disabled it on common 13–14 inch displays.
  const desktop = matchMedia("(min-width: 900px) and (min-height: 650px)");
  const labels = ["01 — Reference", "02 — Deconstruct", "03 — Replace", "04 — Rebuild", "05 — Export"];
  const layers = Object.fromEntries(["sourceBadge", "demoTimeline", "briefCard", "editCard", "exportCard", "demoCaption", "originalBadge", "playhead", "ratioLabel", "sceneLabel"].map(id => [id, document.getElementById(id)]));
  let enabled = false, scheduled = false, start = 0, distance = 1, width = 1, height = 1, chapter = -1, staticChapter = 0;
  function opacity(element, amount, shift = 22) {
    element.style.opacity = amount;
    element.style.visibility = amount > 0 ? "visible" : "hidden";
    element.setAttribute("aria-hidden", String(amount <= 0));
    element.style.transform = `translate3d(0,${(1 - amount) * shift}px,0)`;
  }
  function render(p) {
    const s = sceneState(p);
    const geometry = sceneGeometry(p, width, height);
    frame.style.width = `${geometry.width}px`;
    frame.style.height = `${geometry.height}px`;
    frame.style.left = `${geometry.x}px`;
    frame.style.top = `${geometry.y}px`;
    frame.style.transform = "translate(-50%,-50%)";
    opacity(layers.sourceBadge, s.source, -20);
    opacity(layers.demoTimeline, s.timeline, 32);
    opacity(layers.briefCard, s.brief, 25);
    opacity(layers.editCard, s.edit, 25);
    opacity(layers.exportCard, s.export, 12);
    opacity(layers.demoCaption, s.caption, 8);
    layers.originalBadge.style.opacity = 1 - s.person;
    layers.originalBadge.setAttribute("aria-hidden", String(s.person === 1));
    replacementScene.style.opacity = s.person;
    replacementBadge.style.opacity = s.person;
    replacementBadge.setAttribute("aria-hidden", String(s.person === 0));
    originalScene.setAttribute("aria-hidden", String(s.person >= .5));
    replacementScene.setAttribute("aria-hidden", String(s.person < .5));
    // The preview shows Scene 02 at 00:08, so the playhead stays inside the
    // matching second clip instead of drifting onto a different thumbnail.
    layers.playhead.style.left = "25%";
    layers.ratioLabel.textContent = s.finish > .5 ? "9:16" : "16:9";
    if (chapter !== s.chapter) {
      chapter = s.chapter;
      chapters.forEach((element, i) => {
        element.classList.toggle("active", i === chapter);
        element.setAttribute("aria-hidden", String(i !== chapter));
        element.inert = i !== chapter;
      });
      navigation.forEach((button, i) => i === chapter ? button.setAttribute("aria-current", "step") : button.removeAttribute("aria-current"));
      layers.sceneLabel.textContent = labels[chapter];
    }
  }
  function draw() {
    scheduled = false;
    if (!enabled) return;
    render(clamp01((scrollY - start) / distance));
  }
  function schedule() { if (enabled && !scheduled) { scheduled = true; requestAnimationFrame(draw); } }
  function measure() {
    enabled = desktop.matches && !reduced.matches && !document.body.classList.contains("studio-mode");
    story.classList.toggle("motion-enabled", enabled);
    chapter = -1;
    if (enabled) {
      const bounds = story.getBoundingClientRect();
      // The compact sticky canvas no longer fills the viewport. Map the full
      // story to its actual pinned travel, including its centered top inset.
      const pinnedTop = parseFloat(getComputedStyle(sticky).top) || 0;
      start = scrollY + bounds.top - pinnedTop;
      distance = Math.max(1, bounds.height - sticky.offsetHeight);
      width = stage.clientWidth; height = stage.clientHeight;
      schedule();
    } else {
      frame.removeAttribute("style");
      replacementScene.removeAttribute("style");
      replacementBadge.removeAttribute("style");
      originalScene.removeAttribute("aria-hidden");
      replacementScene.removeAttribute("aria-hidden");
      Object.values(layers).forEach(element => { element.removeAttribute("style"); element.removeAttribute("aria-hidden"); });
      width = stage.clientWidth; height = stage.clientHeight;
      // Reduced-motion and compact windows keep the same five-step story as
      // an explicit, click-driven demo instead of exposing every layer at once.
      render(staticChapter / 4);
    }
  }
  navigation.forEach(button => button.addEventListener("click", () => {
    const target = Number(button.dataset.go);
    if (enabled) scrollTo({ top: start + distance * target / 4, behavior: "smooth" });
    else {
      staticChapter = target;
      chapter = -1;
      width = stage.clientWidth; height = stage.clientHeight;
      render(staticChapter / 4);
    }
  }));
  addEventListener("scroll", schedule, { passive: true });
  addEventListener("resize", measure, { passive: true });
  addEventListener("load", measure);
  reduced.addEventListener("change", measure);
  desktop.addEventListener("change", measure);
  document.addEventListener("pixfun:viewchange", measure);
  // Import results can increase document height above the sticky section.
  new ResizeObserver(measure).observe(document.querySelector("main"));
  new ResizeObserver(measure).observe(stage);
  measure();
})();
