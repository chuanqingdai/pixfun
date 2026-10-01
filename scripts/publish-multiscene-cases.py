"""Publish reviewed local-model drafts, verified cuts and ASR/source-caption corrections.

Public records use the Mac editorial schema; English display copy is localized.
Reviews are explicit human/editorial judgments, not unreviewed model assertions.
"""
import difflib, json, re, subprocess, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from shot_analysis import stamp, validate_shot
from video_description import validate_description
DATA=ROOT/'data/landing-cases-v2'; OUT=ROOT/'public/media/cases/v3'

def shot(end,title,description,size,capture,motion,role,level,duration,reason,connect='',caution='',reaction='',score=75):
    return dict(end=end,title=title,description=description,size=size,capture=capture,motion=motion,role=role,recommendation=level,useDuration=duration,reason=reason,connect=connect,caution=caution,reaction=reaction,importance_score=score)

REVIEWS={
 'alpine':dict(
  title="Wild Alaska",
  full_description='棕熊在浅水中进食，海鸟在旁走动；镜头随后升到森林上方，沿弯曲河道展示林地与苔原，再转向云雾中的陡峭雪山、蓝色湖湾和覆雪火山。旁白将动物获取食物与阿拉斯加的地貌连接起来，叙事由生命细节扩展到广阔环境。棕熊进食和明亮雪峰最有保留价值，航拍适合建立空间或作为章节高潮；可压缩相似山景的停留，不应把不同机位误写为同一次连续飞行。',
  description="A feeding brown bear gives way to winding rivers, blue lakes and snow-covered peaks. Original narration connects wildlife with the landscape; the bright mountain reveal is the visual payoff.",
  subjects=['Brown bear','Shore birds'],tags=['Alaska','Wildlife','Snow peaks','Aerial landscape'],
  highlightReason='Bright snow, a clearly defined summit and blue sky create the strongest landscape reveal, without titles or graphics.',
  context='Continuous excerpt from the NPS Lake Clark film (2018). Original narration preserved; no added graphics. Not unedited camera footage. No NPS endorsement.',
  reference='alaska-reference.vtt',
  shots=[
   shot(10.9,'A bear at the water','A brown bear eats in shallow water while pale birds approach and pass in front of it. The animal briefly turns its head before returning to the food.','Medium','Shore-level wildlife view','Mostly fixed framing','Action / wildlife detail','Keep',6,'Retain an eating movement and the head turn to establish an active subject.','Open out to the habitat from above.','Do not infer the animal’s emotion or identify an individual.',score=92),
   shot(19.38,'Follow the river','An elevated moving view follows a winding reddish river through dense green trees; open tundra becomes visible beyond the forest.','Wide','Aerial','Forward travel','Habitat / scale','Recommended',5,'Keep the river bend and the change from forest to open terrain.','Cut from the river’s curve to the mountain ridgeline.',score=85),
   shot(29.1,'Into the cloud','Dark rock walls and bands of snow fill a steep mountain face. Cloud brushes the upper ridge as the elevated viewpoint moves alongside it.','Wide','Aerial','Lateral travel','Transition / dramatic scale','Recommended',5,'Keep the section where cloud reveals the ridgeline; shorten similar rock textures.','Reveal the lake and distant range next.',score=86),
   shot(39.7,'The lake opens out','A blue lake and projecting wooded landform spread across the foreground, with a long line of snow-covered mountains behind.','Extreme wide','Aerial','Slow forward drift','Place / reveal','Keep',5,'Hold the clean wide composition to connect water and mountains.','Move closer to a bright snow-covered summit.',score=90),
   shot(46.54,'A summit in sunlight','A bright snow-covered volcanic peak dominates the frame. Dark ridges and crevasses become clearer as the viewpoint moves past its slopes.','Wide','Aerial','Gliding lateral view','Highlight / climax','Keep',6,'Use the full reveal; the strong snow-and-sky contrast makes it readable even at preview size.','Finish by opening back out to the wider mountain range.',score=96),
   shot('end','Return to the whole range','A distant snowy summit sits above a darker mountain range and blue water, returning the scene to a broad landscape view.','Extreme wide','Aerial','Gentle drift','Resolution / ending','Recommended',3,'Keep the final landscape and let the sentence finish.','Close the chapter or transition to a new location.',score=84)
  ]),
 'citywalk':dict(
  title="Tokyo after dark",
  full_description='城市在暮色中逐渐亮灯，高处视角展示东京塔与密集楼群；随后降到暖黄色灯光的街头，行人穿过斑马线，有人停留交谈；最后靠近红、蓝、绿交织的霓虹招牌，以颜色和建筑细节收尾。三个独立来源镜头形成由城市全貌到街头活动再到局部细节的结构，适合旅行夜游段落。保留入夜的光线变化和清楚的人物经过，压缩重复步行与招牌停留；店招是实景而非添加字幕，素材无音轨。',
  description="Tokyo lights up at dusk, pedestrians cross a warm-lit street, and neon fills the frame. Keep the shift from skyline to street life; use the sign detail as a short closing beat.",
  subjects=['Pedestrians'],tags=['Tokyo','Dusk','Street life','Neon'],
  highlightReason='Layered pedestrians and warm storefront light give the street scene depth, a clear subject and a lively sense of place.',
  context='Three separately sourced Tokyo scenes, arranged for the demo. Real shop signs remain visible; no added video text or sound.',
  shots=[
   shot(8,'The city lights up','A high view shows Tokyo Tower and dense buildings as dusk deepens and city lights become more prominent.','Extreme wide','Elevated city view','Time-lapse from a fixed viewpoint','Environment / opening','Recommended',5,'Keep the visible shift from evening sky to city lights.','Move down to people crossing a street.',score=89),
   shot(16,'Street life','Pedestrians cross in front of closely packed, warmly lit restaurants. People enter the foreground while others pause near storefronts.','Wide','Street-level view','Fixed viewpoint','Action / place','Keep',5,'Choose a clear crossing with foreground and background activity.','Cut into the nearby-feeling neon detail without claiming an exact location match.','Passersby are not established recurring characters.',score=93),
   shot('end','Neon details','Red, blue and green neon lettering fills the frame against a dark building facade. The luminous lines and stacked signs remain the main subject.','Close-up','Upward street view','Mostly fixed detail view','Texture / ending','Compress',3,'A short hold communicates the color and night-time character; a long hold adds little action.','End the night scene or cut on color to the next location.','These are photographed signs, not added captions.',score=85)
  ]),
 'food':dict(
  title="Slow mornings",
  full_description='细白面粉落在桌面的面团上，柔和光线让粉尘与表面纹理清晰可见；随后切到咖啡杯近景，手持奶缸倒入奶液，白色拉花逐渐展开；最后俯看摆有可颂、橙片、果汁和咖啡的早餐桌，手进入画面给杯中加入奶液。三个独立场景以制作和享用的顺序组成轻松的早餐段落。面粉飘落与拉花成形是高光，可压缩重复倒奶和静止等待，不应声称来自同一家店或同一份早餐；素材没有原声。',
  description="Flour falls onto dough, milk draws a pattern in coffee, and breakfast is served. Soft light and close-up textures turn three separate food scenes into a calm morning sequence.",
  subjects=['Hands preparing coffee','Breakfast preparation'],tags=['Breakfast','Baking','Coffee','Food detail'],
  highlightReason='The milk pattern forms visibly in one continuous action, with a clean background and warm, shallow-focus lighting.',
  context='Three separately sourced food scenes, arranged as a morning sequence. Not one documented café or recipe. No audio track.',
  shots=[
   shot(8,'Flour in the light','Flour falls onto a rounded piece of dough on a dusted wooden surface. Soft side light makes the particles and dough texture visible.','Close-up','Table-level view','Fixed close framing','Preparation / opening','Recommended',4,'Retain the falling flour and a brief settled surface; repeated dusting can be shortened.','Match the falling flour to the flow of milk.',score=90),
   shot(16,'The pattern appears','A hand holds a white coffee cup while milk pours from a metal pitcher. A pale curved pattern broadens across the coffee surface.','Close-up','Slightly elevated view','Fixed close framing','Transformation / highlight','Keep',6,'Keep the pour until the pattern becomes readable; this is the payoff of the making process.','Open out from the cup to the breakfast table.',score=95),
   shot('end','Breakfast is ready','An overhead view shows a croissant, orange slices, spreads, juice and coffee on a wooden table. A hand pours milk into the coffee and then withdraws.','Medium','Overhead tabletop view','Fixed viewpoint','Serving / ending','Recommended',4,'Keep the pouring action and a short clean composition of the table.','End the morning vignette or cut to the day’s first outing.','This is a separate setting, not the same cup as the latte shot.',score=86)
  ]),
 'outdoors':dict(
  title="Geysers at golden hour",
  full_description='蒸汽先在开阔地热盆地中升起，镜头靠近岩石中的泉口，随后交替展示强烈喷发的水柱、被蒸汽遮掩的岩石锥体和蓝天下的喷泉全景。光线转暖后，金色逆光照亮喷出的水与雾，最后以紫红晚霞中的喷发收尾。原声讲解强调间歇泉变化的不可预测性，画面从结构细节走向自然力量与光线的高潮。金色喷泉和晚霞最值得保留，可缩短相似日景，不把不同时间与机位表述成同一场喷发。',
  description="Steam and mineral textures build toward eruptions in golden light and a pink evening sky. Original narration explains their unpredictability; keep the changing light as the sequence’s payoff.",
  subjects=[],tags=['Yellowstone','Geysers','Golden light','Natural forces'],
  highlightReason='Backlight turns the water and steam gold while a dark treeline gives the eruption a clear silhouette.',
  context='Continuous excerpt from Yellowstone In Depth: Geysers, NPS / Steven M. Bumgardner. Different eruptions and lighting conditions; not one continuous event. No NPS endorsement.',
  reference='geysers-reference.vtt',
  shots=[
   shot(4.98,'Steam across the basin','A broad geothermal basin lies under a blue, cloud-streaked sky. White steam drifts sideways above pale mineral ground.','Wide','Ground-level landscape view','Fixed viewpoint','Environment / opening','Recommended',3,'Use a brief establishing view before revealing the vent.','Cut in to the mineral opening.',score=82),
   shot(10.82,'Look into the vent','An irregular opening interrupts the pale mineral surface. Steam and water movement are visible inside its darker hollow.','Close-up','Downward oblique view','Fixed framing','Information / detail','Recommended',4,'Hold long enough to read the opening that feeds the larger eruption sequence.','Cut from the confined opening to an expansive water plume.',score=84),
   shot(16.54,'The plume rises','A tall white plume surges upward from a dark cone, with dense steam catching light against the blue sky.','Wide','Low ground-level view','Fixed viewpoint','Action / power','Keep',5,'Retain the rising plume and contrasting silhouette as a clear action beat.','Move closer to the wet mineral cone.',score=92),
   shot(21.7,'Water over stone','Steam wraps a mineral cone as water spills over its dark, uneven rim. The closer view emphasizes wet surfaces and turbulent vapor.','Close-up','Ground-level detail','Fixed viewpoint','Texture / detail','Recommended',3,'Use the visible spill to add a different scale; avoid repeating too much steam.','Return to a wide view for scale.',score=85),
   shot(26.3,'A column against blue sky','A tall eruption rises from a mineral mound into a clear blue sky, with lower vapor moving across the surrounding ground.','Wide','Ground-level landscape view','Fixed viewpoint','Scale / transition','Recommended',3,'Use a short wide view before the decisive change in light.','Cut on the water column to the golden backlit eruption.',score=87),
   shot(36.94,'Water turns to gold','Low golden light illuminates a narrow jet and surrounding spray. A dark treeline and wet foreground frame the bright water.','Wide','Backlit landscape view','Fixed viewpoint','Visual highlight / climax','Keep',6,'Hold the clean silhouette and sparkling spray; this is the strongest five-second excerpt.','Let the warmer light lead into the pink evening sky.',score=97),
   shot('end','An evening eruption','White water rises against pink and violet clouds above a dark horizon. The changing plume remains visible as the narration finishes.','Wide','Evening landscape view','Fixed viewpoint','Resolution / ending','Keep',5,'Keep the complete final thought over the colorful closing view.','End the sequence without an extra explanatory title.','Different light does not establish that this is the same eruption.',score=95)
  ]),
 'islands':dict(
  title="Island escape",
  full_description='浅蓝海水中的码头与水上飞机先交代抵达海岛的场景，镜头随后转向独自划桨的人，他在清澈水面上朝白沙小岛前进；最后从岸边观看海浪轻拍沙滩，镜头沿棕榈树与海岸移动。三个独立来源片段以抵达、活动和停留组成旅行片段，清晰的水纹和人物在海面上的比例最有表现力。可保留划桨动作和明亮海岸作为高光，压缩重复漂移；不能据此认定是同一岛屿或同一趟行程，素材无音轨。',
  description="A seaplane beside a jetty, a paddleboarder on turquoise water, and a palm-lined beach suggest arrival, exploration and rest. Keep the clear water and human scale; trim repeated drifting.",
  subjects=['Paddleboarder'],tags=['Island travel','Turquoise water','Paddleboarding','Beach'],
  highlightReason='A single paddleboarder against clear turquoise water gives the view scale and movement without clutter or added graphics.',
  context='Three separately sourced island scenes, arranged for the demo. Not one documented destination or continuous journey. No added sound or text.',
  shots=[
   shot(8,'Arrive by the water','A red-and-white seaplane sits beside a long jetty in pale turquoise water. Boats, roofed platforms and a low island create depth behind it.','Wide','Elevated / aerial view','Slow lateral drift','Arrival / establishing','Recommended',4,'Keep the plane, pier and island in one readable composition.','Move from arrival infrastructure to a person on the water.',score=87),
   shot(16,'Paddle toward the island','A person stands on a board and paddles over clear shallow water toward a small white-sand island. Ripples and seabed texture remain visible.','Extreme wide','Aerial view','Gentle moving viewpoint','Action / exploration','Keep',6,'Retain a complete paddle stroke with both person and island visible.','Move down to a beach-level view.',score=96),
   shot('end','Pause on the shore','Small waves roll onto a white beach beside tall green palms. The view moves along the shoreline under a bright sky.','Wide','Beach-level view','Lateral pan','Rest / ending','Recommended',5,'Let the final wave and palm-lined composition breathe, then end.','Close the beach chapter or introduce the next activity.','No destination name or continuous travel connection is established.',score=90)
  ])
}

