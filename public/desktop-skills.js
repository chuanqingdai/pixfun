/* Creator skills describe editorial strategies, not steps in a processing pipeline. */
(() => {
  'use strict';
  const skills=[
    {
      "id": "visionflow-travel-director",
      "title": "Travel Vlog",
      "image": "skill-visionflow-travel-director-photo-v3",
      "copy": "Shape your travel footage into a story that follows your journey and preserves the moments that matter.",
      "materials": [
        "Photos & mixed-format video",
        "Multi-device trips"
      ],
      "structure": [
        "Hook with the highlights",
        "Follow the real journey",
        "Let people carry the experience",
        "Give each destination a moment",
        "End with a complete memory"
      ],
      "pacing": "Content-led length, not a fixed runtime. Trim repetition; protect complete actions, conversations, and meaningful pauses.",
      "sound": "Choose licensed instrumental music after understanding the footage. Cut to musical phrases, retain real ambience, and lower music under important speech.",
      "avoid": "Verify places and dates; leave unknowns unknown. Never invent events or locations, alter originals, or upload private footage without permission.",
      "value": "For travelers and creators bringing home photos, phone clips, and camera footage. Give every usable unique memory a place, connect destinations clearly, and keep the people and sounds that made the trip yours.",
      "beats": [
        "Open with a brief mix of travel, scenery, and human highlights, then return to the beginning. Revisit those moments properly in the main film.",
        "Group by verified route and visits. Use arrivals, transport, and wide views to establish each destination; do not invent chronology.",
        "Keep complete actions, conversations, and shared reactions. Use details and scenery to connect moments without manufacturing interactions.",
        "Within each chapter: approach → place → people → scenery → a quiet close. Omit missing beats instead of fabricating them.",
        "Close on a complete action, shared photo, final view, or return. Let the original sound and music resolve naturally."
      ],
      "handling": [
        "Keep a meaningful main-film appearance for every usable unique file by default; highlights and blurred backgrounds do not count. Resolve conflicts with a hard duration limit.",
        "Fit portrait clips at full height over a synchronized soft background. Animate photos gently; protect faces, companions, and framing."
      ],
      "example": "First propose a travel story from these video clips. Follow our verified route, preserve complete actions and usable original sound, and let the footage determine the length. Wait for my review before rendering a rough cut.",
      "source": "visionflow-travel-director/SKILL.md",
      "version": "5.4",
      "highlights": [
        {
          "title": "Keep the memories",
          "body": "Cover every usable unique file in the main story. Trim waste, not meaningful events; explain missing or unusable footage."
        },
        {
          "title": "Mix formats naturally",
          "body": "16:9 film with full-height portrait clips, soft backgrounds, and subtle photo motion. Never stretch or crop out companions."
        },
        {
          "title": "Music with a purpose",
          "body": "Licensed instrumental music shapes each chapter. Keep real ambience and make room for speech; beat-matching is optional."
        },
        {
          "title": "A sense of place",
          "body": "Use verified locations, trip days, and dates. Keep chapter cards and scenic captions short; never guess a landmark."
        },
        {
          "title": "Let the story set the length",
          "body": "No fixed runtime by default. Start at 1080p / 30 fps; use 4K only when the source supports it. Your brief overrides defaults."
        },
        {
          "title": "Check the whole film",
          "body": "The full specification calls for rendered-video checks, sound review, coverage evidence, and a recoverable editing project."
        }
      ]
    },
    {id:'city-walk',title:'City walk',image:'skill-city-walk-photo-v3',copy:'Follow a route, not a random collection of landmarks.',materials:['Street clips','Ambient audio'],structure:['Establish the neighborhood','Follow streets and small discoveries','Arrive at a memorable place'],pacing:'Alternate wide views and close details; give each stop room to breathe.',sound:'Keep footsteps, traffic, and local atmosphere. Use narration only when supplied.',avoid:'Do not invent locations or imply a route that the footage cannot support.'},
    {id:'food-tour',title:'Food tour',image:'skill-food-tour-photo-v3',copy:'Build anticipation from the first sizzle to the first bite.',materials:['Food close-ups','Spoken reactions'],structure:['Introduce the place and dish','Show preparation and revealing details','Keep the first taste and honest reaction'],pacing:'Use short detail shots around preparation; hold longer on reactions.',sound:'Prioritize cooking sounds and spoken reactions over background music.',avoid:'Do not invent reviews, prices, or dialogue. Keep preparation and tasting in a plausible order.'},
    {id:'travel-diary',title:'Travel diary',image:'skill-travel-diary-photo-v3',copy:'Connect mixed footage through the story you tell.',materials:['Mixed cameras','Voiceover'],structure:['Set up the journey','Connect discoveries with personal narration','Close with a moment of reflection'],pacing:'Follow the available chronology; use photos and scenery to support the story.',sound:'Let supplied voiceover lead; preserve conversations and meaningful pauses.',avoid:'Do not invent memories or relationships. If voiceover is absent, use a visual diary instead.'},
    {id:'outdoor-adventure',title:'Outdoor adventure',image:'skill-outdoor-adventure-photo-v3',copy:'Balance the scale of the place with the effort of getting there.',materials:['Drone views','Action cameras'],structure:['Establish the terrain','Build the journey through action and effort','Reveal the destination and a quiet aftermath'],pacing:'Use wide shots for scale and close action for intensity; avoid constant rapid cutting.',sound:'Retain wind, breathing, water, and movement where usable.',avoid:'Do not suggest risks or achievements the footage does not show.'},
{id:'flights-stays',title:'Flights & stays',image:'skill-flights-stays-photo-v3',copy:'Organize a thoughtful tour around the details that matter.',materials:['Cabin / room tours','Commentary'],structure:['Introduce arrival and first impressions','Group space, amenities, and service details','End with the creator’s recorded assessment'],pacing:'Use clear chapters and unhurried shots so viewers can inspect the space.',sound:'Keep the creator’s commentary clear and leave room for cabin or room ambience.',avoid:'Do not invent a rating, service claim, or assessment. Skip the verdict if none was recorded.'},
    {id:'family-memories',title:'Family memories',image:'skill-family-memories-photo-v3',copy:'Keep the conversations and imperfect moments worth revisiting.',materials:['Phone clips','Live conversations'],structure:['Set the scene with the group','Connect activities and spontaneous moments','Close on a shared moment'],pacing:'Favor complete interactions over rapid highlights; use scenery as breathing room.',sound:'Keep original jokes and conversations intact. Reduce music under speech.',avoid:'Do not infer identities or relationships from appearance, or manufacture reactions.'},
    {id:'scenic-escape',title:'Scenic escape',image:'skill-scenic-escape-photo-v3',copy:'Give drone views and quiet landscapes a visual rhythm.',materials:['Drone footage','Landscape shots'],structure:['Reveal a sense of place','Move between scale and detail','Land on a quiet final view'],pacing:'Group compatible movement and light; let long scenic shots breathe.',sound:'Use natural sound as the base; add music only when supplied or explicitly requested.',avoid:'Do not join unrelated places into a false continuous journey or imply unrecorded events.'},
    {id:'travel-guide',title:'Travel guide',image:'skill-travel-guide-photo-v3',copy:'Turn long explanations into a clear, useful travel story.',materials:['On-camera speech','Supporting B-roll'],structure:['State what the viewer will learn','Build clear topic chapters','Recap the useful takeaways'],pacing:'Keep complete explanations; use relevant B-roll during longer spoken passages.',sound:'Treat supplied speech as the source of truth. Keep sentence meaning and qualifications intact.',avoid:'Do not invent facts, opening hours, directions, or accessibility claims.'},
  ];
  const details={
    'city-walk':{value:'Turn hours of walking footage into a route viewers can follow. The strategy gives repeated street shots a purpose and keeps the small discoveries that make a neighborhood feel distinct.',beats:['Start with a wide street view and a clear arrival point. Establish where the walk begins using only recorded context.','Group nearby discoveries into stops. Connect each wide view to a sign, storefront, or human-scale detail.','Finish with a destination or a final street moment. Let the atmosphere resolve instead of adding an unrelated highlight.'],handling:['Many similar street clips: choose complementary wide and detail shots instead of repeating the same view.','No spoken narration: let recorded street sound and visual continuity carry the route.'],example:'Make a 4-minute city walk from my street clips. Follow the route, keep café and market sounds, and avoid fast music-driven cuts.'},
    'food-tour':{value:'Help viewers experience a dish rather than just see a plate. This strategy connects preparation, texture, sound, and reactions so a food review has anticipation and a clear payoff.',beats:['Introduce the venue through a street view, counter, or menu when available. Establish the dish without invented background.','Build anticipation with preparation, plating, and texture close-ups. Match each detail to its natural sound when available.','Hold on the first taste and complete spoken reaction. End on a useful recorded observation or the final dish.'],handling:['No preparation footage: build the middle from serving, texture, and tasting; do not imply unseen cooking steps.','Talking clips mixed with food close-ups: keep the reaction as the audio anchor and cover pauses with relevant dish footage.'],example:'Create a 3-minute food tour. Start outside the restaurant, build up through the cooking shots, and keep my full first-bite reaction.'},
    'travel-diary':{value:'Bring phone clips, camera footage, and photos into one personal narrative. Use your voice and the order of the trip to connect uneven footage without forcing every moment into a montage.',beats:['Introduce the trip with an arrival, a voice note, or a scene-setting image. Use the creator’s own recorded context.','Organize discoveries around the narration or the documented day. Bridge gaps with relevant photos or quiet scenery.','Return to a memorable detail, final conversation, or reflective voiceover. Leave the ending personal rather than promotional.'],handling:['Mixed devices and frame sizes: preserve subjects with deliberate framing instead of stretching clips to match.','Missing chronology or voiceover: group scenes by supported activity or setting and avoid inventing an itinerary.'],example:'Make a 5-minute travel diary from my phone clips and photos. Let my voiceover lead, keep our conversations, and close with the train ride home.'},
    'outdoor-adventure':{value:'Make the journey feel earned, not just scenic. Connect action-camera details with wide landscapes to show progress, effort, and the quieter moments around the destination.',beats:['Use an approach or terrain shot to establish scale. Show the real starting conditions without fabricating stakes.','Follow visible progress through walking, climbing, or other recorded activity. Alternate action with details of the environment.','Give the destination reveal room, then finish with recovery, a quiet view, or the return when available.'],handling:['Drone and action-camera clips: use drone footage for orientation and action footage for the human experience.','No summit or destination shot: end with the last meaningful recorded moment instead of suggesting an achievement.'],example:'Make a 4-minute hiking film. Use drone views to establish the trail, preserve breathing and footsteps, and slow down for the final landscape.'},
    'flights-stays':{value:'Make a cabin or hotel tour easy to evaluate. Organize repeated pans and detail shots into useful chapters while preserving the creator’s actual observations and unhurried viewing time.',beats:['Show the arrival, exterior, or first recorded impression. Establish the experience without adding promotional claims.','Group shots by space and function: seating or bed, storage, amenities, food, and service where recorded.','Use the creator’s own closing assessment. If none exists, finish with a complete tour detail rather than an invented verdict.'],handling:['Many room pans: choose views that explain different areas; trim redundant coverage without hiding important details.','Separate spoken review: align each observation with the matching area or amenity, retaining limitations and caveats.'],example:'Create a 6-minute cabin tour with chapters for the seat, storage, food, and amenities. Keep my spoken observations and avoid rushing the detail shots.'},
    'family-memories':{value:'Keep what a polished highlights reel often loses: a full joke, a spontaneous reaction, or a small shared activity. This strategy prioritizes meaningful interactions over constant visual novelty.',beats:['Use a wide scene or recorded conversation to establish the activity. Do not infer people’s identities from appearance.','Keep interactions in understandable sequences. Use scenery and activity details as short transitions between moments.','Finish with a complete shared moment or a calm closing shot, preserving the feeling of the original recording.'],handling:['Clips from several phones: group by recorded time when available, then by supported activities.','Speech over shaky footage: prioritize understandable conversation; use relevant cutaways without manufacturing reactions.'],example:'Make a 4-minute weekend memory film. Keep the children’s conversations and the picnic jokes intact, with quiet scenery between activities.'},
    'scenic-escape':{value:'Create a cohesive film from footage with little or no dialogue. Use changes in scale, light, and movement to connect scenic clips rather than treating them as interchangeable background.',beats:['Open with a revealing wide shot or a gradual change in scale. Establish the dominant setting and mood from the footage.','Alternate broad views with textures and details. Group compatible motion and lighting so transitions feel intentional.','Let the final landscape settle. Avoid an abrupt sequence of unrelated “best shots” at the end.'],handling:['Mostly long drone takes: select distinct compositions instead of repeating nearly identical passes.','No usable location audio: do not fabricate natural sound; request an audio track or keep a silent visual draft.'],example:'Shape my island drone footage into a 90-second scenic film. Move from wide views to water details, use gentle pacing, and finish on a long coastal shot.'},
    'travel-guide':{value:'Make long, information-rich recordings easier to follow without losing the speaker’s meaning. Organize speech into useful chapters and use supporting footage to illustrate, not replace, the explanation.',beats:['Start with the speaker’s actual topic or a concise recorded introduction. Make the scope clear without adding unverified claims.','Group complete explanations by topic. Place relevant place or object footage over speech while keeping qualifications intact.','Close with recorded takeaways or a concise recap based strictly on the supplied content.'],handling:['A single long talk: preserve complete ideas and remove repetition only when the meaning remains unchanged.','B-roll without a clear match: leave the speaker visible rather than implying a place or object they did not discuss.'],example:'Turn this 10-minute guided walk into a 6-minute travel guide. Keep the factual explanations, group related topics, and use my location shots as B-roll.'},
  };
  skills.forEach(skill=>Object.assign(skill,details[skill.id]));
  function buildBrief(skill,direction){return `${skill.title}${skill.source ? `\nFull specification: CreatorSkills/${skill.source} (v${skill.version}). This brief is a summary; consult the bundled specification when execution is connected.` : ''}\n\nStory framework:\n${skill.structure.map((beat,i)=>`${i+1}. ${beat}: ${skill.beats[i]}`).join('\n')}\nPacing: ${skill.pacing}\nSound: ${skill.sound}\nMaterial handling: ${skill.handling.join(' ')}\nGuardrails: ${skill.avoid}\n\nCreator direction: ${direction.trim()||'Use the strategy above with the selected footage.'}`;}
  if(typeof document==='undefined'){module.exports={skills,buildBrief};return;}
  if(!window.PixfunDesktop)return;
  const library=window.PixfunLibrary,root=document.getElementById('workspaceSkills');
  const node=(tag,text,cls)=>{const el=document.createElement(tag);if(text!=null)el.textContent=text;if(cls)el.className=cls;return el;};
  const picture=name=>{const img=node('img');img.src=`/assets/media/travel/${name}.jpg`;img.alt='';img.loading='lazy';return img;};
  const catalog=node('div',null,'skill-catalog'),detail=node('section',null,'skill-task-detail');detail.hidden=true;root.replaceChildren(catalog,detail);root.setAttribute('aria-label','Creator skills');
  catalog.append(node('p','Editing strategies for your kind of story.','skill-intro'));
  const grid=node('div',null,'skill-task-grid');catalog.append(grid);
  skills.forEach(task=>{
    const button=node('button',null,'skill-task-card');button.type='button';
    const preview=picture(task.image);preview.className='creator-skill-cover';
    const cover=node('span',null,'creator-skill-photo');cover.append(preview);
    const copy=node('span',null,'skill-task-copy');copy.append(node('strong',task.title),node('span',task.copy));
    button.append(cover,copy);button.setAttribute('aria-label',`${task.title} skill`);button.onclick=()=>openTask(task,button);grid.append(button);
  });
  let sourceButton=null;
  function back(){detail.hidden=true;catalog.hidden=false;sourceButton?.focus({preventScroll:true});}
  function openTask(task,trigger){
    sourceButton=trigger;catalog.hidden=true;detail.hidden=false;detail.replaceChildren();
    const backButton=node('button','← All skills','text-button skill-back');backButton.type='button';backButton.onclick=back;
    const head=node('header'),title=node('h2',task.title);title.tabIndex=-1;head.append(title,node('p',task.copy));
    const action=node('button','Use skill','button primary');action.type='button';action.onclick=()=>window.PixfunWorkspace.useSkill({id:task.id,title:task.title,strategy:buildBrief(task,'')});
    const top=node('div',null,'creator-skill-actions');top.append(backButton,action);
    const value=node('section',null,'creator-skill-value');value.append(node('h3','Why creators use it'),node('p',task.value));
    const story=node('section',null,'creator-story-structure');story.append(node('h3','Story framework'));const beats=node('ol');task.structure.forEach((beat,index)=>{const li=node('li');li.append(node('strong',beat),node('p',task.beats[index]));beats.append(li);});story.append(beats);
    const strategy=node('dl',null,'creator-strategy');for(const [label,value]of [['Works with',task.materials.join(' · ')],['Pacing',task.pacing],['Sound',task.sound],['Keep it honest',task.avoid]]){const row=node('div');row.append(node('dt',label),node('dd',value));strategy.append(row);}
    const handling=node('section',null,'creator-material-handling');handling.append(node('h3','Make the most of your footage'));const tips=node('ul');task.handling.forEach(tip=>tips.append(node('li',tip)));handling.append(tips);
    const example=node('section',null,'creator-skill-example');example.append(node('h3','Example brief'),node('p',task.example));
    detail.append(top,head,value,story,strategy,handling,example,node('p','Use this strategy in your Home brief. Automatic editing is not connected yet.','skill-capability-note'));
    title.focus({preventScroll:true});root.scrollIntoView({block:'start',behavior:'instant'});
  }
  document.addEventListener('pixfun:workspacepage',event=>{if(event.detail==='skills'){detail.hidden=true;catalog.hidden=false;}});
})();
