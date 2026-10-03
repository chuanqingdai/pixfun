"""Validated local finishing, independent of model/provider and original media storage."""
import math
import re
from pathlib import Path
from music_library import catalog, credit
import agent_layers


REQUEST_SCHEMA = '''For video edits also return finishingRequest:
{"music":"keep|add|remove","narration":"keep|add|remove","transition":"keep|fade|none","originalAudio":"keep|mute|restore"}.
Use keep unless the user explicitly asks to change that layer. Music uses attached audio or the bundled catalog;
do not generate or download music. Narration uses ordinary local macOS voices, never voice cloning.
fade means dip to black between clips (not cross-dissolve), preserving film duration.
Never interpret "no music", "不要旁白" or "no transitions" as add; use remove/remove/none.
'''

PLAN_SCHEMA = '''When finishingRequest asks for a layer, also output finishing:
{"music":{"mediaId":"attached audio ID","sourceStart":0,"volume":0.18,"loop":true,"ducking":true},
"narration":[{"start":0,"end":5,"text":"Short factual narration","voice":"Samantha","rate":175}],
"transition":{"kind":"fade","duration":0.25},"originalVolume":1}.
Omit unrequested layers. Narration times use the finished-film clock, never source time.
Keep narration short enough to fit its range at 175 words/minute with a safety margin. Use only observed facts;
no invented dialogue or claimed identities. Default voice Samantha (English), Tingting only for requested Chinese.
Use supplied previousFinishing for unchanged layers. music uses only attached audio IDs, not paths/URLs.
Show the actual narration script for approval. Do not claim audio has already been synthesized or mixed.
If the user supplies a quoted narration script, preserve its wording exactly; do not paraphrase it.
'''


def numeric(value, lo, hi):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not lo <= value <= hi:
        raise ValueError('Invalid finishing value or time range.')
    return float(value)


def request(value):
    if value is None: value = {}
    if not isinstance(value, dict): raise ValueError('Invalid finishing request.')
    allowed = {'music': ('keep', 'add', 'remove'), 'narration': ('keep', 'add', 'remove'),
               'transition': ('keep', 'fade', 'none'), 'originalAudio': ('keep', 'mute', 'restore')}
    result = {}
    for key, options in allowed.items():
        choice = value.get(key, 'keep')
        if choice not in options: raise ValueError('Unsupported finishing request: ' + key)
        result[key] = choice
    return result


def travel_defaults(wanted, prompt, enabled, music_available):
    """First travel films get a music bed and fades; edits keep existing layers.

    Explicit negatives win over both model output and skill defaults. Never add
    narration by default, and never acquire music from outside the chosen inputs.
    """
    wanted = dict(wanted)
    if re.search(r'\b(?:no|without)\s+(?:background\s+)?(?:music|bgm)\b|\boriginal (?:sound|audio) only\b|\bonly (?:the )?original (?:sound|audio)\b|不要(?:背景)?音乐|不加(?:背景)?音乐|不要配乐|不加配乐|仅(?:保留)?原声|只(?:保留|用)原声', prompt, re.I):
        wanted['music'] = 'remove'
    if re.search(r'\b(?:no|without)\s+(?:transitions?|fades?|effects)\b|不要(?:转场|特效)|不加(?:转场|特效)|硬切', prompt, re.I):
        wanted['transition'] = 'none'
    automatic_music = enabled and music_available and wanted['music'] == 'keep'
    if automatic_music: wanted['music'] = 'add'
    if enabled and wanted['transition'] == 'keep': wanted['transition'] = 'fade'
    return wanted, automatic_music


def background_music(records):
    """Prefer imported music; use the warm travel catalog track otherwise."""
    audio = [record for record in records.values() if record['kind'] == 'audio']
    uploaded = [record for record in audio if not record.get('musicCredit')]
    preferred = next((record for record in audio if record['id'] == 'music-life-of-riley'), None)
    record = (uploaded[0] if uploaded else preferred or (audio[0] if audio else None))
    if record is None: raise ValueError('No background music is available for this edit.')
    return {'mediaId': record['id'], 'sourceStart': 0, 'volume': .18, 'loop': True, 'ducking': True}


