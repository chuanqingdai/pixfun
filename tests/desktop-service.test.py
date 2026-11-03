"""Integration tests use a temporary desktop database, never the user's library."""
import json
import os
from pathlib import Path
import signal
import sqlite3
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
    def test_resolved_place_requires_native_auth_and_matching_gps(self):
        route='/api/desktop/analysis/place'
        with self.assertRaises(urllib.error.HTTPError) as denied: self.api(route,{})
        self.assertEqual(denied.exception.code,401)
        source=ROOT/'qa/media-library/captioned-test.mp4'
        key=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]['id']
        self.wait_ready(key)
        with sqlite3.connect(Path(self.temp.name)/'library.sqlite3') as db:
            record=json.loads(db.execute('SELECT record FROM media WHERE id=?',(key,)).fetchone()[0])
            record['metadata']['location']={'latitude':40.0036,'longitude':116.3181}
            db.execute('UPDATE media SET record=? WHERE id=?',(json.dumps(record),key))
        place={'version':2,'provider':'apple-geocoder','language':'zh-Hans','latitude':40.0036,'longitude':116.3181,
               'label':'北京市 · 海淀区 · 清华大学 · 双清路30号','area':'清华大学','nearbyName':'清华大学药学院','resolvedAt':1792100000}
        with self.assertRaises(urllib.error.HTTPError) as invalid:
            self.api(route,{'id':key,'place':{**place,'latitude':0}},native=True)
        self.assertEqual(invalid.exception.code,400)
        self.assertTrue(self.json(route,{'id':key,'place':place},native=True)['ok'])
        after=next(i for i in self.json('/api/desktop/library')['items'] if i['id']==key)
        self.assertEqual(after['resolvedPlace'],place)
        self.assertEqual(after['metadata']['location'],record['metadata']['location'])
        self.assertEqual(after['file'],record['file'])
        self.assertEqual(after.get('context'),record.get('context'))
        enriched={**place,'version':3,'provider':'apple-osm','displayName':'北京 清华大学',
                  'boundaryID':'area/3607469216','areaRelation':'inside','placeKind':'campus'}
        self.assertTrue(self.json(route,{'id':key,'place':enriched},native=True)['ok'])
        enriched_after=next(i for i in self.json('/api/desktop/library')['items'] if i['id']==key)
        self.assertEqual(enriched_after['resolvedPlace'],enriched)
        self.assertEqual(enriched_after['file'],record['file'])
        self.assertEqual(enriched_after['metadata']['location'],record['metadata']['location'])

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

    def test_multiple_removals_preserve_originals_and_can_be_restored(self):
        import hashlib
        import shutil
        sources = [Path(self.temp.name)/f'original-{index}.jpg' for index in range(3)]
        for source in sources:
            shutil.copyfile(ROOT/'public/media/travel/luxury.jpg', source)
        before = {str(p): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns) for p in sources}
        records = self.json('/api/desktop/register', {'paths': [str(p) for p in sources]}, native=True)['items']
        self.assertEqual(len(records), 3)
        for record in records:
            self.wait_ready(record['id'])
        for index, record in enumerate(records):
            self.json('/api/desktop/remove', {'id': record['id']})
            self.assertEqual(len(self.json('/api/desktop/library')['items']), 2-index)
        self.stop(); self.start()
        self.assertEqual(self.json('/api/desktop/library')['items'], [])
        for record in records:
            self.json('/api/desktop/restore', {'id': record['id']})
        self.assertEqual({r['id'] for r in self.json('/api/desktop/library')['items']}, {r['id'] for r in records})
        for source in sources:
            self.assertEqual((hashlib.sha256(source.read_bytes()).hexdigest(), source.stat().st_mtime_ns), before[str(source)])

    def test_language_setting_is_native_only_and_does_not_import(self):
        route = '/api/desktop/settings'
        with self.assertRaises(urllib.error.HTTPError) as denied:
            self.api(route, {'key':'language', 'value':'zh-Hans'})
        self.assertEqual(denied.exception.code, 401)
        with self.assertRaises(urllib.error.HTTPError) as invalid:
            self.api(route, {'key':'language', 'value':'unsupported'}, native=True)
        self.assertEqual(invalid.exception.code, 400)
        for language in ('zh-Hans', 'en'):
            self.assertTrue(self.json(route, {'key':'language', 'value':language}, native=True)['ok'])
            self.assertEqual(self.json(route)['settings']['language'], language)
            self.assertEqual(self.json('/api/desktop/library')['items'], [])

    def test_first_use_stays_empty_even_with_legacy_sample_environment(self):
        self.stop()
        from unittest.mock import patch
        with patch.dict(os.environ, {'PIXFUN_EXAMPLE_DIR': str(Path(self.temp.name)/'not-a-user-import')}):
            self.start()
        self.assertEqual(self.json('/api/desktop/library')['items'], [])

    def test_catalog_is_native_only_and_search_does_not_import(self):
        route='/api/desktop/agent/catalog'
        for payload in (None, {'action':'index','ids':[]}):
            with self.assertRaises(urllib.error.HTTPError) as denied: self.api(route,payload)
            self.assertEqual(denied.exception.code,401)
        status=self.json(route,native=True)
        self.assertEqual((status['indexed'],status['total']),(0,0))
        self.json(route,{'action':'search','query':'a river'},native=True)
        for _ in range(30):
            status=self.json(route,native=True)
            if status['job']['status']!='running': break
            time.sleep(.05)
        self.assertEqual(status['job']['status'],'failed')
        self.assertEqual(self.json('/api/desktop/library')['items'],[])

    def test_tag_corrections_native_only_and_preserve_filename(self):
        route='/api/desktop/agent/media-tags'
        with self.assertRaises(urllib.error.HTTPError) as denied: self.api(route,{})
        self.assertEqual(denied.exception.code,401)
        source=ROOT/'qa/media-library/captioned-test.mp4'
        key=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]['id']
        self.wait_ready(key)
        self.json(route,{'id':key,'hidden':['subject:people'],'added':[{'category':'activity','label':'Walking & hiking'}]},native=True)
        item=next(i for i in self.json('/api/desktop/library')['items'] if i['id']==key)
        self.assertEqual(item['tagCorrections']['added'][0]['id'],'activity:walking')
        self.assertEqual(item['file']['name'],source.name)
        with self.assertRaises(urllib.error.HTTPError) as invalid:
            self.api(route,{'id':key,'added':[{'category':'location','label':'Guessed place'}]},native=True)
        self.assertEqual(invalid.exception.code,400)
        item=next(i for i in self.json('/api/desktop/library')['items'] if i['id']==key)
        self.assertEqual(item['tagCorrections']['hidden'],['subject:people'])

    def test_access_control(self):
        for route in ('/api/desktop/description/start','/api/desktop/description/stop','/api/desktop/shots/start','/api/desktop/shots/stop'):
            with self.assertRaises(urllib.error.HTTPError) as denied:self.api(route,{})
            self.assertEqual(denied.exception.code,401)
            with self.assertRaises(urllib.error.HTTPError) as invalid:self.api(route,{},native=True)
            self.assertEqual(invalid.exception.code,400)
        with self.assertRaises(urllib.error.HTTPError) as denied:self.api('/api/desktop/analysis/reanalyze',{})
        self.assertEqual(denied.exception.code,401)
        self.assertEqual(self.json('/api/desktop/analysis/reanalyze',{},native=True)['queued'],0)
        with self.assertRaises(urllib.error.HTTPError) as denied:self.api('/api/desktop/analysis/retry-failed',{})
        self.assertEqual(denied.exception.code,401)
        self.assertEqual(self.json('/api/desktop/analysis/retry-failed',{},native=True)['queued'],0)
        for route,payload in [('/api/desktop/sync',None),('/api/desktop/sync',{}),('/api/desktop/agent/runs',None),('/api/desktop/agent/capabilities',None),('/api/desktop/agent/start',{}),('/api/desktop/agent/action',{}),('/api/desktop/agent/configure',{})]:
            with self.assertRaises(urllib.error.HTTPError) as denied:self.api(route,payload)
            self.assertEqual(denied.exception.code,401)
        for route,headers,status in [('/api/health',{'Authorization':''},401),('/api/health',{'Origin':'https://evil.test'},403),('/api/import',{},404)]:
            with self.assertRaises(urllib.error.HTTPError) as error:self.api(route,{} if route=='/api/import' else None,headers=headers)
            self.assertEqual(error.exception.code,status)
        with self.assertRaises(urllib.error.HTTPError) as error:self.api('/api/desktop/register',{'paths':[str(ROOT/'app.py')]})
        self.assertEqual(error.exception.code,401)
        result=self.json('/api/desktop/register',{'paths':[str(ROOT/'app.py')]},native=True)
        self.assertEqual(result['items'],[])

    def test_media_sync_real_photo_and_video_roundtrip(self):
        import shutil
        with tempfile.TemporaryDirectory(prefix='pixfun-sync-http-') as folder:
            root=Path(folder).resolve(); source=root/'card'; working=root/'working'; archive=root/'archive'
            for path in (source,working,archive): path.mkdir()
            shutil.copyfile(ROOT/'public/media/travel/luxury.jpg',source/'photo.jpg')
            shutil.copyfile(ROOT/'qa/media-library/captioned-test.mp4',source/'clip.mp4')
            self.json('/api/desktop/sync',{'action':'storage','kind':'working','path':str(working)},native=True)
            self.json('/api/desktop/sync',{'action':'storage','kind':'archive','path':str(archive)},native=True)
            result=self.json('/api/desktop/sync',{'action':'configure','name':'Test card','path':str(source),'kind':'camera','automatic':False,'photos':True,'videos':True,'importNow':True},native=True)
            key=result['devices'][0]['id']
            self.assertNotIn('root',result['devices'][0])
            def wait_sync():
                deadline=time.monotonic()+20
                while time.monotonic()<deadline:
                    snapshot=self.json('/api/desktop/sync',native=True)
                    # Snapshot reads source metadata before the future's busy flag;
                    # completion can occur between them. Require a terminal status
                    # too, rather than accepting an older Verifying/Scanning row.
                    terminal=snapshot['devices'][0]['status'] in ('Completed','Needs Attention','Paused')
                    if terminal and not snapshot['devices'][0]['busy'] and not snapshot['archiving']: return snapshot
                    time.sleep(.1)
                self.fail('Media Sync did not finish')
            snapshot=wait_sync()
            self.assertEqual(snapshot['devices'][0]['status'],'Completed')
            self.assertEqual(snapshot['devices'][0]['completed'],2)
            self.json('/api/desktop/sync',{'action':'archive'},native=True); snapshot=wait_sync()
            self.assertEqual(snapshot['archivePending'],0)
            items=self.json('/api/desktop/library')['items']
            self.assertEqual(len(items),2)
            for item in items: self.assertEqual(self.wait_ready(item['id'])['status'],'ready')
            self.assertEqual({item['file']['name'] for item in items},{'photo.jpg','clip.mp4'})
            self.assertTrue(all(item['syncSourceId']==key and item['syncSourceName']=='Test card' for item in items))
            self.stop(); self.start()
            self.json('/api/desktop/sync',{'action':'start','id':key},native=True)
            snapshot=wait_sync()
            self.assertEqual(snapshot['devices'][0]['skipped'],2)
            self.assertEqual(len(self.json('/api/desktop/library')['items']),2)
            self.assertEqual((source/'photo.jpg').read_bytes(),(ROOT/'public/media/travel/luxury.jpg').read_bytes())
            for suffix in ('jpg','mp4'):
                self.assertEqual(len(list(working.rglob('*.'+suffix))),1)
                self.assertEqual(len(list(archive.rglob('*.'+suffix))),1)

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
        self.assertGreater(record['importedAt'],0)
        duplicate=self.json('/api/desktop/register',{'paths':[str(source)]},native=True)['items'][0]
        self.assertEqual(duplicate['importedAt'],record['importedAt'],'Duplicate registration preserves the original import date')
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
        relinked=self.wait_ready(record['id'])
        self.assertEqual(relinked['importedAt'],record['importedAt'],'Relinking does not change the import date')
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
        # A small fixture can finish before the stop request reaches the service.
        # Completed work must remain ready, not be overwritten as cancelled.
        self.assertIn(stopped['status'],('cancelled','ready'))
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