def seconds(text):
    h,m,s=text.split(':');return int(h)*3600+int(m)*60+float(s)

def reviewed_cues(item,review):
    if not review.get('reference'): return []
    # Require an actual completed local transcription before publishing corrected captions.
    raw=json.loads((DATA/(item['id']+'.speech.json')).read_text())
    if not raw.get('cues'): raise ValueError('Missing ASR evidence: '+item['id'])
    offset=item['sources'][0]['start']; duration=item['duration']; cues=[]
    blocks=re.split(r'\n\s*\n',(DATA/review['reference']).read_text())
    for block in blocks:
        match=re.search(r'(\d{1,2}:\d\d:\d\d\.\d+)\s*(?:-->|,)\s*(\d{1,2}:\d\d:\d\d\.\d+)\s*\n([\s\S]+)',block)
        if not match: continue
        a,b=seconds(match[1])-offset,seconds(match[2])-offset
        if a<-.05 or b>duration or b<=0: continue
        text=re.sub(r'<[^>]+>|\[[^\]]+\]|\(whispers\)','',match[3]);text=' '.join(text.split())
        text=re.sub(r'^(?:MAN|WOMAN|BOY|GIRL|HEASLER|DUFFY):\s*','',text)
        if item['id']=='islands': text=text.replace('arrival of many Alaska','designation of many Alaska')
        if text.endswith('here for Angels'): text+='…'
        if not text: continue
        cues.append(dict(start=round(max(0,a)+.021,3),end=round(min(duration,b+.021),3),text=text))
    # Source captions correct words; local word alignment corrects their often coarse timing.
    alignment=json.loads((DATA/(item['id']+'.aligned.json')).read_text())['words']
    tokenize=lambda text:re.findall(r"[a-z0-9]+(?:'[a-z]+)?",text.lower())
    heard=[]; owners=[]
    for word in alignment:
        tokens=tokenize(word['text'])
        for token in tokens: heard.append(token);owners.append(word)
    reference=[];spans=[]
    for cue in cues:
        a=len(reference);reference.extend(tokenize(cue['text']));spans.append((a,len(reference)))
    mapping={}
    for block in difflib.SequenceMatcher(None,reference,heard,autojunk=False).get_matching_blocks():
        for i in range(block.size): mapping[block.a+i]=block.b+i
    for cue,(a,b) in zip(cues,spans):
        matches=[owners[mapping[i]] for i in range(a,b) if i in mapping]
        if len(matches)<max(1,(b-a)*.5): raise ValueError('Caption needs manual alignment review: '+cue['text'])
        cue['start']=round(max(0,matches[0]['start']),3)
        cue['end']=round(min(duration,matches[-1]['end']),3)
    # Retain sentence-level readability, not arbitrary ASR windows or isolated words.
    joined=[]
    for cue in cues:
        if joined and not re.search(r'[,;.!?…]$',joined[-1]['text']) and cue['start']-joined[-1]['end']<.6 and cue['end']-joined[-1]['start']<12:
            joined[-1]['text']+=' '+cue['text'];joined[-1]['end']=cue['end']
        else: joined.append(cue)
    return joined