def validate(value, records, duration, shots=None):
    if not isinstance(value, dict): raise ValueError('Invalid finishing plan.')
    out = {'originalVolume': numeric(value.get('originalVolume', 1), 0, 1), 'narration': []}
    for key in ('musicMuted', 'narrationMuted'):
        if not isinstance(value.get(key, False), bool): raise ValueError('Invalid audio mute state.')
        out[key] = value.get(key, False)
    out['narrationVolume'] = numeric(value.get('narrationVolume', 1), 0, 1)
    music = value.get('music')
    if music is not None:
        if not isinstance(music, dict): raise ValueError('Invalid music track.')
        record = records.get(music.get('mediaId'))
        if not record or record['kind'] != 'audio': raise ValueError('Music must reference an attached audio file.')
        length = numeric((record.get('metadata') or {}).get('duration'), .01, 86400)
        start = numeric(music.get('sourceStart', 0), 0, length - .01)
        for key in ('loop', 'ducking'):
            if not isinstance(music.get(key, True), bool): raise ValueError('Invalid music option.')
        if not music.get('loop', True) and length - start < duration - .05:
            raise ValueError('Music is shorter than the edit. Enable looping or choose a longer track.')
        out['music'] = {'mediaId': record['id'], 'sourceStart': start, 'volume': numeric(music.get('volume', .18), 0, 1),
                        'loop': music.get('loop', True), 'ducking': music.get('ducking', True)}
    cues = value.get('narration', [])
    if not isinstance(cues, list) or len(cues) > 40: raise ValueError('Use at most 40 narration segments.')
    last = 0
    for cue in cues:
        if not isinstance(cue, dict): raise ValueError('Invalid narration segment.')
        start = numeric(cue.get('start'), last, duration)
        end = numeric(cue.get('end'), start + .25, duration)
        text = cue.get('text')
        if not isinstance(text, str) or not text.strip() or len(text) > 1500 or '[[' in text or ']]' in text:
            raise ValueError('Use plain narration text, without speech control commands.')
        voice = cue.get('voice', 'Samantha')
        if voice not in ('Samantha', 'Tingting'): raise ValueError('Choose an available standard English or Chinese voice.')
        out['narration'].append({'start': start, 'end': end, 'text': text.strip(), 'voice': voice,
                                 'rate': numeric(cue.get('rate', 175), 120, 220)})
        last = end
    transition = value.get('transition') or {'kind': 'none'}
    if not isinstance(transition, dict) or transition.get('kind') not in ('none', 'fade'):
        raise ValueError('Only cuts and fade-through-black transitions are supported.')
    out['transition'] = {'kind': transition['kind'], 'duration': numeric(transition.get('duration', .25), .05, 1)}
    return agent_layers.validate(value, out, duration, numeric, shots)


def resolve(proposal, previous, wanted, records, duration):
    """Only requested/skill-default layers may change; preserve earlier layers."""
    if not isinstance(proposal, dict): raise ValueError('Invalid finishing proposal.')
    value = dict(previous or {})
    for layer in ('music', 'narration'):
        if wanted[layer] == 'remove': value.pop(layer, None)
        elif wanted[layer] == 'add':
            if not proposal.get(layer): raise ValueError('The requested ' + layer + ' is missing from the plan.')
            value[layer] = proposal[layer]
            value[layer + 'Muted'] = False
    if wanted['transition'] != 'keep': value['transition'] = {'kind': wanted['transition'], 'duration': .25}
    if wanted['originalAudio'] != 'keep':
        value['originalVolume'] = 0 if wanted['originalAudio'] == 'mute' else 1
        value['originalMuted'] = wanted['originalAudio'] == 'mute'
    return validate(value, records, duration)


def transition_filters(finishing, index, count, length, shots=None):
    if shots is not None:
        filters=[]
        for other, incoming in ((index-1,True),(index+1,False)):
            if not 0 <= other < len(shots): continue
            left,right=(shots[other],shots[index]) if incoming else (shots[index],shots[other])
            seam=agent_layers.seam(finishing,left,right)
            if seam['kind'] != 'fade': continue
            fade=min(seam['duration'],(left['end']-left['start'])/3,(right['end']-right['start'])/3)
            filters.append(f'fade=t={"in" if incoming else "out"}:st={0 if incoming else length-fade}:d={fade}')
        return ','+','.join(filters) if filters else ''
    if finishing['transition']['kind'] != 'fade': return ''
    fade = min(finishing['transition']['duration'], length / 3)
    filters = []
    if index: filters.append(f'fade=t=in:st=0:d={fade}')
    if index < count - 1: filters.append(f'fade=t=out:st={length-fade}:d={fade}')
    return ',' + ','.join(filters) if filters else ''


