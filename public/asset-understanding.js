/* Presentation adapter. Only explicit model output is treated as semantic analysis. */
(() => {
  const metadata=typeof module!=='undefined'?require('./media-metadata.js'):window.PixfunMetadata;
  const labels={
    cameraMode:{drone:'Drone',pov:'POV',selfie:'Selfie',handheld:'Handheld',tripod:'Tripod',follow:'Follow shot',car:'Car-mounted',action_camera:'Action camera',timelapse:'Timelapse'},
    shotSize:{extreme_wide:'Extreme wide',wide:'Wide shot',medium:'Medium shot',close_up:'Close-up',extreme_close_up:'Extreme close-up'},
    cameraMotion:{static:'Static',push:'Push in',pull:'Pull out',pan:'Pan',tilt:'Tilt',follow:'Tracking',orbit:'Orbit',moving:'Moving'},
    shotRole:{establishing:'Establishing',action:'Action',detail:'Detail',character:'Character',reaction:'Reaction',transition:'Transition',highlight:'Highlight',ending:'Ending'},
    recommendedUse:{hook:'Opening hook',chapter_open:'Chapter opening',b_roll:'B-roll',transition:'Transition',climax:'Climax',ending:'Ending'}
  };
  const capturePaths={
    drone:['M9 9h6v6H9z','M9 9 5 5m10 4 4-4M9 15l-4 4m10-4 4 4','M7 4a3 3 0 1 0-3 3m13-3a3 3 0 1 1 3 3M4 17a3 3 0 1 0 3 3m10 0a3 3 0 1 0 3-3'],
    pov:['M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z','M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0'],
    selfie:['M8 2h8v20H8z','M14 9a2 2 0 1 1-4 0 2 2 0 0 1 4 0M9 16c0-4 6-4 6 0'],
    handheld:['M3 6h12v12H3zM15 10l6-3v10l-6-3'],
    tripod:['M5 3h14v9H5zM12 12v10m0-8-7 8m7-8 7 8'],
    follow:['M3 6h12v12H3zM18 8l4 4-4 4M9 9v6m-3-3h6'],
    car:['M4 10l2-6h12l2 6v8H4zM4 10h16M7 14h2m6 0h2M6 18v3m12-3v3'],
    action_camera:['M3 6h18v12H3zM16 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0M5 9h3'],
    timelapse:['M21 12a9 9 0 1 1-9-9','M12 7v5l4 2M16 3h5v5'],
    slow_motion:['M3 5v14l7-7-7-7Zm10 0v14l7-7-7-7Z']
  };
  const clean=value=>typeof value==='string'?value.replace(/\s+/g,' ').trim().slice(0,240):'';
  const list=value=>Array.isArray(value)?[...new Set(value.map(clean).filter(Boolean))].slice(0,12):[];
  const object=value=>value&&typeof value==='object'&&!Array.isArray(value)?value:{};
  const choice=(group,value)=>Object.hasOwn(labels[group],value)?value:null;
  const bool=value=>typeof value==='boolean'?value:null;
  const positive=value=>typeof value==='number'&&Number.isFinite(value)&&value>0?value:null;
  const score=value=>typeof value==='number'&&Number.isFinite(value)&&value>=0&&value<=100?Math.round(value<=1?value*100:value):null;
  function normalize(item,segment) {
    // A segment never inherits a whole-video semantic summary or role.
    const raw=object(segment?segment.assetUnderstanding:item.result?.analysis?.assetUnderstanding||item.assetUnderstanding);
    const m=item.metadata||{},capture=object(raw.capture),editing=object(raw.editing),quality=object(raw.quality),audio=object(raw.audio),location=object(raw.location);
    const suggested=object(editing.suggestedDuration),min=positive(suggested.min),max=positive(suggested.max),length=segment?segment.end-segment.start:m.duration;
    const longText=value=>typeof value==='string'?value.trim().slice(0,8000):'';
    const summary=(!segment&&longText(item.description))||longText(raw.summary),hasSummary=!!summary;
    const sceneSearch=segment?'':(item.result?.analysis?.segments||[]).map(s=>{
      const r=object(s.assetUnderstanding||item.result?.analysis?.sceneUnderstanding?.[s.id]),note=object(item.sceneNotes?.[s.id]);
      return [clean(note.title),clean(note.description),clean(r.title),longText(r.summary),...['subjects','objects','scene','actions','visibleText','keywords'].flatMap(key=>list(r[key]))].join(' ');
    }).join(' ');
    return {
      id:item.id,filename:item.file.name,title:clean(item.title)||clean(m.title)||item.file.name.replace(/\.[^.]+$/,''),kind:item.kind,summary,analyzed:hasSummary||Object.keys(capture).length>0||Object.keys(editing).length>0,
      duration:length,width:m.width,height:m.height,fps:m.fps,hasAudio:bool(m.hasAudio),camera:clean(item.context?.device)||clean(m.camera),capturedAt:metadata.dateText(m.capturedAt),mediaCreatedAt:metadata.dateText(m.mediaCreatedAt),
      orientation:m.width&&m.height?(m.width>m.height?'Landscape':m.width<m.height?'Portrait':'Square'):'',
      subjects:list(raw.subjects),scene:list(raw.scene),actions:list(raw.actions),location:[clean(item.context?.location),clean(m.location),clean(location.poi),clean(location.city),clean(location.country)].filter(Boolean),
      objects:list(raw.objects),visualStyle:list(raw.visualStyle),visibleText:list(raw.visibleText),uncertainties:list(raw.uncertainties),keywords:list(raw.keywords),sceneSearch,
      capture:{cameraMode:choice('cameraMode',capture.cameraMode),shotSize:choice('shotSize',capture.shotSize),cameraMotion:choice('cameraMotion',capture.cameraMotion),slowMotion:bool(capture.slowMotion)},
      editing:{shotRole:choice('shotRole',editing.shotRole),importance:typeof editing.importance==='number'&&editing.importance>=0&&editing.importance<=1?editing.importance:null,recommendedUse:choice('recommendedUse',editing.recommendedUse),suggestedDuration:min&&max&&min<=max&&(!length||max<=length)?{min,max}:null},
      quality:{overall:score(quality.overall),sharpness:score(quality.sharpness),stability:score(quality.stability),exposure:score(quality.exposure),composition:score(quality.composition),issues:list(quality.issues)},
      audio:{hasSpeech:bool(audio.hasSpeech),speechText:typeof audio.speechText==='string'?audio.speechText.slice(0,30000):'',hasUsefulAmbientSound:bool(audio.hasUsefulAmbientSound),ambientTypes:list(audio.ambientTypes),audioQuality:score(audio.audioQuality),issues:list(audio.issues)},
      subtitleCues:(item.result?.analysis.subtitleCues||[]).filter(c=>!segment||(c.start<segment.end&&c.end>segment.start))
    };
  }
  function resolution(asset){const edge=Math.min(asset.width||0,asset.height||0);return edge>=2160?'4K':edge>=1080?'1080p':edge>=720?'HD':edge>0?`${edge}p`:'';}
  function discoveryTags(asset) {
    const date=asset.capturedAt?.slice(0,10).replaceAll(':','-');
    // Prefer searchable context; never infer a location or subject from a filename.
    const candidates=[asset.camera,asset.location[0],date,asset.scene[0],asset.subjects[0]];
    return [...new Set(candidates.filter(Boolean))].slice(0,2);
  }
  function buildAssetCard(asset) {
    const capture=asset.capture,editing=asset.editing;
    const highlight=editing.importance!==null&&editing.importance>0.85;
    const tags=[labels.shotSize[capture.shotSize],labels.cameraMotion[capture.cameraMotion],highlight?'Highlight':null].filter(Boolean).slice(0,3);
    const audio=asset.audio.hasSpeech===true?'Dialogue':asset.audio.hasUsefulAmbientSound===true?'Useful ambience':asset.audio.hasSpeech===false?'No dialogue':asset.hasAudio===false?'Silent':asset.subtitleCues.length?'Subtitles':asset.hasAudio===true?'Audio':null;
    return {
      title:asset.title,summary:asset.summary&&asset.summary!==asset.title?asset.summary:'',
      summaryMissing:!asset.summary,captureKey:capture.cameraMode||(capture.slowMotion?'slow_motion':null),
      captureLabel:labels.cameraMode[capture.cameraMode]||(capture.slowMotion?'Slow motion':''),
      primaryRole:labels.shotRole[editing.shotRole]||'',tags,discoveryTags:discoveryTags(asset),highlight,
      status:[resolution(asset),asset.fps>=50?`${Math.round(asset.fps)} fps`:null,audio].filter(Boolean).slice(0,3),
      warning:asset.quality.issues[0]||asset.audio.issues[0]||'',duration:asset.duration
    };
  }
  const groupNames={content:'Content',scene:'Scene / event',capture:'Capture',shot:'Shot',editing:'Edit use',quality:'Quality / audio'};
  function facets(asset){return {
    content:asset.subjects,scene:[...asset.scene,...asset.actions],
    capture:[labels.cameraMode[asset.capture.cameraMode],asset.capture.slowMotion?'Slow motion':null].filter(Boolean),
    shot:[labels.shotSize[asset.capture.shotSize],labels.cameraMotion[asset.capture.cameraMotion]].filter(Boolean),
    editing:[labels.shotRole[asset.editing.shotRole],labels.recommendedUse[asset.editing.recommendedUse],asset.editing.importance>0.85?'Highlight':null].filter(Boolean),
    quality:[asset.quality.overall>=80?'High quality':null,asset.audio.hasSpeech===true?'Dialogue':asset.audio.hasSpeech===false?'No dialogue':null,asset.audio.hasUsefulAmbientSound===true?'Useful ambience':null,asset.hasAudio===false?'Silent':asset.hasAudio===true?'Audio':null,asset.subtitleCues.length?'Subtitles':null,...asset.quality.issues,...asset.audio.issues].filter(Boolean)
  };}
  function searchText(asset){return [asset.title,asset.filename,asset.summary,asset.orientation,asset.camera,resolution(asset),asset.fps?`${asset.fps} fps`:'',asset.capturedAt?.slice(0,10).replaceAll(':','-'),asset.mediaCreatedAt?.slice(0,10).replaceAll(':','-'),...asset.location,...Object.values(facets(asset)).flat(),...asset.objects,...asset.visualStyle,...asset.visibleText,...asset.keywords,asset.sceneSearch,asset.audio.speechText,...asset.subtitleCues.map(c=>c.text)].join(' ').toLowerCase();}
  function detailSections(asset){
    const unique=values=>[...new Set(values.filter(Boolean))];
    const tags=[
      ['Scene',unique([...asset.scene,...asset.keywords])],
      ['Subjects',unique([...asset.subjects,...asset.objects])],
      ['Action',asset.actions],['Look',asset.visualStyle],['Visible text',asset.visibleText],
      ['Location',unique(asset.location)],['Camera',asset.camera?[asset.camera]:[]],
      ['Shot on',asset.capturedAt?[asset.capturedAt.slice(0,10).replaceAll(':','-')]:[]]
    ].filter(([,values])=>values.length);
    const use=asset.editing;
    const editing=[['Story role',labels.shotRole[use.shotRole]],['Use as',labels.recommendedUse[use.recommendedUse]],['Suggested cut',use.suggestedDuration?`${use.suggestedDuration.min}–${use.suggestedDuration.max} sec`:null],['Shot size',labels.shotSize[asset.capture.shotSize]],['Movement',labels.cameraMotion[asset.capture.cameraMotion]],['Capture',labels.cameraMode[asset.capture.cameraMode]],['Slow motion',asset.capture.slowMotion===true?'Detected':null]].filter(([,value])=>value);
    const cautions=unique([...asset.quality.issues,...asset.audio.issues,...asset.uncertainties]);
    const hasContent=!!asset.summary||[asset.scene,asset.subjects,asset.objects,asset.actions,asset.visualStyle,asset.visibleText,asset.keywords].some(values=>values.length);
    return {summary:asset.summary,tags,editing,cautions,hasContent};
  }
  function compactDescription(value,limit=240){
    const text=String(value||'').replace(/\s+/g,' ').trim();if(text.length<=limit)return text;
    const head=text.slice(0,limit),sentence=Math.max(head.lastIndexOf('. '),head.lastIndexOf('。'),head.lastIndexOf('! '),head.lastIndexOf('? '));
    if(sentence>limit*.45)return head.slice(0,sentence+1);
    const word=head.lastIndexOf(' ');return head.slice(0,word>limit*.7?word:limit).trimEnd()+'…';
  }
  function editingOverview(item,segment){
    const asset=normalize(item,segment),analysis=item.result?.analysis||{};
    const join=values=>[...new Set(values.filter(Boolean))].join(' · ');
    const rows=[['On screen',join([...asset.scene,...asset.subjects,...asset.objects])],['Action',join(asset.actions)],['Framing',labels.shotSize[asset.capture.shotSize]],['Camera movement',labels.cameraMotion[asset.capture.cameraMotion]],['Look',join(asset.visualStyle)]].filter(([,value])=>value);
    // Preserve authored / model-generated structured briefs, without inventing recommendations.
    const structured=asset.summary.split(/\n+/).map(line=>line.match(/^(Theme|Key shots|Suggested use|Watch out):\s*(.+)$/i)).filter(Boolean);
    let summary=asset.summary,fullSummary=asset.summary;const editingNotes=[];
    if(structured.length>=2){
      summary=structured.find(row=>row[1].toLowerCase()==='theme')?.[2]||'';
      for(const row of structured){const label=row[1][0].toUpperCase()+row[1].slice(1).toLowerCase();if(row[1].toLowerCase()==='key shots')rows.push([label,row[2]]);else if(row[1].toLowerCase()!=='theme')editingNotes.push([label,row[2]]);}
      fullSummary=[summary,...structured.filter(row=>row[1].toLowerCase()==='key shots').map(row=>row[2])].filter(Boolean).join('\n');
    }
    const candidates=(segment?[segment]:analysis.segments||[]).filter(s=>Number.isFinite(s.start)&&Number.isFinite(s.end)&&s.start>=0&&s.end>s.start).map(s=>{
      const raw=s.assetUnderstanding||analysis.sceneUnderstanding?.[s.id]||{},note=item.sceneNotes?.[s.id]||{};
      return {start:s.start,title:clean(note.title)||clean(raw.title)||list(raw.scene).join(' · '),text:clean(note.description)||clean(raw.summary),source:note.title||note.description?'Saved note':'Visual analysis'};
    }).filter(s=>s.title||s.text).sort((a,b)=>a.start-b.start);
    const spread=values=>values.length<=3?values:[values[0],values[Math.floor((values.length-1)/2)],values[values.length-1]];
    // Visual descriptions and scene notes never fall back to speech or subtitles.
    const moments=spread(candidates),momentLabel='Scene notes';
    return {summary:compactDescription(summary),fullSummary,editingNotes,source:!segment&&item.description?'Saved description':summary?'Visual analysis':'',rows:rows.map(([label,value])=>[label,compactDescription(value,180)]),moments:moments.map(row=>({...row,text:compactDescription(row.text,180)})),momentLabel,hasVisualContent:!!summary||rows.length>0};
  }
  function matches(asset,filters,query=''){
    if(!query.toLowerCase().trim().split(/\s+/).every(term=>searchText(asset).includes(term)))return false;
    if(![...Object.keys(groupNames),'resolution','orientation','device','location'].every(key=>!filters[key]||facetValues(asset,key).includes(filters[key])))return false;
    const date=(asset.capturedAt||'').slice(0,10).replaceAll(':','-');
    if(filters.dateFrom&&(!date||date<filters.dateFrom))return false;
    if(filters.dateTo&&(!date||date>filters.dateTo))return false;
    return true;
  }
  function facetValues(asset,key){
    const extra={resolution:[resolution(asset)],orientation:[asset.orientation],device:[asset.camera],location:asset.location};
    return [...new Set((extra[key]||facets(asset)[key]||[]).filter(Boolean))];
  }
  function relatedOptions(assets,filters,query,key){
    // Match all other groups before counting this group's available alternatives.
    const other={...filters};delete other[key];const counts=new Map();
    for(const asset of assets){if(!matches(asset,other,query))continue;for(const value of facetValues(asset,key))counts.set(value,(counts.get(value)||0)+1);}
    if(filters[key]&&!counts.has(filters[key]))counts.set(filters[key],0);
    return [...counts].map(([value,count])=>({value,count})).sort((a,b)=>b.count-a.count||a.value.localeCompare(b.value));
  }
  function description(asset,segmentCount=0){
    if(asset.summary)return asset.summary;
    const parts=[];
    if(asset.kind==='video'&&asset.duration>0)parts.push(`${Math.floor(asset.duration)}-second ${asset.orientation?asset.orientation.toLowerCase()+' ':''}video.`);
    else if(asset.orientation)parts.push(`${asset.orientation} ${asset.kind==='image'?'photo':'video'}.`);
    if(segmentCount>0)parts.push(`${segmentCount} scene segments available.`);
    if(asset.hasAudio===false)parts.push('No audio track.');
    else if(asset.hasAudio===true)parts.push('Includes audio.');
    if(asset.subtitleCues.length)parts.push(`${asset.subtitleCues.length} subtitle entries available.`);
    return parts.join(' ')||'Add a description for this file.';
  }
  const api={labels,capturePaths,groupNames,normalize,buildAssetCard,resolution,facets,searchText,matches,facetValues,relatedOptions,description,detailSections,compactDescription,editingOverview};
  if(typeof module!=='undefined')module.exports=api;else window.PixfunAssets=api;
})();
