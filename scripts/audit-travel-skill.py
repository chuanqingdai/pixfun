"""Evidence audit of the current adapter against the imported v5.4 specification.

Does not mark the full skill passed from successful FFmpeg execution.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'build-native/travel-skill-audit'; folder.mkdir(exist_ok=True)
acceptance=json.loads((ROOT/'build-native/finishing-acceptance.json').read_text())
run=next(c['run'] for c in acceptance['checks'] if c['name']=='real-voice-music-transition-render' and c['pass'])
video=Path(next(a['path'] for a in run['artifacts'] if a['type']=='preview'))
ffmpeg=str(ROOT/'build-desktop/media/bin/ffmpeg'); ffprobe=str(ROOT/'build-desktop/media/bin/ffprobe')
def command(label,args):
    result=subprocess.run(args,capture_output=True,text=True,timeout=180)
    (folder/(label+'.log')).write_text(result.stderr)
    return result
probe=json.loads(subprocess.check_output([ffprobe,'-v','error','-count_frames','-show_streams','-show_format','-of','json',str(video)]))
v=next(s for s in probe['streams'] if s['codec_type']=='video'); a=next(s for s in probe['streams'] if s['codec_type']=='audio')
decode=command('decode',[ffmpeg,'-v','error','-xerror','-i',str(video),'-f','null','-'])
scan=command('scan',[ffmpeg,'-hide_banner','-nostats','-i',str(video),'-vf','blackdetect=d=0.02:pix_th=0.10,freezedetect=n=-50dB:d=1','-af','silencedetect=n=-50dB:d=0.2','-f','null','-'])
loudness=command('loudness',[ffmpeg,'-hide_banner','-nostats','-i',str(video),'-vn','-af','ebur128=peak=true','-f','null','-'])
summary=loudness.stderr.split('Summary:')[-1]
integrated=re.search(r'I:\s+(-?[\d.]+) LUFS',summary); peak=re.search(r'Peak:\s+(-?[\d.]+) dBFS',summary)
lufs=float(integrated[1]) if integrated else None; true_peak=float(peak[1]) if peak else None
report={'skill':'Travel Vlog 5.4','sourceSHA256':hashlib.sha256((ROOT/'creator-skills/visionflow-travel-director/SKILL.md').read_bytes()).hexdigest(),
        'adapterScope':run['skillExecution']['executionScope'],'overall':'NEEDS_REVIEW','fullSkillComplete':False,
        'preview':str(video),'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),
        'scope':'Two short repository travel clips. Real local model routing/planning, cached visual analysis, real system TTS and bundled FFmpeg. Not a full trip, mixed-format, dialogue or subjective listening acceptance.',
        'measured':{'duration':probe['format']['duration'],'videoCodec':v['codec_name'],'width':v['width'],'height':v['height'],'fps':v['r_frame_rate'],
                    'decodedFrames':v.get('nb_read_frames'),'audioCodec':a['codec_name'],'sampleRate':a['sample_rate'],'channels':a['channels'],'integratedLUFS':lufs,'truePeakDBTP':true_peak},
        'checks':[
            {'id':'real-model-finishing-chain','status':'PASS','evidence':'../finishing-acceptance.json'},
            {'id':'full-decode','status':'PASS' if decode.returncode==0 and not decode.stderr.strip() else 'FAIL','evidence':'decode.log'},
            {'id':'skill-output-specification','status':'PASS' if v['codec_name']=='h264' and v['width']>=1920 and v['height']>=1080 else 'FAIL','expected':'H.264, source-aware 1080p/4K; current app renders a 720p preview'},
            {'id':'48k-stereo','status':'PASS' if a['sample_rate']=='48000' and a['channels']==2 else 'FAIL'},
            {'id':'final-loudness','status':'UNVERIFIED' if lufs is None else 'PASS' if -17<=lufs<=-15 else 'FAIL','expected':'-16 +/- 1 LUFS','actual':lufs,'evidence':'loudness.log'},
            {'id':'final-true-peak','status':'UNVERIFIED' if true_peak is None else 'PASS' if true_peak<=-1 else 'FAIL','expected':'<= -1 dBTP','actual':true_peak,'evidence':'loudness.log'},
            {'id':'black-freeze-silence-scan','status':'UNVERIFIED','scanExitCode':scan.returncode,'evidence':'scan.log','reason':'Detections require semantic review against declared intentional intervals; the current timeline does not register them.'},
            {'id':'file-coverage','status':'PASS' if not run['skillExecution']['coverage']['requiresDecision'] else 'FAIL','evidence':run['skillExecution']['coverage']},
            {'id':'key-event-completeness','status':'UNVERIFIED','reason':'File exposure is not event or dialogue completeness.'},
            {'id':'music-listening-and-loop-boundaries','status':'UNVERIFIED','reason':'Author-supplied instrumental metadata and license checked; no full subjective listening.'},
            {'id':'full-skill-packaging','status':'FAIL','reason':'No chapter cards, location/scenery titles, burned-in dialogue subtitles, three cover candidates, portrait blurred backgrounds, photo animation or HDR/Log conversion.'},
            {'id':'speech-aware-ducking','status':'FAIL','reason':'Current sidechain reacts to all foreground energy. The skill forbids ordinary noise triggering dialogue ducking.'},
            {'id':'chapter-music-and-transitions','status':'FAIL','reason':'Single music bed after shot planning; no phrase/energy map, per-chapter tracks or specified 3+2+3-frame chapter transition/card.'},
            {'id':'reproducible-skill-delivery-package','status':'FAIL','reason':'Current run JSON and preview are not the complete project/state/media/visits/facts/story/copy/timeline/coverage/audio/qa/editing-notes delivery contract.'}
        ]}
(folder/'qa.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps({'report':str(folder/'qa.json'),'measured':report['measured'],'checks':[{k:c[k] for k in ('id','status')} for c in report['checks']]},indent=2))