def mix(engine, run, folder, base, target, finishing, duration, cancel):
    """All paths originate from the library or this task directory, never model output."""
    command = engine.command
    args = ['ffmpeg', '-v', 'error', '-y', '-i', base]
    gain=0 if finishing.get('originalMuted') else finishing['originalVolume']
    filters = [f'[0:a]aformat=sample_rates=48000:channel_layouts=stereo,volume={gain}[original]']
    speech_labels = []
    import json
    voice_gain = 0 if finishing.get('narrationMuted') else finishing.get('narrationVolume', 1)
    for index, cue in enumerate(finishing['narration'] if voice_gain > 0 else []):
        engine.progress(run['id'], f'Recording narration {index+1}/{len(finishing["narration"])}', 'render')
        if not Path('/usr/bin/say').is_file(): raise ValueError('Local narration requires macOS system voices.')
        script = folder / f'v{run["version"]}-narration-{index}.txt'
        audio = script.with_suffix('.aiff')
        script.write_text(cue['text'], encoding='utf-8')
        command(['/usr/bin/say', '-v', cue['voice'], '-r', str(int(cue['rate'])), '-f', script, '-o', audio], cancel, 120)
        probe = json.loads(command(['ffprobe', '-v', 'error', '-show_format', '-of', 'json', audio], cancel))
        length = float(probe.get('format', {}).get('duration') or 0)
        if not math.isfinite(length) or length <= .01:
            raise ValueError('The macOS voice produced no audio. Check that the system voice is installed and speech services are available, then retry.')
        if length > cue['end'] - cue['start'] + .03:
            raise ValueError(f'Narration {index+1} needs {length:.1f}s, but has {cue["end"]-cue["start"]:.1f}s. Shorten the script or give it more time; speech was not cut off.')
        args += ['-i', audio]
        label = f'voice{index}'
        filters.append(f'[{index+1}:a]aresample=48000,aformat=channel_layouts=stereo,volume={voice_gain},adelay={round(cue["start"]*1000)}:all=1,apad,atrim=duration={duration}[{label}]')
        speech_labels.append(f'[{label}]')
    foreground = '[original]' + ''.join(speech_labels)
    filters.append(f'{foreground}amix=inputs={1+len(speech_labels)}:duration=first:normalize=0[foreground]')
    music = None if finishing.get('musicMuted') else finishing.get('music')
    if music:
        engine.progress(run['id'], 'Mixing music and sound', 'render')
        bundled = catalog().get(music['mediaId'])
        record, source = bundled or engine.library.get(music['mediaId'])
        # Trim the chosen in-point before looping, so each repeat uses the same music range.
        prepared = folder / f'v{run["version"]}-music.wav'
        command(['ffmpeg', '-v', 'error', '-y', '-ss', str(music['sourceStart']), '-i', source,
                 '-vn', '-t', str(duration), '-ac', '2', '-ar', '48000', prepared], cancel, 120)
        if music['loop']: args += ['-stream_loop', '-1']
        args += ['-i', prepared]
        m = len(speech_labels) + 1
        fade = min(1, duration / 3)
        filters.append(f'[{m}:a]atrim=duration={duration},asetpts=PTS-STARTPTS,volume={music["volume"]},afade=t=in:d={fade},afade=t=out:st={duration-fade}:d={fade}[music]')
        if music['ducking']:
            filters += ['[foreground]asplit=2[fg][side]',
                        '[music][side]sidechaincompress=threshold=0.025:ratio=8:attack=20:release=350[ducked]',
                        '[fg][ducked]amix=inputs=2:duration=first:normalize=0[mixed]']
        else: filters.append('[foreground][music]amix=inputs=2:duration=first:normalize=0[mixed]')
        final = 'mixed'
    else: final = 'foreground'
    filters.append(f'[{final}]alimiter=limit=0.95:level=false:latency=true[out]')
    if music and credit(record): args += ['-metadata', 'comment=' + credit(record)]
    elif not music: args += ['-metadata', 'comment=']
    args += ['-filter_complex', ';'.join(filters), '-map', '0:v:0', '-map', '[out]', '-t', str(duration),
             '-c:v', 'copy', '-c:a', 'aac', '-ar', '48000', '-ac', '2', '-movflags', '+faststart', target]
    command(args, cancel, 300)


def summary(finishing, records):
    lines = []
    if finishing.get('music'):
        m = finishing['music']
        lines.append('Music: ' + records[m['mediaId']]['file']['name'] + (' · auto-ducking' if m['ducking'] else ''))
    if finishing['originalVolume'] == 0: lines.append('Original sound: muted')
    if finishing['transition']['kind'] == 'fade': lines.append('Transitions: fade through black')
    for c in finishing['narration']:
        lines.append(f'Voiceover {c["start"]:.1f}–{c["end"]:.1f}s ({c["voice"]}): {c["text"]}')
    return '\n'.join(lines)
