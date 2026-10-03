"""Real FFmpeg + system TTS; isolated projects, fixture model decisions (no GPU contention)."""
import array
import importlib.util
import json
import math
from pathlib import Path
import sys
import threading
import unittest
import wave

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('agent_contracts', ROOT/'tests/agent.test.py')
contracts = importlib.util.module_from_spec(spec); spec.loader.exec_module(contracts)
import agent_finishing as finishing
from music_library import catalog, credit


def tone(path, frequency, duration, active=None):
    # Fixtures only. The shipped renderer never synthesizes music.
    data=array.array('h',(round(6000*math.sin(2*math.pi*frequency*i/48000)) if active is None or i/48000 < active else 0 for i in range(round(duration*48000))))
    with wave.open(str(path),'wb') as output:
        output.setnchannels(1); output.setsampwidth(2); output.setframerate(48000); output.writeframes(data.tobytes())


class PolicyTests(unittest.TestCase):
    def test_audio_controls_preserve_levels_and_validate_mute_states(self):
        value = finishing.validate({'music':{'mediaId':'a','volume':0.3}, 'musicMuted':True,
            'narrationMuted':True, 'narrationVolume':0.6}, self.records, 6)
        self.assertTrue(value['musicMuted']); self.assertEqual(value['music']['volume'], 0.3)
        self.assertTrue(value['narrationMuted']); self.assertEqual(value['narrationVolume'], 0.6)
        self.assertEqual(finishing.resolve({}, value, finishing.request(None), self.records, 6), value)
        for invalid in ({'musicMuted':'yes'}, {'narrationMuted':1}, {'narrationVolume':float('nan')}, {'narrationVolume':2}):
            with self.assertRaises(ValueError): finishing.validate(invalid, self.records, 6)
        restored = finishing.resolve({}, {'originalMuted':True}, finishing.request({'originalAudio':'restore'}), self.records, 6)
        self.assertFalse(restored['originalMuted'])

    def test_muted_layers_are_not_sent_to_tts_or_music_input(self):
        from types import SimpleNamespace
        import tempfile
        commands = []
        engine = SimpleNamespace(command=lambda args, *a: commands.append(args), progress=lambda *a: None)
        value = finishing.validate({'music':{'mediaId':'a'}, 'musicMuted':True, 'narrationMuted':True,
            'narration':[{'start':0,'end':5,'text':'Muted voice'}]}, self.records, 6)
        with tempfile.TemporaryDirectory() as folder:
            finishing.mix(engine, {'id':'fixture','version':1}, Path(folder), 'base.mp4', 'out.mp4', value, 6, threading.Event())
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0].count('-i'), 1)
        self.assertNotIn('/usr/bin/say', commands[0])

    def setUp(self):
        self.records = {'a': {'id':'a','kind':'audio','metadata':{'duration':10},'file':{'name':'Music'}}}

    def test_unrequested_layers_ignored_and_negative_constraints_remove(self):
        proposal = {'music':{'mediaId':'a'}, 'narration':[{'start':0,'end':5,'text':'Hello'}], 'transition':{'kind':'fade'}}
        empty = finishing.resolve(proposal,{},finishing.request(None),self.records,6)
        self.assertNotIn('music',empty); self.assertFalse(empty['narration']); self.assertEqual(empty['transition']['kind'],'none')
        full = finishing.resolve(proposal,{},finishing.request({'music':'add','narration':'add','transition':'fade'}),self.records,6)
        preserved = finishing.resolve({},full,finishing.request(None),self.records,6)
        self.assertEqual(full,preserved)
        removed = finishing.resolve({},full,finishing.request({'music':'remove','narration':'remove','transition':'none'}),self.records,6)
        self.assertNotIn('music',removed); self.assertFalse(removed['narration'])

    def test_bad_sources_cues_commands_and_values_rejected(self):
        cases = [{'music':{'mediaId':'/etc/passwd'}}, {'music':{'mediaId':'a','volume':float('nan')}},
                 {'narration':[{'start':0,'end':7,'text':'Too long'}]},
                 {'narration':[{'start':0,'end':3,'text':'[[volm 1]] hello'}]},
                 {'narration':[{'start':0,'end':3,'text':'hi','voice':'shell'}]},
                 {'transition':{'kind':'shell'}}, {'originalVolume':True},
                 {'narration':[{'start':0,'end':4,'text':'hi'},{'start':3,'end':5,'text':'overlap'}]}]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(ValueError): finishing.validate(value,self.records,6)
        with self.assertRaisesRegex(ValueError,'missing'):
            finishing.resolve({}, {}, finishing.request({'music':'add'}), self.records,6)

    def test_bundled_catalog_and_credits(self):
        tracks = catalog(); self.assertEqual(len(tracks),3)
        for record, path in tracks.values():
            self.assertTrue(path.is_file()); self.assertGreater(path.stat().st_size,100000)
            self.assertIn('Kevin MacLeod',credit(record)); self.assertIn('CC BY 4.0',credit(record))

    def test_first_travel_film_defaults_and_explicit_opt_outs(self):
        wanted, automatic = finishing.travel_defaults(finishing.request(None), 'Create a travel video.', True, True)
        self.assertTrue(automatic)
        self.assertEqual((wanted['music'], wanted['transition'], wanted['narration']), ('add', 'fade', 'keep'))
        for prompt in ('No music, no transitions', '不要配乐，不要转场', 'original sound only, no effects'):
            result, automatic = finishing.travel_defaults(finishing.request({'music':'add','transition':'fade'}), prompt, True, True)
            self.assertFalse(automatic)
            self.assertEqual((result['music'], result['transition']), ('remove', 'none'))
        unchanged, automatic = finishing.travel_defaults(finishing.request(None), 'Shorten this shot', False, True)
        self.assertEqual(unchanged, finishing.request(None))
        self.assertFalse(automatic)
        missing, automatic = finishing.travel_defaults(finishing.request(None), 'Create a film', True, False)
        self.assertEqual(missing['music'], 'keep')
        self.assertFalse(automatic)
        records = {key:value[0] for key,value in catalog().items()}
        self.assertEqual(finishing.background_music(records)['mediaId'], 'music-life-of-riley')
        records.update(self.records)
        self.assertEqual(finishing.background_music(records)['mediaId'], 'a')

    def test_empty_rank_query_does_not_rank_edit_instructions(self):
        from agent_tools import tool_plan
        self.assertNotIn('rank',tool_plan('create',{'tools':['rank'],'query':''})['tools'])
        source=(ROOT/'scripts/agent-model-worker.py').read_text()
        self.assertIn('max_length=limit,truncation=True',source)


