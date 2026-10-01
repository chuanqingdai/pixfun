# Pixfun landing assets

## Native bundled example — 2026-10-01

`native/Examples/wild-alaska/` contains one offline 1080p example, a continuous 00:25–03:54 excerpt (3:29) from [NPS Lake Clark Virtual Field Trip](https://www.nps.gov/media/video/view.htm?id=a7ea1719-005e-42cd-b7c9-79cda436ecad), credited to T. Vaughn and J. Pfeiffenberger (2018). The source page identifies NPS-credited footage as public domain. Original narration/music are retained, with no added on-picture text; the opening logo/title is excluded. This is a documentary excerpt, not unedited camera footage. Official captions are offset into the excerpt, visual cuts are precomputed, and the supplied description is an editorial review, not a claim of live model inference. `scripts/build-native-example.py` reproduces all assets from the existing local source. The gold “案例” badge is UI only. The Mac build includes source/credit in `SOURCE.txt`.

## Current five hero cases — visual-quality revision, 2026-10-01

This section supersedes all earlier hero/case selections below. Routes are retained; `public/media/cases/v3/` is the active asset version. Five separate, silent 5-second excerpts link to 24–50-second multi-shot examples. No captions, titles, logos or analysis graphics are added to the video. Naturally photographed Tokyo signs remain. All are real footage, not generated imagery. The two documentary excerpts are not represented as unedited camera originals.

| Route | Current selection | Complete example | Source / licence |
|---|---|---|---|
| `islands` | Seaplane arrival → paddleboarder → palm beach | 24s, 3 shots, 1080p, silent | Mixkit [2883](https://mixkit.co/free-stock-video/paradise-port-on-an-island-2883/), [1579](https://mixkit.co/free-stock-video/a-man-paddling-on-a-board-to-get-to-a-1579/), [1564](https://mixkit.co/free-stock-video/white-sand-beach-background-1564/), 2–10s each; Stock Video Free License |
| `citywalk` | Tokyo dusk → warm-lit street → neon detail | 24s, 3 shots, 1080p, silent | Mixkit [4308](https://mixkit.co/free-stock-video/aerial-view-of-a-city-during-the-night-4308/) 2–10s, [4451](https://mixkit.co/free-stock-video/quiet-tokyo-street-at-night-4451/) 4–12s, [4447](https://mixkit.co/free-stock-video/neon-signs-with-japanese-letters-4447/) 8–16s; Stock Video Free License |
| `food` | Falling flour → latte art → breakfast table | 24s, 3 shots, 1080p, silent | Mixkit [1669](https://mixkit.co/free-stock-video/a-chef-covering-dough-with-flour-1669/) 1–9s, [41859](https://mixkit.co/free-stock-video/serving-a-sparkling-cappuccino-in-a-cup-41859/) 0–8s, [4866](https://mixkit.co/free-stock-video/breakfast-at-a-table-with-bread-coffee-and-fruit-4866/) 2–10s; Stock Video Free License |
| `outdoors` | Yellowstone geysers, gold backlight and pink sky | 43.47s, 7 shots, native 720p, original narration | [NPS / Steven M. Bumgardner, In Depth: Geysers](https://www.nps.gov/media/video/view.htm?id=DBA52FFD-155D-451F-67C4471D28BA5344), 237.8–281.25s; NPS public-domain credit |
| `alpine` | Alaska bear → river → mountains → snowy summit | 50.22s, 6 shots, 1080p, original narration | [NPS / T. Vaughn and J. Pfeiffenberger, Lake Clark](https://www.nps.gov/media/video/view.htm?id=a7ea1719-005e-42cd-b7c9-79cda436ecad), 102.8–153s; NPS public-domain credit |

Selection: removed the soft ranger/pika and archaeology field recordings, dim car-window/railway views and busy grill scene. Kept the strongest latte action. Candidate review includes full sampled contact sheets and source resolution checks, not thumbnails alone. Excluded Yosemite footage with unclear/no-derivatives licensing, Glacier Bay research footage with non-commercial music, and a portrait espresso clip rather than cropping it into a fake landscape source. This does not assert any endorsement by the NPS or stock contributors.

The three Mixkit examples are expressly labelled curated, multi-source sequences, not evidence of one real journey or café. The NPS excerpts retain their original continuous audio/video. Local Whisper was rerun and word-aligned, then checked against official source captions. The complete transcript appears below the video, not over it. Local Qwen visual drafts were rerun; the final shot boundaries and editing judgments are editorially reviewed and labelled precomputed, not passed off as a live automatic result. Silent-source clips receive no invented dialogue or environmental sound.

The source pages and 1080p candidates are recorded in `data/landing-quality-20261001/`. Rebuild with `scripts/build-multiscene-cases.py`, then local analysis/alignment and `scripts/publish-multiscene-cases.py`. `--refresh-previews` updates highlight selections without recompressing complete examples. Older assets remain recoverable and are not requested by the active pages. Homepage previews are 720p for load performance; detail files preserve real 1080p where available. No upscaling, synthetic enhancement or playback-speed change was used.

## Current six-step adventure example — 2026-09-27

`public/media/travel/story/` contains real, native-landscape stock clips and extracted poster frames for **Beyond the trail**. The example now carries one curated selection through import, understanding, a written creative brief, arrangement, refinement and review. Twelve different shots form four chapters: Departure → Into the wild → The reward → After dark. Cinematic / Travel diary are 45 seconds; Quick highlights is 30 seconds. The user-triggered example refinement reallocates two seconds without changing the total or ending.

The forest/camping actors recur within the same provider series. The mountain, lake and night cutaways are separately sourced stock: this is an illustrative adventure montage, **not proof of a single real trip, location, snowfall event, or actual dangerous climb**. No capture-device metadata is invented. All outputs are 1280 × 720, 24 fps, silent H.264 previews. No portrait crop, synthetic frame, repeated shot, or duration-stretching was used. There is no generated music or automatic custom edit behind the demo. The written brief is retained in memory between steps; it is not sent to a model or saved as a real project.

All source pages below displayed **Mixkit Stock Video Free License** (commercial/personal use) when checked on 2026-09-27. [License](https://mixkit.co/license/#videoFree).

| Local stem | Source |
| --- | --- |
| `coffee` | [Coffee at camp — 43165](https://mixkit.co/free-stock-video/couple-having-coffee-in-a-campsite-43165/) |
| `trail` | [Exploring the forest — 43151](https://mixkit.co/free-stock-video/couple-exploring-a-forest-43151/) |
| `hike` | [High view of hikers — 43155](https://mixkit.co/free-stock-video/high-view-of-young-people-hiking-43155/) |
| `look` | [Hiker looking up — 43159](https://mixkit.co/free-stock-video/hiker-looking-at-the-sky-43159/) |
| `snow` | [Clouds over Matterhorn — 4282](https://mixkit.co/free-stock-video/clouds-touching-the-tip-of-matterhorn-mountain-4282/) |
| `clouds` | [Sky over the mountains — 4303](https://mixkit.co/free-stock-video/sky-over-the-mountains-4303/) |
| `vista` | [Mountains and lake — 42490](https://mixkit.co/free-stock-video/landscape-with-mountains-and-a-lake-seen-from-above-42490/) |
| `together` | [Sharing the view — 43161](https://mixkit.co/free-stock-video/couple-looking-at-a-landscape-in-nature-43161/) |
| `selfie` | [Hiking selfie — 43150](https://mixkit.co/free-stock-video/hiking-couple-taking-a-selfie-43150/) |
| `camp` | [Unpacking at camp — 43137](https://mixkit.co/free-stock-video/man-unpacking-his-camping-gear-43137/) |
| `fire` | [Campfire after dark — 22730](https://mixkit.co/free-stock-video/campfire-burning-wood-logs-in-the-dark-22730/) |
| `stars` | [Stars above the mountains — 4124](https://mixkit.co/free-stock-video/many-stars-in-the-night-sky-4124/) |

Rebuild via `node scripts/build-workflow-story.mjs`. Sources download to `qa/workflow-story/sources/`; build outputs are limited to the first nine seconds of each source (or the source duration if shorter). Every edit variant is tested against the actual media duration. The browser advances sources at the edit boundaries; wall-clock playback can include network-loading delays. Earlier family-story and portrait-based workflow notes below are superseded by this section. The unused `rest` candidate (Mixkit 43144) remains only as a local asset and is not loaded by the page.

## Current hero: sequential travel playlist — 2026-09-27

Five independently encoded, silent **8.000-second** videos now play in sequence, wrapping after the fifth. These replace the single-case looping behavior below. Files are 1280 × 720, 24 fps, H.264, fast-start; playback speed is unchanged. No repeated frames or looping are used to extend a source. A full round is approximately 40 seconds plus loading transitions. Eight seconds is a design choice, not a measured optimum.

| Current hero file | Real stock sources and selected time ranges | License shown on source page |
|---|---|---|
| `hero-citywalk.mp4` | [Pedestrian walk in Tokyo — Mixkit 4231](https://mixkit.co/free-stock-video/pedestrian-walk-in-tokyo-4231/), 2–10s: neon streets, rain, crowds | Mixkit Stock Video Free License |
| `hero-food.mp4` | [Chef cooking with a frying pan — Pexels 4003980, Jamie Roach](https://www.pexels.com/video/a-chef-cooling-with-a-frying-pan-4003980/), 0–3.5s: flambé; then [Tokyo’s busy outdoor market — Mixkit 4452](https://mixkit.co/free-stock-video/tokyos-busy-outdoor-market-4452/), 1–5.5s | Pexels License / Mixkit Stock Video Free License |
| `hero-luxury.mp4` | [Private jet boarding stairs — Pexels 28586465, AP Vibes](https://www.pexels.com/video/elegant-private-jet-with-boarding-stairs-outside-28586465/), 0–4s; then [Private jet cabin — Pexels 5778801, RDNE Stock project](https://www.pexels.com/video/businessman-reading-newspaper-in-private-jet-5778801/), 4–8s | Pexels License |
| `hero-islands.mp4` | [Snorkeling above a reef — Mixkit 1582](https://mixkit.co/free-stock-video/a-person-snorkeling-in-a-turquoise-water-with-reef-1582/), 4–12s | Mixkit Stock Video Free License |
| `hero-alpine.mp4` | [Skier on a snowy peak — Mixkit 3362](https://mixkit.co/free-stock-video/skier-at-the-peak-of-a-snowy-mountain-3362/), 2–6s; then [Snowboarding at a resort — Pexels 1581362, Jakob Kreinecker](https://www.pexels.com/video/people-snowboarding-at-a-resort-1581362/), 0–4s | Mixkit Stock Video Free License / Pexels License |

Posters are taken at 1s from each final video. These are illustrative licensed stock samples, not generated edits, real customer examples, endorsements, or documentation of one continuous trip/restaurant/aircraft. The luxury cabin shot is intentionally retained; the other hero selections are new. No AI imagery or audio is used. Other page sections retain separate material sets.

Reproduce with `qa/hero-autoplay/build-media.mjs`; local source cache is ignored. Downloads: `https://assets.mixkit.co/videos/{id}/{id}-720.mp4` for the Mixkit IDs above; Pexels video files `4003980/4003980-hd_1920_1080_24fps.mp4`, `28586465/12427507_3840_2160_24fps.mp4`, `1581362/1581362-uhd_2562_1440_30fps.mp4` under `https://videos.pexels.com/video-files/`. The existing cabin source remains in the earlier QA source cache. [Pexels license](https://www.pexels.com/license/). Candidate restricted-license clips were not used.

## Previous travel themes (superseded hero) — 2026-09-27

The previous hero used **five independent, silent 8.000-second samples**, 1280 × 720 / 24 fps / H.264 with fast-start metadata. These were manually selected real stock examples, not Pixfun-generated results or customer testimonials. Its single-case looping has now been replaced by the sequential playlist above. Older files are retained but are no longer loaded by the hero.

| Hero file | Source and selection | License |
|---|---|---|
| `citywalk-preview.mp4` | [Street with people walking at dusk — Mixkit 3428](https://mixkit.co/free-stock-video/street-with-people-walking-at-dusk-3428/), 3–11s | Mixkit Stock Video Free License |
| `food-preview.mp4` | [Chef cooking on a large grill — 4678](https://mixkit.co/free-stock-video/chef-cooking-on-a-large-grill-4678/), 5–9s; then [Serving a cappuccino — 41859](https://mixkit.co/free-stock-video/serving-a-sparkling-cappuccino-in-a-cup-41859/), 0–4s | Mixkit Stock Video Free License |
| `luxury-preview.mp4` | [Private jet at the airport — Pexels 14109773, Advancer Drones](https://www.pexels.com/video/white-private-jet-at-the-airport-14109773/), 2–6s; then [Private jet cabin — Pexels 5778801, RDNE Stock project](https://www.pexels.com/video/businessman-reading-newspaper-in-private-jet-5778801/), 4–8s | [Pexels License](https://www.pexels.com/license/) |
| `citybreak-preview.mp4` | [Bellagio fountain skyline — Mixkit 4253](https://mixkit.co/free-stock-video/bellagio-fountain-skyline-4253/), 8–16s | Mixkit Stock Video Free License |
| `outdoors-preview.mp4` | [People walking on the snowy summit — Mixkit 3335](https://mixkit.co/free-stock-video/people-walking-on-the-snowy-summit-3335/), 1–9s | Mixkit Stock Video Free License |

Hero JPGs are frames extracted from these exact final samples. Food & cafés and Luxury flights each combine two shots within their own theme; these do not claim to document the same restaurant or the same aircraft. No music was copied or added. No performer, café, hotel, destination, or aviation operator is represented as endorsing Pixfun.

The workflow uses provider-supplied **real video thumbnails**, not newly generated images or working uploaded files. Its illustrative filenames are interface examples. The same selected images recur intentionally in understanding/style/arrangement to preserve source-to-edit continuity; none is borrowed from the hero or the input/output section.

| Local JPG stem | Original Mixkit source |
|---|---|
| `project-airport` | [Airport corridor — 4008](https://mixkit.co/free-stock-video/people-walking-down-an-airport-corridor-in-fast-motion-4008/) |
| `project-flight` | [Plane taking off near the sea — 2628](https://mixkit.co/free-stock-video/plane-taking-off-near-the-sea-2628/) |
| `project-island` | [Water plane arriving at an island — 2882](https://mixkit.co/free-stock-video/water-plane-arriving-to-a-little-island-2882/) |
| `project-street` | [Walking in Japan — 4437](https://mixkit.co/free-stock-video/people-walking-in-the-street-in-japan-4437/) |
| `project-crosswalk` | [Person on a crosswalk — 98](https://mixkit.co/free-stock-video/person-walking-on-crosswalk-98/) |
| `project-bikes` | [Couple with bicycles — 41873](https://mixkit.co/free-stock-video/couple-walking-with-bicycles-on-the-sidewalk-41873/) |
| `project-lavender` | [Lavender field — 4530](https://mixkit.co/free-stock-video/lovers-walking-through-a-lavender-field-4530/) |
| `project-park` | [Walking in a park — 40656](https://mixkit.co/free-stock-video/slowly-walking-down-a-path-in-a-park-40656/) |
| `project-lake` | [Couple by a lake — 41581](https://mixkit.co/free-stock-video/loving-couple-sitting-on-the-shore-of-a-lake-outdoors-41581/) |
| `project-forest` | [Forest path — 32622](https://mixkit.co/free-stock-video/walking-of-a-person-on-the-path-of-a-forest-32622/) |
| `project-family` | [Family walking in nature — 39767](https://mixkit.co/free-stock-video/family-walking-together-in-nature-39767/) |
| `creator-cafe` | [Woman in a café — 223](https://mixkit.co/free-stock-video/woman-drinking-coffee-in-a-cafe-223/) |
| `creator-flight` | [Seaplane arrival — 2885](https://mixkit.co/free-stock-video/tourists-getting-off-a-water-plane-on-a-pier-2885/) |
| `creator-outdoor` | [Two people hiking — 114](https://mixkit.co/free-stock-video/two-people-hiking-114/) |
| `closing-street` | [Old street at night — 3456](https://mixkit.co/free-stock-video/old-street-at-night-3456/) |

Each source page above displayed the commercial/personal **Mixkit Stock Video Free License** label on 2026-09-27. Original provider thumbnail paths follow the page's verified `https://assets.mixkit.co/videos/{id}/{id}-thumb-720-0.jpg` link. The existing `camping.jpg` is now exclusive to the workflow; `city.jpg` is exclusive to the creator section. The coast/van/hiking footage is reserved for the input/output example. Old previews remain on disk but are not loaded by the landing page. Candidate Mixkit 7138, 16534, and 25890 were rejected because their free versions were personal-use-only.

Build selections: `qa/material-diversity/build-media.mjs`. Visual verification: `qa/material-diversity/review.md`.

## Travel-editing brand mark — 2026-09-27

`public/images/pixfun-mark.svg` is an original code-native vector mark: two folded segments form a forward-facing play symbol, suggesting both footage editing and a journey. Warm sand (#E6C38C) and muted brass (#CDA56C) pair with the dark-green canvas. This replaces the generic compass in the header, footer, and browser favicon. Existing body/heading typography stays unchanged; the wordmark now uses the already self-hosted DM Sans semibold font, lowercase with tighter letter spacing. No new font service or font download is required.

`public/images/pixfun-touch-icon.png` is a 180px rasterization of that SVG with a dark-green background and padding, generated with Sharp. Original compass and historic user-supplied icons remain on disk, unmodified. Adobe Fonts discovery was unavailable due to missing authorization; no Adobe font assets were obtained or used.

## Sharing destinations — 2026-09-27

`public/images/platforms/{youtube,tiktok,instagram,facebook}.svg` are unmodified Simple Icons 14.0.0 assets, downloaded from `https://cdn.jsdelivr.net/npm/simple-icons@14.0.0/icons/`. License: CC0, saved as `Simple-Icons-LICENSE.md` beside the assets. Platform trademarks remain their owners’ property; icon availability does not imply brand endorsement or a partnership. Review each platform's brand-use requirements before public deployment.

The landing page renders the icons in a subdued warm-gray monochrome using CSS, keeping their original geometry. Names are ordinary interface text, not recreated wordmarks. This non-interactive row communicates destinations for manual posting after export, not connected accounts, direct-publishing integrations, or automatic platform-specific export presets.

## Current input → output presentation — 2026-09-27

The example is now a **static, illustrative project**, not a playable output. Eight overlapping cards reuse licensed real stock frames (`coast`, `citywalk`, `luxury`, `roadtrip`, `food`, `citybreak`, `outdoors`, `hiking`). Older hero-only frames are reused here after those hero selections were replaced. The coast photo also anchors the output cover, intentionally linking input and output. Its title and duration badge are HTML/CSS; no AI image or photo modification was created.

“96 clips · 2 hr 18 min”, individual card filenames/durations, and the 20:18 cover duration are explicitly labeled sample project data, not the lengths of these underlying stock files or evidence of an actual generated twenty-minute film. No views, channel identity, YouTube embed, or play affordance is shown. The old example MP4 remains on disk but is not loaded by the page.

## Previous playable input → output example (superseded) — 2026-09-27

`public/media/travel/travel-edit-example.mp4` is a manually assembled, silent 12-second example (1280 × 720, 24 fps, H.264). It uses the existing licensed real stock sources listed below: coast.mp4 at 3–7 seconds, roadtrip.mp4 at 1–5 seconds, and hiking.mp4 at 5–9 seconds, joined with straight cuts. No AI imagery, synthetic audio, or claimed automatic generation. It appears only in the input/output section, not among the five independent hero cases.

The input list shows these same three source files (28.737, 10.093, and 10.260 seconds; displayed rounded to 29, 10, and 10 seconds). The direction is an illustrative brief matching this edit. The player is user-initiated with native controls, and the caption identifies it as a sample, not live output. No soundtrack, captions, or automatic color treatment is implied.

## Import device icons — 2026-09-26

`public/images/devices/{drone,smartphone,camera,video}.svg` are original Lucide library icons, downloaded from `https://github.com/lucide-icons/lucide/tree/main/icons`. Local license: `public/images/devices/Lucide-LICENSE.txt` (ISC, with inherited MIT notices). Only their display color is styled. These describe footage sources in the import workflow preview, not direct hardware connections.

## Travel Vlog redesign — 2026-09-26

All imagery used by the new landing page is real stock footage or frames extracted from it. No AI-generated people or images are shipped in the travel design. Historical assets below remain unused.

| Local source | Real footage / source page | License |
|---|---|---|
| media/travel/coast.mp4 | [Coast landscape aerial shot](https://mixkit.co/free-stock-video/coast-landscape-aerial-shot-1955/) | Mixkit Stock Video Free License |
| media/travel/roadtrip.mp4 | [Road trip as a couple aboard a van](https://mixkit.co/free-stock-video/road-trip-as-a-couple-aboard-a-van-41582/) | Mixkit Stock Video Free License |
| media/travel/hiking.mp4 | [Hiking couple taking a selfie](https://mixkit.co/free-stock-video/hiking-couple-taking-a-selfie-43150/) | Mixkit Stock Video Free License |
| media/travel/city.mp4 | [Venice central canal at night](https://mixkit.co/free-stock-video/venice-central-canal-at-night-4646/) | Mixkit Stock Video Free License |
| media/travel/camping.mp4 | [Parents and their daughter roasting marshmallows in a forest](https://mixkit.co/free-stock-video/parents-and-their-daughter-roasting-marshmallows-in-a-forest-39771/) | Mixkit Stock Video Free License |

Source pages and free-license labels checked on 2026-09-26. Stock performers are not represented as Pixfun customers; their nationality is not asserted. Context is western travel-Vlog audiences, not a fabricated American identity. Review the [Mixkit video license](https://mixkit.co/license/#videoFree) before public deployment.

- The original JPGs below were extracted from real footage; the current additional provider thumbnails are documented above.
- The original five 5-second previews are retained, superseded by the five 8-second thematic samples above.
- The selected case loops by itself, with no automatic case switching. A previously prepared montage is retained on disk but is not linked or loaded anywhere in the page, per the user's clarification.
- Fonts: self-hosted Lora (regular / italic) and DM Sans (regular / semibold), Google Fonts, SIL Open Font License. License files live beside the fonts.
- Brand: cream Lora wordmark plus a sand-colored Phosphor Compass icon. Icon comes from @phosphor-icons/core 2.1.1, MIT; its license is in public/images/Phosphor-LICENSE.txt. Recolored official SVG geometry, not a generated logo.
- Six-stage workflow is illustrative. Current supported import, analysis, scene thumbnails, captions, direction notes and existing text/crop export remain intact. Automatic montage, music and color finishing are explicitly labeled as planned workflow.

## Current assets

- `public/images/pixfun-logo.png`: supplied by the user, preserved unchanged.
- `public/images/speaker-medium.png`: current front-facing conference-speaker cover and second timeline shot.
- `public/images/speaker-wide.png`: first timeline shot, auditorium and stage overview.
- `public/images/speaker-audience.png`: third timeline shot, audience reaction.
- `public/images/speaker-close.png`: fourth timeline shot, speaker close-up.
- `public/images/speaker-male-suit.png`: male replacement reference and illustrative editing/export result. Generated from the earlier male presenter, now in a black suit with a handheld microphone and a new blue keynote stage; not a real video-processing output.

The original four shots were made with the built-in image-generation tool, not extracted from an actual recording. They share a speaker, wardrobe, and violet-lit conference setting. The four timeline slots use different image files, not alternate crops of one image. The creative-brief reference now shows the new male presenter. Entering editing cleanly switches the female cover to the male presenter, which remains through export; reverse scrolling restores the original. Presenters are never blended. Side panels exit fully before the next enters, and the media and editor share a top alignment. Static and reduced-motion layouts show both portraits side by side. The customization copy and FAQ explain that person replacement and translation are illustrative, not implemented processing features.

## Current generation prompts

### Closing CTA — creator studio background

Asset: `public/images/creator-studio-background.png` (2172 × 724). Generated with the built-in image-generation tool. Used as a decorative photograph beneath a dark CSS overlay; the headline and button remain live HTML.

Generated original: `/Users/daichuanqing/.codex/generated_images/01a0aa1f-af9a-7801-8216-8fbc68d82ad8/exec-8902f2a0-5d66-45b3-8816-eb840175cac2.png`.

Use case: ads-marketing. Asset type: a cinematic photographic background for the bottom call-to-action banner of Pixfun, a premium video-remix creation website. Ultra-wide landscape 3:1 composition, ideally 1536x512. A sophisticated dark video creator's editing studio at night: a professional compact cinema camera with a beautiful glass lens and focus rings sits in the far-left foreground; on the far-right, an angled editing monitor shows a few small cinematic video stills, including a conference speaker, a travel coast and a portrait, with a subtle purple editing timeline and no readable interface lettering. Refined charcoal-black surfaces, soft violet practical light and restrained cool blue screen reflections, authentic premium editorial photography, tactile materials, shallow depth of field. The middle 50 percent of the frame must remain mostly empty dark charcoal wall and desk atmosphere, softly illuminated but uncluttered, for overlaying a white headline and a purple button in HTML. Compose key objects across the middle horizontal band so a shallow 4:1 crop still shows the camera and monitor. Background should be visibly photographic yet calm and low contrast, not pure black. No people in the center, no words, no letters, no logos, no watermark, no rendered buttons, no page layout, no border. Final output is only the standalone studio background image.

### Male replacement — black suit and new stage (current)

Use case: identity-preserve. Edit target: the supplied photograph of a male speaker in a white shirt. Keep the SAME adult man's recognizable face, short dark hairstyle, light stubble and natural photographic appearance. Change his outfit to a beautifully tailored BLACK SUIT jacket and trousers over a crisp white dress shirt, open collar, no tie. Change his pose noticeably: he holds a wireless handheld microphone near his mouth in his right hand, his left hand relaxed at his waist, torso turned slightly three-quarter while his face looks toward the camera/audience, speaking with a confident warm expression. Remove the headset microphone. Change the background completely from violet panels to a sophisticated modern keynote auditorium: a large curved deep midnight-blue LED wall with soft abstract cyan light bands, warm amber stage spotlights high behind him and unobtrusive blurred audience along the very bottom. No text on screen. Medium waist-up, centered, landscape 3:2, generous headroom, subject and microphone fit inside the central 40% for vertical cropping. Professional realistic editorial conference photography, natural skin and anatomically correct hands, subtle cinematic depth. No logos, lettering, captions, watermark, UI or collage.

Generated original: `/Users/daichuanqing/.codex/generated_images/01a0aa1f-af9a-7801-8216-8fbc68d82ad8/exec-0743d4cb-dc51-4967-96ca-aa01de14dfcb.png`. The earlier white-shirt version remains in `public/images/speaker-male.png` but is no longer referenced by the page.

### Male replacement — white shirt (superseded)

Use case: precise-object-edit. Edit the supplied conference photograph. Replace ONLY the female speaker with a clearly different adult male presenter, around 35, short neatly styled dark hair, light stubble, a natural confident friendly expression, broader shoulders. He faces the camera speaking, wearing a white linen button-up shirt with rolled sleeves, light trousers and a small black headset microphone. Preserve the original person's center position, waist-up framing, hand gestures, scale, comfortable headroom, camera viewpoint and photographic realism. Preserve the exact dark charcoal conference stage, softly lit violet panels, audience silhouettes and light direction. This is an illustrative before/after identity-replacement demo, so the scene must match closely while the new person is obviously male. Natural editorial photography, realistic skin and hands, central subject fits a vertical 9:16 crop. Landscape 3:2, no text, labels, logos, watermark, borders or UI.

Generated original: `/Users/daichuanqing/.codex/generated_images/01a0aa1f-af9a-7801-8216-8fbc68d82ad8/exec-5a46e9cc-3af6-4362-9688-e0d978c9f372.png`.

### Main cover

Use case: precise-object-edit. Reference image is the woman in a white linen shirt. Keep her face, hair, adult age, natural appearance and white shirt consistent, but replace the setting and pose: she is giving a compelling talk on a tasteful modern conference stage, facing the camera, speaking with a small black headset microphone, one hand gesturing naturally. A medium-wide horizontal cinematic video frame: she is visible waist-up, centered, with comfortable headroom. Background is dark charcoal with softly lit muted violet stage panels, a few out-of-focus audience silhouettes along the very bottom, no branding or signage. Professional soft key light illuminates her face naturally; subtle violet stage rim light. Editorial conference photography, realistic texture, no glamour retouch. The speaker remains unobstructed inside the central 40% so the frame works as a portrait crop. Landscape 3:2. No text, logos, watermark, captions, borders or UI.

### wide

Edit target: the supplied conference-speaker scene. Create a distinctly different WIDE ESTABLISHING SHOT of the same talk: camera behind the audience at the back of the auditorium, the same woman in a white shirt and headset visible full body in the middle of the stage, rows of seated people in silhouette in the foreground. Preserve the dark charcoal and softly lit violet stage panels, the woman's identity, attire, and lighting. It must read unmistakably as a wide auditorium shot, not another medium portrait. Landscape 3:2 cinematic conference photography, crisp professional still, no text, logos, borders or UI.

### audience

Edit target/reference: the supplied conference scene. Create a new reverse-angle cutaway shot at the SAME event: medium close-up of three adult audience members seated in an auditorium, listening with attentive warm expressions, one holding a notebook. The speaker is out of frame. Match the subdued charcoal/violet stage lighting and cinematic realistic color grade from the reference. Clear human faces, natural candid conference photography. Distinct audience reaction B-roll, not the speaker and not a wide stage. Landscape 3:2. No text, logos, borders or UI.

### close

Edit target: the supplied conference-speaker scene. Create a distinctly different camera angle and shot size: CLOSE-UP head-and-shoulders portrait of the exact same woman, from a slight 20-degree side angle, looking toward the audience, speaking with an engaged expression. Her face fills much more of the frame than the reference. Preserve her exact face, dark shoulder-length hair, white linen shirt, black headset microphone, and charcoal/violet stage background. Shallow depth of field, natural editorial conference photography, cinematic detail. Landscape 3:2. No text, logos, borders or UI.

### Earlier front-facing coastal edit (superseded)

`public/images/creator-front.png` was generated using the built-in tool, then superseded by the speaker scene at the user's request. Prompt:

Use case: precise-object-edit. Edit target: the attached coastal travel photograph. Change the woman from a rear view to a front-facing medium portrait looking directly into the camera, with a natural friendly expression, as if speaking to her travel-video audience. She is an adult woman in her late twenties with shoulder-length dark hair, wearing the same relaxed white linen shirt. Preserve the rocky Mediterranean coastline, turquoise water, distant cliffs, horizon, warm afternoon light, realistic photographic textures and overall composition. Preserve the centered subject and landscape framing, with face and upper body fully visible, comfortable headroom, suitable for both horizontal video preview and central portrait crop. Hands relaxed, no props, no extra people. No text, no logos, no UI, no watermark. Natural editorial photography, not glamour retouching.


## Earlier assets (retained, not used by the current demo)

- `public/images/kold-my-year-2016.jpg`: official public thumbnail for **KOLD - My Year 2016**, by **kold**. Source: https://www.youtube.com/watch?v=QJbpJQscn9E ; image: https://i.ytimg.com/vi/QJbpJQscn9E/maxresdefault.jpg . Title and author checked against YouTube oEmbed on 2026-09-16. This is a cover image, not an extracted video frame. Credited in the local demo. No affiliation or commercial reuse permission is implied; obtain appropriate permission or replace with owned material before public marketing use.

## Superseded generated asset

`public/images/creator-scene.png` is retained but is no longer used by the page, following the request for a real popular-video image. Created with the built-in image-generation tool. Prompt:

> Use case: photorealistic-natural. Asset type: cinematic video still for a Pixfun video-editing product landing page. One original editorial travel photograph, landscape 3:2. An adult East Asian woman with shoulder-length dark hair in a simple white linen shirt viewed from behind, standing centered on a sunlit Mediterranean rocky coast looking at luminous turquoise sea. Low rough coastal stone foreground, green headland and sculptural cliffs at the sides, clear warm pale blue sky. Late afternoon sunlight, atmospheric film grain, editorial travel magazine quality, rich teal ocean, natural warm skin and ivory linen. The central subject must fit the central 40 percent for responsive compositions. Full bleed real photographic scene only, no user interface, no frames, no collage, no text, no logos, no watermark. Quiet cinematic authenticity, not oversaturated stock photography.

## Motion

## Selected Pixfun brand lockup — 2026-09-27

- `public/images/pixfun-lockup-v2.png` (1086 × 362): generated production variant of the selected opposing-filmstrip concept, with the user-requested capital P. Source: `exec-105ea764-e88e-4db9-98f3-7d0eee48d52e.png` in the task's generated-images directory. Direction: gold and ivory film-cut symbol, clean sans-serif “Pixfun” lettering, horizontal lockup on black. Resized for navigation/footer use.
- `public/images/pixfun-icon-v2.png`: 192 × 192 favicon/touch icon from generated `exec-512ac0cc-3821-4e3e-bb2f-a081e166327f.png`, using the same symbol on charcoal.
- `public/images/logo-effects.svg`: compositing filter only, not replacement logo geometry. Converts the raster black matte to transparency when displayed on video and dark surfaces. Transparent-generation attempts were rejected because of edge artifacts.
- Creator perspectives are illustrative scenario copy, not attributed customer endorsements. One disclosure remains below the six cards.

### Earlier motion notes

Five scenes: import → analysis → creative brief → script editing → export. The same media element persists across all scenes. Progress is a pure function, with smooth transitions and hold intervals. Native scrolling, one scheduled animation frame per scroll update, no wheel interception. Small viewports and reduced-motion preferences receive the full static narrative. The on-screen 32-second timeline is an illustrative edit, not actual analysis of a recorded talk. Person-reference and Spanish-language fields represent saved requirements, not an implemented identity replacement or translation pipeline.
# Landing case studies — October 2026

The five new `public/media/cases/` examples use individually verified Mixkit Stock Video Free License footage. Source pages and license links are visible in each detail page and recorded in `catalog.json`. The original downloads and source-page evidence are retained under `data/landing-cases-20261001/`; they are not imported into the user's media library.

| Case | Source | Full duration | Selected excerpt |
| --- | --- | --- | --- |
| Alpine scale | [Mixkit 51689](https://mixkit.co/free-stock-video/flying-over-a-monumental-rocky-mountain-with-visible-snow-and-51689/) | 22.773 s | 4–9 s |
| City after dark | [Mixkit 49846](https://mixkit.co/free-stock-video/side-by-side-aerial-view-of-a-city-at-night-49846/) | 43.752 s | 3–8 s |
| Small rituals | [Mixkit 43925](https://mixkit.co/free-stock-video/preparing-a-bowl-with-yogurt-and-fruit-43925/) | 24.900 s | 7–12 s |
| The human moment | [Mixkit 2385](https://mixkit.co/free-stock-video/man-enjoying-the-wind-2385/) | 23.941 s | 2–7 s |
| Coastal calm | [Mixkit 1564](https://mixkit.co/free-stock-video/white-sand-beach-background-1564/) | 20.687 s | 5–10 s |

Full examples are 1920×1080; separate muted 1280×720 five-second excerpts are used on the landing page. All five downloaded sources have no audio stream, so no transcript or environmental-sound claims are shown. Exact locations and devices are not identified. The local Qwen3-VL observations are retained separately from the editorial review: review corrected false cuts at sample-frame boundaries, unsupported motion, and food-order mistakes. Published descriptions and recommendations are curated examples, not unmodified model output or live inference. Action-stage boundaries inside continuous takes are explicitly labeled.

Rebuild derivatives with `node scripts/publish-landing-cases.mjs --render`; rebuild only metadata with `node scripts/publish-landing-cases.mjs`. Source downloads are reproducible using `node scripts/prepare-landing-cases.mjs` after rechecking licensing. No previous media files were replaced or removed.

## Creator Skill cover collection — October 2026

All nine Skills now use real stock-footage stills, recorded in `public/media/travel/skill-photo-covers.json`, with dedicated `skill-*-photo-v3.jpg` files. Food uses the real chef flambé frame to match the “first sizzle” copy. Card and detail covers preserve a 16:9 photographic composition. A subtle code-native inset border and sand-gold route motif decorate the photo without altering its content or adding interactive controls. Source pages and licenses are recorded per cover; original shared assets were not changed. The generated v2 collage drafts and prompt files remain unused for recovery and are not referenced by the catalog or packaged into the app. This supersedes the earlier generated Travel Vlog cover as well.
# Clean-footage landing revision — 2026-10-01 (current)

After the no-packaging review, examples 4 and 5 were replaced rather than cropping or blurring their original graphics. Example 1 also starts later to exclude its original title sequence. Public routes remain stable; current display order is Alaska, city, food, riverbank discovery, alpine wildlife.

| Example | Current excerpt | Cuts | Original source |
|---|---|---|---|
| Lake Clark, up close | 40.94s; source 25–65.90s | 4 | NPS Lake Clark film linked below; excludes the opening logo and titles |
| City after dark | 32s | 4 | Unchanged city montage below; real signs/billboards remain part of the scene |
| Food in the making | 24s | 3 | Unchanged food montage below |
| A riverbank discovery | 42.62s; source 69.25–111.85s | 5 | [Archeology with Brent Rowley](https://www.nps.gov/media/video/view.htm?id=261b879f-efa9-4f45-8dcb-8a20df93cdc5), NPS/Renata Harrison (2021) |
| Meet the alpine pika | 56.82s; source 0–56.80s | 6 | [Pikas with Jami Belt](https://www.nps.gov/media/video/view.htm?id=6D525AA8-497E-4B8C-970E-7A0106318E1E), NPS/Renata Harrison (2021) |

The selected excerpts were visually checked against chronological contact sheets and cut boundaries for baked-in subtitles, title cards and animated information graphics. They retain natural camera movement, live conversation or original narration. They are **clean excerpts of published footage**, not a claim that the files are unedited camera originals. No generated overlay or in-player caption track is added. Transcripts remain outside the player with click-to-seek and VTT download. On-screen interface controls and real environmental text are not erased.

The three changed examples were retranscribed and word-aligned locally against the final media. Official reference captions for the replacements are Pikas `010EBCDD-08FB-43D9-231F6292020E144E` and the archived Glacier archaeology VTT in `data/travel-long-20260927/`. These NPS captions use comma-delimited one-digit-hour timing; the publisher accepts that source format and emits standard WebVTT. The visual-model drafts were rerun and editorial descriptions/shots reviewed against the new content. Public overview titles are under 40 characters, English descriptions under 55 words; canonical Mac full descriptions retain 100–200 Chinese characters and the complete shot contract. The 10× hero title is unchanged.

# Multi-scene landing examples — earlier 2026-10-01 selection (superseded where noted above)

The five landing previews now use `public/media/cases/v2/`; each preview is a separate, silent 5-second encode. Detail pages play the complete 24–55-second **example excerpt or curated montage**, not the whole original source film. All examples are 16:9, encoded at 1280×720 without claiming source-native 1080p. The hero headline remains unchanged.

| Example | Complete example | Source / composition | Editorial split |
|---|---|---|---|
| Winter, explained | 55.14s | [NPS: Visiting Yellowstone, Winter Season](https://www.nps.gov/media/video/view.htm?id=ACBD450A-B52D-4DBF-A04C-2BEB4865A258), original 2.28–57.40s; NPS / Jacob W. Frank (2022) | 4 distinct ranger/settings |
| A city in motion | 32s | Mixkit [49846](https://mixkit.co/free-stock-video/side-by-side-aerial-view-of-a-city-at-night-49846/) (3–11s), [4332](https://mixkit.co/free-stock-video/times-square-during-a-rainy-night-4332/) (3–11s), [1606](https://mixkit.co/free-stock-video/city-train-driving-under-a-bridge-1606/) (4–12s), [42037](https://mixkit.co/free-stock-video/view-out-of-a-car-window-at-night-42037/) (2–10s) | 4 shots; unrelated locations explicitly disclosed |
| Made, poured, served | 24s | Mixkit [4678](https://mixkit.co/free-stock-video/chef-cooking-on-a-large-grill-4678/) (4–12s), [41859](https://mixkit.co/free-stock-video/serving-a-sparkling-cappuccino-in-a-cup-41859/) (0–8s), [43925](https://mixkit.co/free-stock-video/preparing-a-bowl-with-yogurt-and-fruit-43925/) (15–23s) | 3 scenes; not one restaurant or recipe |
| Inside Zion | 44.02s | [NPS: Zion Introduction Movie](https://www.nps.gov/media/video/view.htm?id=9FA3B222-155D-451F-67211732D9E00AEB), original 0–44s (2017) | 11 intervals, including brief original vista/crowd montage inserts |
| Alaska, up close | 54.94s | [NPS: Lake Clark Virtual Field Trip](https://www.nps.gov/media/video/view.htm?id=a7ea1719-005e-42cd-b7c9-79cda436ecad), original 11–65.90s; T. Vaughn and J. Pfeiffenberger (2018) | 5 shots, landscape → fishing activity → rapids |

NPS pages credit these films to NPS without a copyright symbol and identify such media as public domain. Mixkit pages list the Stock Video Free License. No speaker, agency, venue or contributor endorses Pixfun. NPS visitor advice and graphics are archived source content, not current travel advice. Provenance and excerpt offsets are visible in each detail page; these are precomputed demonstration examples, not uploaded-user data or customer outcomes.

Build: `scripts/build-multiscene-cases.py`. Local analysis: `scripts/analyze-multiscene-cases.py --speech`, then without the flag. It invokes the existing Mac `ModelGateway`, Whisper and Qwen3-VL, with the Mac description/shot instructions. Raw transcripts, model drafts, scene-change logs and contact sheets are in `data/landing-cases-v2/` (not publicly served). The visual model returned description drafts, **not reliable final shot boundaries**; final intervals and English editing recommendations are editorially reviewed, combining known montage cuts, scene-change candidates and frame inspection. Inferred dates, identities and unsupported ecological claims from drafts were discarded.

Publish/review: `scripts/publish-multiscene-cases.py` validates the 100–200-character canonical full descriptions and the Mac shot schema. English display descriptions are localized equivalents; they are not transcripts. Dialogue references only published verified cues. Sound-event arrays are empty because ASR is not an environmental-audio classifier. Highlight marks are editorial judgments, not claims of a validated automated quality score.

All three NPS examples retain their real narration. Whisper was run on the final excerpt files; its raw results are retained. Names and sentence boundaries were checked against the official NPS VTT tracks (Yellowstone `B4947EBE-A23F-B955-5FDB9E9BF5124518`, Zion `0A13C870-9F67-927E-CBBA0285C8B16E4F`, Lake Clark `FDDECA45-CC3E-3627-ADBC90693BF3F9E4`). `scripts/align-case-captions.py` uses the same installed Whisper model with word timestamps; publishing aligns corrected reference words to these real speech timings, failing closed when fewer than half a cue's tokens match. This avoids the original caption tracks' coarse offsets. Lake Clark's “designation” follows both ASR passes instead of the reference's “arrival.” The public VTTs and click-to-seek transcript contain the complete speech for these excerpts, not selected excerpts from speech. Captions remain precomputed and reviewed, not generated on each visitor page load. Silent stock montages have no transcript section.
