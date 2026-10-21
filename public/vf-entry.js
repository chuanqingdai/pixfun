/* Catalog jobs enter the existing Pixfun studio without another analysis pass. */
(() => {
  const link = document.createElement('a');
  link.href = '/library'; link.className = 'button secondary'; link.textContent = '镜头库';
  document.querySelector('.header').append(link);
  const id = new URLSearchParams(location.search).get('vf_job');
  if (!id) return;
  (async () => {
    try {
      const response = await fetch('/api/vf/job?id=' + encodeURIComponent(id));
      const result = await response.json();
      if (!response.ok || !result.ok) throw new Error(result.error || '无法打开镜头');
      document.body.classList.remove('web-analysis-mode', 'library-mode');
      document.getElementById('webAnalysis').hidden = true;
      showAnalysis(result);
      const evidence = result.analysis.catalogEvidence;
      if(evidence) {
        const note = document.createElement('p'); note.id = 'catalogSourceNote';
        note.textContent = `原素材 ${evidence.start.toFixed(3)}–${evidence.end.toFixed(3)} 秒 · 转写沿用素材库，机器文字仍需核对` +
          (evidence.excludedTranscripts.length ? ` · ${evidence.excludedTranscripts.length} 段待复核转写未带入` : '');
        document.getElementById('sourceInfo').append(note);
      }
    } catch (error) {
      const message = document.createElement('p'); message.textContent = error.message;
      message.setAttribute('role', 'alert'); document.querySelector('.header').after(message);
    }
  })();
})();