class RenderTests(unittest.TestCase):
    setUp = contracts.AgentTests.setUp
    tearDown = contracts.AgentTests.tearDown
    start = contracts.AgentTests.start

    def test_narration_gain_uses_real_mix_with_fixture_speech(self):
        # Only TTS is replaced by a deterministic tone; mix, AAC encode and decode are real.
        from types import SimpleNamespace
        folder = Path(self.temp.name); cancel = threading.Event()
        silence = folder/'silence.wav'; tone(silence, 440, 3, active=0)
        base = folder/'base.mp4'
        self.agent.command(['ffmpeg','-v','error','-y','-i',ROOT/'qa/media-library/captioned-test.mp4',
            '-i',silence,'-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-t','3',base], cancel)
        def command(args, *rest):
            if args[0] == '/usr/bin/say':
                tone(Path(args[args.index('-o')+1]), 770, 1)
                return b''
            return self.agent.command(args, *rest)
        engine = SimpleNamespace(command=command, progress=lambda *a: None)
        levels = []
        for gain, muted in ((1,False), (0.25,False), (1,True)):
            value = finishing.validate({'originalVolume':0, 'narrationVolume':gain, 'narrationMuted':muted,
                'narration':[{'start':0,'end':2,'text':'Fixture voice'}]}, {}, 3)
            output = folder/f'voice-{gain}-{muted}.mp4'
            finishing.mix(engine, {'id':'fixture','version':1}, folder, base, output, value, 3, cancel)
            data = self.agent.command(['ffmpeg','-v','error','-i',output,'-vn','-ac','1','-ar','8000','-f','f32le','-'], cancel)
            samples = array.array('f'); samples.frombytes(data)
            levels.append(math.sqrt(sum(x*x for x in samples[:6400]) / 6400))
        self.assertAlmostEqual(levels[1]/levels[0], 0.25, delta=0.03)
        self.assertLess(levels[2], 0.0001)

    def test_ducking_reduces_music_under_foreground_and_recovers(self):
        from types import SimpleNamespace
        folder=Path(self.temp.name); cancel=threading.Event()
        base=folder/'duck-base.mp4'; music=folder/'duck-music.wav'
        foreground=folder/'foreground.wav'; tone(foreground,440,6,active=2); tone(music,990,8)
        self.agent.command(['ffmpeg','-v','error','-y','-stream_loop','-1','-i',ROOT/'qa/media-library/captioned-test.mp4',
                            '-i',foreground,'-map','0:v:0','-map','1:a:0',
                            '-c:v','mpeg4','-c:a','aac','-t','6',base],cancel)
        record={'id':'qa-music','kind':'audio','file':{'name':'QA tone'},'metadata':{'duration':8}}
        engine=SimpleNamespace(command=self.agent.command,progress=lambda *a,**k:None,library=SimpleNamespace(get=lambda mid:(record,music)))
        values=finishing.validate({'music':{'mediaId':'qa-music','volume':.5,'ducking':True}}, {'qa-music':record},6)
        output=folder/'duck-output.mp4'
        finishing.mix(engine,{'id':'qa','version':1},folder,base,output,values,6,cancel)
        raw=self.agent.command(['ffmpeg','-v','error','-i',output,'-vn','-ac','1','-ar','8000','-f','f32le','-'],cancel)
        samples=array.array('f'); samples.frombytes(raw)
        def amplitude(start):
            data=samples[int(start*8000):int((start+.5)*8000)]
            a=sum(x*math.cos(2*math.pi*990*i/8000) for i,x in enumerate(data))
            b=sum(x*math.sin(2*math.pi*990*i/8000) for i,x in enumerate(data))
            return math.hypot(a,b)/len(data)
        self.assertGreater(amplitude(3.5),.01)
        self.assertLess(amplitude(1.2), amplitude(3.5)*.6, 'Music must be audibly attenuated during foreground sound')

    def test_trim_cannot_silently_drop_narration(self):
        self.configure({'narration':'add'}, {'narration':[{'start':2,'end':5.8,'text':'A new journey.'}]})
        run=contracts.wait(self.agent,self.start('Add narration')['id'])
        self.assertEqual(run['status'],'completed',run['message'])
        with self.assertRaises(ValueError):
            self.agent.action({'id':run['id'],'action':'timeline','version':run['version'],'timeline':[run['timeline'][0]]})
        self.assertEqual(self.agent.get(run['id'])['timeline'],run['timeline'])

    def configure(self, wanted, proposal):
        self.models.intent='create'; self.models.routerPatch={'finishingRequest':wanted,'duration':6}
        original=self.models.ask
        def ask(prompt,*args,**kwargs):
            answer=original(prompt,*args,**kwargs)
            if prompt.startswith('Plan an edit using only'):
                answer['shots']=[{'mediaId':self.asset,'start':0,'end':3,'label':'First','reason':'Fixture'},
                                 {'mediaId':self.asset,'start':0,'end':3,'label':'Second','reason':'Fixture'}]
                answer['finishing']=proposal
            return answer
        self.models.ask=ask

    def render(self, run):
        self.assertEqual(run['status'],'completed',run['message'])
        self.assertTrue(any(a['type']=='preview' for a in run['artifacts']))
        return run

    def test_music_narration_fade_automatic_preview_and_export_metadata(self):
        self.configure({'music':'add','narration':'add','transition':'fade'},
                       {'music':{'mediaId':'music-carefree'},'narration':[{'start':0,'end':5.5,'text':'Our journey begins here.'}]})
        run=contracts.wait(self.agent,self.start('Make a six second film with music, narration and fades')['id'])
        self.assertTrue(any('Our journey' in a['text'] for a in run['artifacts'] if a['type']=='finishing'))
        self.assertTrue(any(a['type']=='credits' for a in run['artifacts']))
        done=self.render(run); self.assertEqual(done['status'],'completed',done['message'])
        preview=next(a['path'] for a in done['artifacts'] if a['type']=='preview')
        probe=json.loads(self.agent.command(['ffprobe','-v','error','-show_format','-of','json',preview],threading.Event()))
        self.assertAlmostEqual(float(probe['format']['duration']),6,delta=.2)
        self.assertIn('Kevin MacLeod',probe['format']['tags']['comment'])
        # Fully decode, not merely checking the container header.
        self.agent.command(['ffmpeg','-v','error','-i',preview,'-f','null','-'],threading.Event())
        # The boundary should be near black; normal content remains visible elsewhere.
        def luminance(at):
            data=self.agent.command(['ffmpeg','-v','error','-ss',str(at),'-i',preview,'-frames:v','1','-vf','scale=1:1,format=gray','-f','rawvideo','-'],threading.Event())
            return data[0]
        self.assertLess(luminance(3.0),15)
        self.assertGreater(luminance(1.0),20)
        pcm=self.agent.command(['ffmpeg','-v','error','-i',preview,'-vn','-ac','1','-ar','16000','-f','f32le','-'],threading.Event())
        samples=array.array('f'); samples.frombytes(pcm)
        self.assertGreater(math.sqrt(sum(x*x for x in samples)/len(samples)),.005)

    def test_uploaded_music_is_not_transcribed_or_ignored(self):
        audio=Path(self.temp.name)/'music.wav'
        tone(audio,330,8)
        mid=self.library.register([str(audio)])['items'][0]['id']
        self.configure({'music':'add'}, {'music':{'mediaId':mid}})
        run=contracts.wait(self.agent,self.start('Use my attached music',mediaIds=[self.asset,mid])['id'])
        self.assertEqual(run['status'],'completed',run['message']); self.assertEqual(run['finishing']['music']['mediaId'],mid)
        self.assertFalse(any(a['type']=='subtitle' and a.get('mediaId')==mid for a in run['artifacts']))
        done=self.render(run); self.assertEqual(done['status'],'completed',done['message'])

    def test_speech_overflow_fails_instead_of_truncating(self):
        self.configure({'narration':'add'}, {'narration':[{'start':0,'end':.3,'text':'This long narration must never be silently cut off.'}]})
        done=contracts.wait(self.agent,self.start('Add narration')['id'])
        self.assertEqual(done['status'],'failed'); self.assertIn('speech was not cut off',done['message'])
        self.assertFalse(any(a['type']=='preview' for a in done['artifacts']))

    def test_scoped_request_cannot_change_global_music(self):
        self.models.intent='create'
        first=contracts.wait(self.agent,self.start()['id'])
        self.models.intent='modify'; self.models.routerPatch={'finishingRequest':{'music':'add'}}
        run=contracts.wait(self.agent,self.start('Add music to selection',id=first['projectId'],editScope={'runId':first['id'],'version':first['version'],'shotIds':[first['timeline'][0]['id']]})['id'])
        self.assertEqual(run['status'],'clarify'); self.assertIn('Clear the shot selection',run['question'])


if __name__=='__main__': unittest.main()