def main():
    catalog=[]
    for item in json.loads((DATA/'manifest.json').read_text()):
        key=item['id'];review=REVIEWS[key]; base='/assets/media/cases/v3/'+key
        canonical=validate_description({'title':review['title'],'full_description':review['full_description']})
        cues=reviewed_cues(item,review)
        if cues:
            (OUT/(key+'.vtt')).write_text('WEBVTT\n\n'+'\n\n'.join(stamp(c['start'])+' --> '+stamp(c['end'])+'\n'+c['text'] for c in cues)+'\n')
        sources=[{k:v for k,v in s.items() if k!='file'} for s in item['sources']]
        model_file=DATA/(key+'.model.json')
        model=model_file.exists() and model_file.stat().st_mtime >= (OUT/(key+'.mp4')).stat().st_mtime
        entry=dict(id=key,label=item['label'],title=review['title'],description=review['description'],full_description=canonical['full_description'],subjects=review['subjects'],tags=review['tags'],context=review['context'],duration=item['duration'],width=item['width'],height=item['height'],audio=item['audio'],full=base+'.mp4',preview=base+'-preview.mp4',poster=base+'.jpg',highlight={'start':item['highlight'],'reason':review['highlightReason']},sources=sources,sourcePage=sources[0]['page'],license=sources[0]['license'],licenseURL=sources[0]['page'],analysisModel=('Qwen3-VL visual draft + ' if model else '')+'editorial shot review'+(' · Whisper + source-caption correction' if cues else ''),transcript=cues,captionFile=base+'.vtt' if cues else None,shots=[],video_summary=review['title'].split(' | ')[0],schemaVersion=2)
        start=0
        for i,source in enumerate(review['shots']):
            s=dict(source);end=item['duration'] if s['end']=='end' else s['end'];s.update(start=start,end=end,thumbnail=base+f'-shot-{i}.jpg',highlight=s['importance_score']>=88,audio=[],dialogue='')
            spoken=[c for c in cues if c['start']>=start and c['end']<=end]
            if spoken: s['dialogue']=spoken[0]['text']
            level={'Keep':'必留','Recommended':'推荐','Compress':'可压缩'}[s['recommendation']]
            mac=dict(shot_id=f'shot_{i+1:03}',start_time=stamp(start),end_time=stamp(end),description=s['description'],shot_size=s['size'],capture_type=s['capture'],camera_motion=s['motion'],story_role=s['role'].split(' / '),dialogue=s['dialogue'],reaction=s['reaction'],audio=[],importance_score=s['importance_score'],duplicate_candidate=False,unusable_candidate=False,edit_recommendation=dict(level=level,recommended_duration_sec=s['useDuration'],reason=s['reason']))
            s['editorial']=validate_shot(mac,start,end,cues,item['audio'])
            entry['shots'].append(s)
            subprocess.run(['ffmpeg','-v','error','-y','-ss',str(min(end-.08,start+min(1,(end-start)/2))),'-i',str(OUT/(key+'.mp4')),'-frames:v','1','-vf','scale=640:-2','-q:v','3',str(OUT/(key+f'-shot-{i}.jpg'))],check=True)
            start=end
        catalog.append(entry)
        print(key,len(entry['shots']),'shots',len(cues),'cues',flush=True)
    order=['islands','citywalk','food','outdoors','alpine']
    catalog.sort(key=lambda item:order.index(item['id']))
    target=ROOT/'public/media/cases/catalog.json'
    # Publish only when every example and caption has validated successfully.
    temporary=target.with_suffix('.tmp');temporary.write_text(json.dumps(catalog,ensure_ascii=False,indent=2));temporary.replace(target)

if __name__=='__main__': main()
