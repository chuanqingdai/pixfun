"""Integration tests use a temporary desktop database, never the user's library."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
import urllib.request
import urllib.error

ROOT=Path(__file__).resolve().parents[1]
TOKEN='a'*64
NATIVE='b'*64


class DesktopServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='pixfun-service-test-')
        self.start()

    def start(self):
        env={**os.environ,'PIXFUN_DATA_DIR':self.temp.name,'PIXFUN_PUBLIC_DIR':str(ROOT/'public'),'PIXFUN_SERVICE_TOKEN':TOKEN,'PIXFUN_NATIVE_TOKEN':NATIVE,'PYTHONUNBUFFERED':'1'}
        command=[str(ROOT/'build-desktop/backend/pixfun-service/pixfun-service')] if os.environ.get('PIXFUN_TEST_FROZEN') else [str(ROOT/'.desktop-venv/bin/python'),str(ROOT/'desktop_service.py')]
        self.log=open(Path(self.temp.name)/'test.log','a')
        self.proc=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=self.log,text=True,env=env)
        line=self.proc.stdout.readline()
        if not line:
            self.proc.wait(timeout=5)
            raise RuntimeError((Path(self.temp.name)/'test.log').read_text())
        ready=json.loads(line)
        self.origin=f"http://127.0.0.1:{ready['port']}"

    def stop(self):
        self.proc.terminate()
        self.proc.wait(timeout=8)
        self.proc.stdout.close()
        self.log.close()

    def tearDown(self):
        if self.proc.poll() is None:self.stop()
        self.temp.cleanup()

    def api(self,route,payload=None,native=False,headers=None):
        request=urllib.request.Request(self.origin+route,data=json.dumps(payload).encode() if payload is not None else None,headers={'Authorization':'Bearer '+TOKEN,'Content-Type':'application/json',**({'X-Pixfun-Native':NATIVE} if native else {}),**(headers or {})})
        return urllib.request.urlopen(request,timeout=15)

    def json(self,*args,**kwargs):
        with self.api(*args,**kwargs) as response:return json.load(response)

    def wait_ready(self,media_id):
        deadline=time.monotonic()+45
        while time.monotonic()<deadline:
            record=next(x for x in self.json('/api/desktop/library')['items'] if x['id']==media_id)
            if record['status'] in ('ready','error','cancelled'):return record
            time.sleep(.1)
        self.fail('Analysis did not finish')

    def test_access_control(self):
        for route in ('/api/desktop/description/start','/api/desktop/description/stop','/api/desktop/shots/start','/api/desktop/shots/stop'):
            with self.assertRaises(urllib.error.HTTPError) as denied:self.api(route,{})
            self.assertEqual(denied.exception.code,401)
            with self.assertRaises(urllib.error.HTTPError) as invalid:self.api(route,{},native=True)
            self.assertEqual(invalid.exception.code,400)
        for route,payload in [('/api/desktop/agent/runs',None),('/api/desktop/agent/capabilities',None),('/api/desktop/agent/start',{}),('/api/desktop/agent/action',{}),('/api/desktop/agent/configure',{})]:
            with self.assertRaises(urllib.error.HTTPError) as denied:self.api(route,payload)
            self.assertEqual(denied.exception.code,401)
        for route,headers,status in [('/api/health',{'Authorization':''},401),('/api/health',{'Origin':'https://evil.test'},403),('/api/import',{},404)]:
            with self.assertRaises(urllib.error.HTTPError) as error:self.api(route,{} if route=='/api/import' else None,headers=headers)
            self.assertEqual(error.exception.code,status)
        with self.assertRaises(urllib.error.HTTPError) as error:self.api('/api/desktop/register',{'paths':[str(ROOT/'app.py')]})
        self.assertEqual(error.exception.code,401)
        result=self.json('/api/desktop/register',{'paths':[str(ROOT/'app.py')]},native=True)
        self.assertEqual(result['items'],[])

    def test_single_service_per_library(self):
        # Only one analyzer can own this library.
        env={**os.environ,'PIXFUN_DATA_DIR':self.temp.name,'PIXFUN_PUBLIC_DIR':str(ROOT/'public'),'PIXFUN_SERVICE_TOKEN':TOKEN,'PIXFUN_NATIVE_TOKEN':NATIVE,'PYTHONUNBUFFERED':'1'}
        second=subprocess.run([str(ROOT/'.desktop-venv/bin/python'),str(ROOT/'desktop_service.py')],env=env,capture_output=True,text=True,timeout=5)
        self.assertNotEqual(second.returncode,0)
        self.assertIn('already open',second.stderr)
        self.assertTrue(self.json('/api/health')['ok'])

    def test_people_feature_removed_without_erasing_old_data(self):
        legacy = Path(self.temp.name) / 'native-people.json'
        legacy.write_text('{"version":1,"people":[]}')
        for native in (False, True):
            for route, payload in [('/api/desktop/people', None), ('/api/desktop/people/scan', {}), ('/api/desktop/people/stop', {})]:
                with self.assertRaises(urllib.error.HTTPError) as removed:
                    self.api(route, payload, native=native)
                self.assertEqual(removed.exception.code, 404)
        self.stop(); self.start()
        self.assertEqual(legacy.read_text(), '{"version":1,"people":[]}')
        self.assertFalse((Path(self.temp.name) / 'people').exists())

    def test_native_locations_are_private_references_and_track_relinks(self):
        import shutil
        source=Path(self.temp.name).resolve()/'local photo.jpg'
        shutil.copyfile(ROOT/'public/media/travel/luxury.jpg',source)
        original=source.read_bytes()
        record=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        self.assertEqual(self.wait_ready(record['id'])['status'],'ready')
        with self.assertRaises(urllib.error.HTTPError) as error:self.api('/api/desktop/locations')
        self.assertEqual(error.exception.code,401)
        with self.assertRaises(urllib.error.HTTPError) as error:self.api('/api/desktop/locations',native=True,headers={'Origin':'https://evil.test'})
        self.assertEqual(error.exception.code,403)
        locations=self.json('/api/desktop/locations',native=True)['items']
        self.assertEqual(locations,[{'id':record['id'],'path':str(source)}])
        self.assertNotIn('path',self.json('/api/desktop/library')['items'][0])
        self.assertEqual(list((Path(self.temp.name)/'uploads').iterdir()),[])
        moved=source.with_name('moved photo.jpg');source.rename(moved)
        self.assertEqual(self.json('/api/desktop/locations',native=True)['items'][0]['path'],str(source),'Missing originals retain their indexed path')
        self.json('/api/desktop/locate',{'id':record['id'],'paths':[str(moved)]},native=True)
        self.wait_ready(record['id'])
        self.assertEqual(self.json('/api/desktop/locations',native=True)['items'][0]['path'],str(moved))
        self.json('/api/desktop/remove',{'id':record['id']})
        self.assertEqual(self.json('/api/desktop/locations',native=True)['items'],[])
        self.assertEqual(moved.read_bytes(),original,'Removing a reference never changes the original')
        self.json('/api/desktop/restore',{'id':record['id']})
        self.assertEqual(self.json('/api/desktop/locations',native=True)['items'][0]['path'],str(moved))

    def test_import_analysis_restart_and_original_reference(self):
        source=ROOT/'qa/media-library/captioned-test.mp4'
        if not source.exists():self.skipTest('local video fixture missing')
        original=source.stat().st_mtime_ns
        added=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        record=self.wait_ready(added['id'])
        self.assertEqual(record['status'],'ready',record.get('error'))
        self.assertTrue(record['metadata']['width'])
        self.assertTrue(record['result']['analysis']['segments'])
        self.assertTrue(record['result']['analysis']['subtitleCues'])
        self.assertEqual(list((Path(self.temp.name)/'uploads').iterdir()),[],'Original footage must not be copied')
        with self.api(added['url'],headers={'Range':'bytes=0-99'}) as response:
            self.assertEqual(response.status,206)
            self.assertEqual(len(response.read()),100)
        self.json('/api/desktop/update',{'id':record['id'],'favorite':True,'description':'My trip'})
        self.json('/api/desktop/settings',{'key':'skill','value':'Travel diary'})
        self.stop();self.start()
        restored=self.json('/api/desktop/library')['items'][0]
        self.assertTrue(restored['favorite']);self.assertEqual(restored['description'],'My trip')
        self.assertEqual(self.json('/api/desktop/settings')['settings']['skill'],'Travel diary')
        duplicate=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)
        self.assertEqual([item['id'] for item in duplicate['items']],[record['id']])
        self.assertEqual(duplicate['errors'],[])
        self.assertEqual(duplicate['items'][0]['status'],'ready')
        self.json('/api/desktop/remove',{'id':record['id']})
        self.assertEqual(self.json('/api/desktop/library')['items'],[])
        self.json('/api/desktop/restore',{'id':record['id']})
        self.assertEqual(len(self.json('/api/desktop/library')['items']),1)
        self.assertEqual(source.stat().st_mtime_ns,original)

    def test_missing_file_and_relink(self):
        import shutil
        source=Path(self.temp.name)/'photo.jpg'
        shutil.copyfile(ROOT/'public/media/travel/luxury.jpg',source)
        record=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        self.assertEqual(self.wait_ready(record['id'])['status'],'ready')
        moved=source.with_name('moved.jpg');source.rename(moved)
        self.assertTrue(self.json('/api/desktop/library')['items'][0]['missing'])
        self.json('/api/desktop/locate',{'id':record['id'],'paths':[str(moved)]},native=True)
        self.assertEqual(self.wait_ready(record['id'])['status'],'ready')
        self.assertEqual(len(self.json('/api/desktop/library')['items']),1)

    def test_stop_and_retry(self):
        source=ROOT/'public/media/travel/hero-citywalk.mp4'
        record=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        self.json('/api/desktop/stop',{})
        stopped=self.wait_ready(record['id'])
        self.assertEqual(stopped['status'],'cancelled')
        self.json('/api/desktop/retry',{'id':record['id']})
        self.assertEqual(self.wait_ready(record['id'])['status'],'ready')

    def test_audio_context_and_projects_survive_restart(self):
        import wave
        source=Path(self.temp.name)/'voice.wav'
        with wave.open(str(source),'wb') as audio:
            audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(16000);audio.writeframes(b'\x00\x00'*16000)
        source.with_suffix('.pixfun.json').write_text(json.dumps({'location':'Test location','credit':'Test fixture'}))
        item=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        record=self.wait_ready(item['id'])
        self.assertEqual(record['kind'],'audio');self.assertEqual(record['status'],'ready',record.get('error'))
        self.assertTrue(record['metadata']['hasAudio']);self.assertEqual(record['context']['location'],'Test location')
        self.json('/api/desktop/update',{'id':item['id'],'context':{'device':'Test recorder'}})
        draft=json.dumps({'prompt':'A draft request','attachments':[{'id':item['id'],'name':'voice.wav'}]})
        self.json('/api/desktop/settings',{'key':'projectDraft','value':draft})
        project=self.json('/api/desktop/projects',{'prompt':'A short travel story','mediaIds':[item['id']]})['project']
        continued=self.json('/api/desktop/projects',{'id':project['id'],'prompt':'Keep the voiceover','mediaIds':[item['id']]})['project']
        self.assertEqual(len(continued['messages']),2);self.assertEqual(continued['status'],'draft')
        self.stop();self.start()
        self.assertEqual(self.json('/api/desktop/projects')['projects'][0],continued)
        self.assertEqual(self.json('/api/desktop/settings')['settings']['projectDraft'],draft)
        self.assertEqual(self.json('/api/desktop/library')['items'][0]['context']['device'],'Test recorder')
        for payload in ({'prompt':''},{'prompt':'Invalid media','mediaIds':['missing']},{'id':'invalid','prompt':'Test'}):
            with self.assertRaises(urllib.error.HTTPError):self.json('/api/desktop/projects',payload)
        with self.assertRaises(urllib.error.HTTPError):self.json('/api/desktop/update',{'id':item['id'],'context':{'source':'untrusted overwrite'}})

    def test_long_video_has_bounded_honest_navigation(self):
        source=ROOT/'data/travel-long-20260927/Kennesaw - Woodland Ranger Talk.mp4'
        if not source.exists():self.skipTest('optional long field recording is not downloaded')
        item=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        record=self.wait_ready(item['id'])
        self.assertEqual(record['status'],'ready',record.get('error'))
        self.assertGreater(record['metadata']['duration'],500)
        analysis=record['result']['analysis']
        self.assertEqual(analysis['segmentationMethod'],'time-sampled')
        self.assertEqual(len(analysis['segments']),8)
        self.assertTrue(all(s.get('thumbnailUrl') for s in analysis['segments']))
        self.assertTrue(all(s['label'].startswith('Chapter') for s in analysis['segments']))
        self.assertNotIn('hookScore',analysis)

    def test_creator_skill_survives_project_and_draft_restart(self):
        skill={'id':'city-walk','title':'City walk','strategy':'Follow a route. Keep street sounds.'}
        scoped={**skill,'applicability':'Street footage and local sound; a route-led walk.'}
        scoped_project=self.json('/api/desktop/projects',{'prompt':'Use this scoped strategy','skill':scoped})['project']
        self.assertEqual(scoped_project['skill'],scoped)
        for invalid in [None,3,'', 'x'*401]:
            with self.assertRaises(urllib.error.HTTPError):
                self.json('/api/desktop/projects',{'prompt':'Invalid scope','skill':{**skill,'applicability':invalid}})
        draft=json.dumps({'prompt':'An unsent request','skill':skill,'attachments':[]})
        self.json('/api/desktop/settings',{'key':'projectDraft','value':draft})
        project=self.json('/api/desktop/projects',{'prompt':'A 3-minute city film','skill':skill})['project']
        self.assertEqual(project['skill'],skill)
        self.assertEqual(project['messages'][0]['skill'],skill)
        self.stop();self.start()
        self.assertEqual(self.json('/api/desktop/projects')['projects'][0]['skill'],skill)
        self.assertEqual(self.json('/api/desktop/settings')['settings']['projectDraft'],draft)
        cleared=self.json('/api/desktop/projects',{'id':project['id'],'prompt':'Continue without a skill','skill':None})['project']
        self.assertIsNone(cleared['skill']);self.assertEqual(cleared['messages'][0]['skill'],skill)
        for bad in ({'id':'x'}, {'id':'x','title':'x','strategy':'x'*4001}, {'id':'x','title':[],'strategy':'x'}):
            with self.assertRaises(urllib.error.HTTPError):self.json('/api/desktop/projects',{'prompt':'Test','skill':bad})


if __name__=='__main__':unittest.main()
