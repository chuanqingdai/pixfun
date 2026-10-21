(() => {
  'use strict';
  const $ = id => document.getElementById(id), pageSize = 48;
  let offset = 0, activeShot = null, queryVersion = 0, detailVersion = 0, preparing = false;
  const el = (tag, text, cls) => { const n = document.createElement(tag); if(text !== undefined) n.textContent = text; if(cls) n.className = cls; return n; };
  const time = n => { const ms = Math.round(n * 1000); return `${String(Math.floor(ms / 60000)).padStart(2,'0')}:${String(Math.floor(ms / 1000) % 60).padStart(2,'0')}.${String(ms % 1000).padStart(3,'0')}`; };
  const frame = id => '/api/vf/frame/' + encodeURIComponent(id);
  const button = (text, fn) => { const b = el('button', text); b.type = 'button'; b.onclick = fn; return b; };
  async function api(path, options) {
    const response = await fetch('/api/vf/' + path, options), result = await response.json();
    if(!response.ok || !result.ok) throw new Error(result.error || '服务暂时不可用');
    return result;
  }
  function notice(text, error = false) { $('notice').textContent = text; $('notice').classList.toggle('error', error); }
  function image(id) { const n = el('img'); n.loading = 'lazy'; n.alt = '镜头画面'; n.src = frame(id); return n; }
  function score(row, name) { const n = row.scores?.[name]?.max; return Number.isFinite(n) ? n.toFixed(2) : '未评分'; }
  async function status() {
    const data = await api('status');
    $('counts').textContent = `${data.counts.assets} 个文件 · ${data.counts.shots} 个镜头 · ${data.counts.transcripts} 段转写`;
    const select = $('search').elements.tag, previous = select.value;
    select.replaceChildren(new Option('全部标签', ''));
    for(const tag of data.tags) select.add(new Option(tag, tag));
    select.value = previous;
  }
  function card(row) {
    const c = el('article', undefined, 'card'); c.dataset.shotId = row.id;
    const fid = row.match?.match_frame_id || row.representative;
    const cover = button('', () => preview(row)); cover.className = 'cover'; cover.setAttribute('aria-label', '预览 ' + row.asset);
    if(fid) cover.append(image(fid)); else cover.append(el('p', '暂无缓存封面'));
    cover.append(el('span', `${time(row.start)}–${time(row.end)}`, 'time'));
    const body = el('div', undefined, 'card-body');
    body.append(el('h2', row.context.place || '地点待确认'), el('p', row.asset, 'filename'));
    body.append(el('p', row.context.note || '', 'context'));
    const tags = el('div', undefined, 'tags');
    for(const tag of [...new Set(row.tags.map(t => t.tag))]) {
      const b = button(tag, () => { $('search').elements.tag.value = tag; search(0); });
      b.title = row.tags.filter(t => t.tag === tag).map(t => t.origin).join(' / '); tags.append(b);
    }
    body.append(tags, el('p', `美感 ${score(row, 'beauty')} · ${row.cover_choice?.locked ? '人工锁定封面' : '自动封面'}${row.online ? '' : ' · 原片离线'}`, 'meta'));
    if(row.frames.some(f => f.frame_id === fid && f.display_profile)) body.append(el('p', 'HDR 封面显示已修复 · 评分来自原扫描', 'meta'));
    if(row.match?.match_t !== undefined) body.append(el('p', `画面命中 ${time(row.match.match_t)} · 相关度 ${row.match.similarity.toFixed(3)}`, 'meta'));
    const actions = el('div', undefined, 'actions'), panel = el('div', undefined, 'similar'); panel.hidden = true;
    const similar = button('相似镜头', async () => {
      panel.hidden = !panel.hidden; similar.setAttribute('aria-expanded', String(!panel.hidden));
      if(panel.hidden || panel.childElementCount) return;
      similar.disabled = true;
      try {
        const data = await api('search?' + new URLSearchParams({similar: row.id, k: 6}));
        panel.append(el('p', '按画面相似度排列，不代表质量或同一人物。'));
        for(const hit of data.shots) {
          const b = button('', () => preview(hit)), id = hit.match?.match_frame_id || hit.representative;
          if(id) b.append(image(id));
          b.append(el('span', `${hit.context.place || hit.asset} · ${time(hit.match?.match_t ?? hit.start)}`)); panel.append(b);
        }
        if(!data.shots.length) panel.append(el('p', '暂无其他可比较镜头。'));
      } catch(e) { notice(e.message, true); } finally { similar.disabled = false; }
    });
    similar.setAttribute('aria-expanded', 'false'); actions.append(button('预览与详情', () => preview(row)), similar);
    body.append(actions, panel); c.append(cover, body); return c;
  }
  async function search(next = 0) {
    const version = ++queryVersion, params = new URLSearchParams(new FormData($('search')));
    params.set('k', String(pageSize + 1)); params.set('offset', String(next));
    notice(params.get('q') && params.get('mode') !== 'text' ? '正在检索，首次画面语义搜索需加载本地模型…' : '正在读取镜头…');
    $('prev').disabled = true; $('next').disabled = true;
    try {
      const data = await api('search?' + params); if(version !== queryVersion) return;
      offset = next; $('grid').replaceChildren(...data.shots.slice(0, pageSize).map(card));
      $('prev').disabled = offset === 0; $('next').disabled = data.shots.length <= pageSize;
      $('page').textContent = `第 ${Math.floor(offset / pageSize) + 1} 页`;
      notice(data.shots.length ? `本页 ${Math.min(data.shots.length, pageSize)} 个镜头` : '没有匹配的镜头，试试其他关键词或检索方式。');
      window.scrollTo({top: 0, behavior: 'instant'});
    } catch(e) { if(version === queryVersion) { $('grid').replaceChildren(); notice(e.message, true); } }
  }
  function details(label, value) { const d = el('details'); d.append(el('summary', label), el('pre', JSON.stringify(value, null, 2))); return d; }
  async function preview(row) {
    const version = ++detailVersion; activeShot = null;
    const video = $('detail').querySelector('video'); video.pause(); video.removeAttribute('src'); video.load();
    $('detailTitle').textContent = row.context.place || row.asset;
    $('facts').replaceChildren(); $('useNotice').textContent = ''; $('playbackNotice').textContent = '正在读取镜头详情…';
    $('useShot').disabled = true; if(!$('detail').open) $('detail').showModal();
    try {
      const shot = (await api('shot?' + new URLSearchParams({shot_id: row.id}))).shot;
      if(version !== detailVersion || !$('detail').open) return;
      activeShot = shot;
      const start = (row.match?.match_t ?? shot.start) + shot.playback.origin, end = shot.playback.end;
      video.onloadedmetadata = () => { video.currentTime = start; };
      video.ontimeupdate = () => { if(video.currentTime >= end) video.pause(); };
      video.onerror = () => { $('playbackNotice').textContent = '视频不可播放：原片可能离线、已变化或编码不受浏览器支持。'; };
      video.poster = shot.representative ? frame(shot.representative) : '';
      if(shot.online) video.src = '/api/vf/video/' + encodeURIComponent(shot.id) + `#t=${start},${end}`;
      $('playbackNotice').textContent = `${shot.asset} · 原片 ${time(shot.start)}–${time(shot.end)}${shot.online ? '' : ' · 原片离线'}`;
      const facts = el('div', undefined, 'facts');
      facts.append(el('p', `地点：${shot.context.place || '待确认'}`), el('p', `日期：${shot.context.date || '待确认'}`));
      $('facts').append(facts, details('分数、候选和镜头元信息', {scores:shot.scores, context:shot.context, candidates:shot.candidates, metadata:shot.metadata, cover_choice:shot.cover_choice}));
      const transcript = el('details'); transcript.open = true; transcript.append(el('summary', `转写 · ${shot.transcript_segments.length} 段`));
      for(const s of shot.transcript_segments) {
        const block = el('blockquote'); block.append(el('p', `${time(s.overlap_start)}–${time(s.overlap_end)}`));
        if(!s.searchable || s.timing_status === 'legacy_clock_unverified') {
          block.append(el('p', '待复核，不带入剪辑文本', 'warn'), details('查看原识别', {text:s.text, reason:s.review_reason, timing:s.timing_status}));
        } else block.append(el('p', s.text), el('p', s.human_verified ? '有人工核对记录' : '机器转写，未经逐句人工核对', 'meta'));
        transcript.append(block);
      }
      $('facts').append(transcript); $('useShot').disabled = !shot.online || preparing || shot.end - shot.start > 600;
    } catch(e) { $('playbackNotice').textContent = e.message; }
  }
  $('useShot').onclick = async () => {
    if(!activeShot || preparing) return;
    const shotId = activeShot.id; preparing = true; $('useShot').disabled = true;
    $('useNotice').textContent = '正在准备这个镜头的编辑副本（单任务、2 线程）…';
    try {
      const data = await api('use-shot', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({shot_id:shotId})});
      location.href = '/?vf_job=' + encodeURIComponent(data.jobId) + '#studio';
    } catch(e) { $('useNotice').textContent = e.message; } finally { preparing = false; $('useShot').disabled = !activeShot?.online; }
  };
  $('close').onclick = () => $('detail').close();
  $('detail').addEventListener('close', () => { ++detailVersion; activeShot = null; const v = $('detail').querySelector('video'); v.pause(); v.removeAttribute('src'); v.load(); });
  $('search').onsubmit = e => { e.preventDefault(); search(0); };
  $('clear').onclick = () => { $('search').reset(); search(0); };
  $('prev').onclick = () => search(Math.max(0, offset - pageSize)); $('next').onclick = () => search(offset + pageSize);
  $('reload').onclick = () => status().then(() => search(offset)).catch(e => notice(e.message, true));
  status().then(() => search(0)).catch(e => notice(e.message, true));
})();
