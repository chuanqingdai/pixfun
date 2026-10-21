import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from desktop_service import Library
from vf_native import NativeCatalog, project_asset, validate_source


class NativeCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        self.source=self.root/'source.mp4'; self.source.write_bytes(b'media')
        st=self.source.stat()
        self.shot=dict(id='shot-1',asset='trip/clip.mp4',source=str(self.source),start=1.,end=5.,
            playback=dict(start=1.2,end=5.2,origin=.2), representative='frame:1/600',
            context=dict(place='Lake',collection='Trip',note='Unverified place'),tags=[dict(tag='Trip')],
            metadata=dict(observation=dict(fingerprint=[str(self.source.resolve()),st.st_size,st.st_mtime_ns,st.st_ino],transform=dict(rotation=90)),
                media=dict(data=dict(streams=[dict(codec_type='video',width=1920,height=1080),dict(codec_type='audio')]))),
            transcript_segments=[dict(id='t1',start=1,end=3,text='Good',searchable=True),
                dict(id='t2',start=3,end=4,text='Wrong singing',searchable=False),
                dict(id='t3',start=4,end=5,text='Wrong clock',searchable=True,timing_status='legacy_clock_unverified')],
            scores=dict(beauty=dict(max=4.2)),cover_choice=dict(locked=True),candidates=[])
        self.library=Library(self.root/'native')
        self.bridge=NativeCatalog(self.root/'server.json',self.library)
        self.bridge.catalog.search=lambda params:[copy.deepcopy(self.shot)]

    def tearDown(self): self.library.close(); self.temp.cleanup()

    def test_clock_rotation_and_transcript_quarantine(self):
        r,source=project_asset([self.shot]); a=r['result']['analysis']
        self.assertEqual((r['metadata']['width'],r['metadata']['height']),(1080,1920))
        self.assertEqual(a['segments'][0]['start'],1.2)
        self.assertEqual(a['subtitleCues'],[dict(start=1.2,end=3.2,text='Good',human_verified=False)])
        self.assertEqual(r['vfCatalog']['shots'][0]['scores'],self.shot['scores'])
        self.assertTrue(r['vfCatalog']['shots'][0]['cover_choice']['locked'])
        self.assertIn('frame%3A1%2F600',r['coverUrl'])
        validate_source(r,Path(source)); self.source.write_bytes(b'changed')
        with self.assertRaises(FileNotFoundError): validate_source(r,Path(source))

    def test_cached_capture_metadata_reaches_map_without_guessing(self):
        data=self.shot['metadata']['media']['data']
        data['format']={'tags':{'com.apple.quicktime.location.ISO6709':'+39.9000+116.4000/',
                               'com.apple.quicktime.model':'Test Camera',
                               'com.apple.quicktime.creationdate':'2024-10-01T12:00:00+08:00'}}
        r,_=project_asset([self.shot])
        self.assertEqual(r['metadata']['location']['latitude'],39.9)
        self.assertEqual(r['metadata']['camera'],'Test Camera')
        self.assertIn('Trip',r['analysisTags'])
        self.assertNotIn('com.apple.quicktime.model',r['analysisTags'])
        self.assertEqual(r['metadata']['capturedAt'],'2024-10-01T12:00:00+08:00')
        data['format']={'tags':{'creation_time':'2026-10-21T00:00:00Z'}}
        r,_=project_asset([self.shot])
        self.assertIsNone(r['metadata']['capturedAt'])
        self.assertIsNone(r['metadata']['location'])

    def test_refresh_preserves_edits_removal_and_does_not_enqueue(self):
        with patch.object(self.library,'enqueue',side_effect=AssertionError('must not rescan')):
            self.bridge.sync(); r=self.library.list()[0]
            self.library.patch(r['id'],favorite=True,title='My title',description='My note',context={'location':'Corrected'},tagCorrections={'hidden':['dog'],'added':[]},locationReview={'label':'Reviewed place'},importedAt=12345)
            self.bridge.sync(); again=self.library.list()[0]
            self.assertEqual(len(self.library.list()),1)
            self.assertEqual(again['title'],'My title'); self.assertTrue(again['favorite'])
            self.assertEqual(again['context']['location'],'Corrected')
            self.assertEqual(again['tagCorrections']['hidden'],['dog'])
            self.assertEqual(again['locationReview']['label'],'Reviewed place')
            self.assertEqual(again['importedAt'],12345)
            with self.library.connect() as db: db.execute('UPDATE media SET removed=1')
            self.bridge.sync(); self.assertEqual(self.library.list(),[])
            self.assertTrue((self.library.directory/'before-visionflow.sqlite3').is_file())

    def test_no_partial_publish_on_bad_page(self):
        self.bridge.sync()
        invalid=copy.deepcopy(self.shot); invalid['playback']['end']=float('nan')
        self.bridge.catalog.search=lambda params:[invalid]
        with self.assertRaises(ValueError): self.bridge.sync()
        self.assertEqual(len(self.library.list()),1)

    def test_missing_context_is_decodable_by_native_string_dictionary(self):
        self.shot['context'].update(place=None,collection=None,date=None)
        r,_=project_asset([self.shot])
        self.assertTrue(all(isinstance(v,str) for v in r['context'].values()))
        self.assertEqual(r['vfCatalog']['collection'],'')

    def test_similar_keeps_trip_and_maps_saved_identity(self):
        self.bridge.sync(); received=[]
        def search(p): received.append(p); return [self.shot]
        self.bridge.catalog.search=search
        rows=self.bridge.search(similar='shot-1',collection='Trip')
        self.assertEqual(received[0]['tag'],'Trip')
        self.assertEqual(rows[0]['start'],1.2)
        self.assertEqual(rows[0]['mediaId'],self.library.list()[0]['id'])

    def test_planning_reuses_ranges_without_model_or_editorial_signature(self):
        from agent_engine import AgentEngine
        from types import SimpleNamespace
        import threading
        r, source = project_asset([self.shot])
        agent = SimpleNamespace(ready_source=lambda *_: (r, Path(source)))
        with patch('shot_analysis.analyze_shots', side_effect=AssertionError('no repeat inference')):
            returned, result = AgentEngine.understand(agent, {'mode':'local', 'intent':'create'}, r['id'], threading.Event())
        self.assertIs(returned, r)
        self.assertEqual(result['segments'][0]['start'], 1.2)
        self.assertNotIn('editorial', result['segments'][0])
        self.assertNotIn('shotAnalysis', r)
        self.assertEqual([c['text'] for c in result['speechEvidence']['cues']], ['Good'])
        self.assertEqual(result['speechEvidence']['excluded'], 2)
        from agent_editor import source_speech
        speech=source_speech(agent, r, Path(source))
        self.assertEqual(speech['kind'],'asr')
        self.assertEqual(speech['cues'],[{'start':1.2,'end':3.2,'text':'Good'}])

        with patch('shot_analysis.analyze_shots', return_value=(r, {'segments':[]})) as analyze:
            AgentEngine.understand(agent, {'intent':'analyze'}, r['id'], threading.Event())
            analyze.assert_called_once()

    def test_catalog_evidence_rejects_changed_or_unbound_source(self):
        from vf_evidence import catalog_evidence
        r, source = project_asset([self.shot])
        no_fp = copy.deepcopy(r); no_fp['vfCatalog']['fingerprint'] = None
        self.assertIsNone(catalog_evidence(no_fp, source))
        self.source.write_bytes(b'changed')
        with self.assertRaises(FileNotFoundError): catalog_evidence(r, source)

    def test_original_header_read_never_changes_proxy_clock_or_user_place(self):
        original=self.root/'original.mp4'; original.write_bytes(b'original')
        self.shot['context']['original_source']=str(original)
        self.bridge.sync(); record=self.library.list()[0]
        before=copy.deepcopy(record)
        with patch('desktop_service.engine.probe_media', return_value=dict(available=True,
                duration=999, capturedAt='2024-10-01T12:00:00+08:00',location={'latitude':39.9,'longitude':116.4})) as probe:
            metadata=self.library.map_metadata(record['id'])
        probe.assert_called_once_with(original.resolve())
        self.assertEqual(metadata['metadataSource'], 'catalog-linked-original')
        self.assertNotIn('duration',metadata)
        self.assertEqual(self.library.get(record['id'])[0], before)
        original.unlink()
        with self.assertRaises(FileNotFoundError): self.library.map_metadata(record['id'])

    def test_legacy_detection_tags_are_details_not_primary_subjects(self):
        self.shot['tags'].extend([{'tag':'dog'}, {'tag':'Lake'}])
        self.bridge.sync(); record=self.library.list()[0]
        tag=record['analysisEvidence']['tags'][0]
        self.assertEqual((tag['label'],tag['category']),('dog','detail'))
        self.assertEqual(tag['evidence'][0]['start'],1.2)
        self.library.patch(record['id'], tagCorrections={'hidden':[tag['id']], 'added':[]})
        self.shot['tags'].append({'tag':'bird'})
        self.bridge.sync(); updated=self.library.get(record['id'])[0]
        self.assertEqual({t['label'] for t in updated['analysisEvidence']['tags']},{'dog','bird'})
        self.assertEqual(updated['tagCorrections']['hidden'],[tag['id']])

    def test_mixed_catalog_ranking_keeps_every_reference_without_fake_scores(self):
        from agent_tools import rank_available_evidence
        candidates=[{'id':'cached'}, {'id':'local','framePath':'frame.jpg'}, {'id':'cached2'}]
        def rank(paths):
            self.assertEqual(paths,['frame.jpg'])
            return {'scores':[.75]}
        ranked, missing=rank_available_evidence(candidates,candidates,rank)
        self.assertEqual([r['id'] for r in ranked],['cached','local','cached2'])
        self.assertEqual(missing,2)
        self.assertNotIn('similarity',ranked[0]); self.assertNotIn('similarity',ranked[2])
        self.assertEqual(ranked[1]['similarity'],.75)
        self.assertNotIn('similarity',candidates[1])

    def test_proxy_is_not_exported_as_an_original(self):
        from agent_export import SourceSnapshot
        from types import SimpleNamespace
        self.shot['context']['original_source'] = str(self.root/'camera-original.mp4')
        self.bridge.sync(); record=self.library.list()[0]
        engine=SimpleNamespace(library=self.library)
        with self.assertRaisesRegex(ValueError, '代理'):
            SourceSnapshot(engine, {'timeline':[{'mediaId':record['id']}], 'mediaIds':[record['id']]})
        self.assertTrue(self.source.is_file())

    def test_same_frame_display_repair_invalidates_cover_url(self):
        self.bridge.sync(); before=self.library.list()[0]['coverUrl']
        self.shot['frames']=[dict(frame_id=self.shot['representative'],display_sha256='repaired-pixels')]
        self.bridge.sync(); after=self.library.list()[0]['coverUrl']
        self.assertNotEqual(before,after)
        self.assertTrue(after.endswith('?v=repaired-pixels'))
        self.assertEqual(self.library.list()[0]['result']['analysis']['segments'][0]['thumbnailUrl'],after)

if __name__=='__main__':unittest.main()
