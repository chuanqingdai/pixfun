"""No user media/model inference: synthetic frames, deterministic embeddings."""
import copy
import concurrent.futures
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT/'scripts'))
from media_catalog import MediaCatalog, source_key, representative_frames


class FakeLibrary:
    def __init__(self, root):
        self.source = root/'original.mp4'; self.source.write_bytes(b'fixture')
        self.items = {'one': {'id':'one','kind':'video','metadata':{'duration':4},'file':{'name':'original.mp4'}}}
    def list(self): return copy.deepcopy(list(self.items.values()))
    def get(self, key): return copy.deepcopy(self.items[key]), self.source
    def patch(self, key, **kwargs): self.items[key].update(kwargs)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        from types import SimpleNamespace
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.library = FakeLibrary(self.root)
        self.calls = []
        def local(job,cancel):
            self.calls.append(job)
            folder = Path(job['folder'])/'catalog'; folder.mkdir(parents=True)
            (folder/'shots.sqlite3').touch()
            return {'status':'ready'}
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.agent = SimpleNamespace(root=self.root/'agent',pool=self.pool,models=SimpleNamespace(local=local))
        self.catalog = MediaCatalog(self.library,self.agent)
    def tearDown(self): self.pool.shutdown(wait=True); self.tmp.cleanup()
    def finish(self): self.pool.submit(lambda:None).result(timeout=10)
    def test_index_keeps_existing_analysis_and_scopes_paths(self):
        self.library.items['one']['description']='A preserved description'
        response=self.catalog.start({'action':'index','ids':['one']}); self.finish()
        self.assertEqual(self.catalog.status()['indexed'],1)
        self.assertEqual(self.library.items['one']['description'],'A preserved description')
        self.assertTrue(Path(self.calls[0]['folder']).is_relative_to(self.agent.root))
        self.assertEqual(self.catalog.job['status'],'completed')
    def test_search_without_index_never_scans(self):
        self.catalog.start({'action':'search','query':'river'}); self.finish()
        self.assertEqual(self.calls,[])
        self.assertEqual(self.catalog.job['status'],'failed')
    def test_changed_source_is_excluded(self):
        self.catalog.start({'action':'index','ids':['one']}); self.finish()
        self.library.source.write_bytes(b'changed')
        self.assertEqual(self.catalog.status()['indexed'],0)
        self.assertEqual(self.catalog.status()['stale'],1)
    def test_new_reviewed_shots_invalidate_detector_only_index(self):
        from media_evidence import source_stamp, shot_revision
        self.catalog.start({'action':'index','ids':['one']}); self.finish()
        shots=[{'id':'canonical','start':0.,'end':4.}]
        self.library.items['one']['shotAnalysis']={'status':'ready','revision':shot_revision(shots),
            'sourceStamp':source_stamp(self.library.source),'segments':shots}
        self.assertEqual(self.catalog.status()['indexed'],0)
        self.assertEqual(self.catalog.status()['stale'],1)
    def test_cancel_before_running_keeps_previous_index(self):
        gate=threading.Event(); self.pool.submit(lambda:gate.wait(5))
        self.catalog.start({'action':'index','ids':['one']}); self.catalog.stop(); gate.set(); self.finish()
        self.assertEqual(self.calls,[])
        self.assertEqual(self.catalog.job['status'],'cancelled')
    def test_client_cannot_supply_paths(self):
        with self.assertRaises((ValueError,KeyError)): self.catalog.start({'action':'index','ids':['/etc/passwd']})
        with self.assertRaises(ValueError): self.catalog.start({'action':'search','query':[]})
    def test_action_frame_preserved_and_cut_avoided(self):
        frames=[]
        for i in range(20):
            p=self.root/f'{i}.jpg'; p.touch()
            frames.append({'t':i*.2,'path':str(p),'metrics':{'change':.9 if i==4 else 0}})
        selected=representative_frames({'frames':frames,'shots':[{'start':0},{'start':2}]},0,4)
        self.assertLessEqual(len(selected),4)
        self.assertIn(.8,[f['t'] for f in selected])
        self.assertNotIn(2,[f['t'] for f in selected])


class EngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import av, lancedb
            import vf_media_catalog
            from vf_agent import shot_library
        except ImportError: raise unittest.SkipTest('Run engine fixtures in the VisionFlow venv')
        cls.adapter = vf_media_catalog
        cls.shot_library = shot_library
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.root=Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()
    def video(self,name):
        import av, numpy as np
        path=self.root/name
        with av.open(str(path),'w') as c:
            s=c.add_stream('ffv1',rate=10); s.width=96; s.height=54; s.pix_fmt='yuv420p'
            for i in range(40):
                pixels=np.zeros((54,96,3),np.uint8); pixels[:,:,0 if i<20 else 2]=255
                f=av.VideoFrame.from_ndarray(pixels,format='rgb24')
                for packet in s.encode(f): c.mux(packet)
            for packet in s.encode(): c.mux(packet)
        return path
    def test_cached_scan_uses_actual_pts_and_cuts(self):
        source=self.video('scene.mkv'); folder=self.root/'cache'
        result=self.adapter.sample(source,folder)
        self.assertEqual(result['status'],'ready')
        self.assertGreaterEqual(len(result['observation']['shots']),2)
        self.assertTrue(all('pts' in f for f in result['observation']['frames']))
        with patch.object(self.adapter.sampling,'observe',side_effect=AssertionError('must reuse scan')):
            self.assertEqual(self.adapter.sample(source,folder),result)
    def test_unsupported_input_is_explicit(self):
        source=self.root/'hdr.mov'; source.write_bytes(b'fixture')
        with patch.object(self.adapter.sampling,'observe',side_effect=ValueError('HDR requires a validated tone-map path; pending review')):
            self.assertEqual(self.adapter.sample(source,self.root/'cache')['status'],'unsupported')
    def test_real_lancedb_federation_with_synthetic_vectors(self):
        import numpy as np
        class Encoder:
            queries=0
            def __init__(self,revision=None):
                self.spec=dict(model='fixture',revision='fixture',dimensions=768,normalization='l2',preprocessing='test',version=1)
            def encode(self,*,text=None,paths=None):
                if text is not None: Encoder.queries+=1
                result=np.zeros((1 if text else len(paths),768),np.float32); result[:,0]=1
                return result
        entries=[]
        with patch.object(self.shot_library,'Encoder',Encoder), patch.object(self.shot_library,'media_metadata',return_value={'status':'ok','data':{}}):
            for i in range(2):
                source=self.video(f'{i}.mkv'); folder=self.root/f'cache{i}'
                from media_evidence import shot_revision
                shots=[{'id':f'canonical-{i}','start':0.,'end':4.}]
                revision=shot_revision(shots)
                result=self.adapter.index(source,folder,{'tags':['river']},[],shots,revision)
                self.assertEqual(result['status'],'ready')
                entries.append({'mediaId':str(i),'folder':str(folder/('reviewed-'+revision))})
            result=self.adapter.search(entries,'river')
        self.assertEqual(Encoder.queries,1)
        self.assertEqual({h['mediaId'] for h in result['hits']},{'0','1'})
        self.assertFalse(result['unavailable'])
        self.assertTrue(all(0<=h['start']<h['end'] for h in result['hits']))
        self.assertEqual({h['shotId'] for h in result['hits']},{'canonical-0','canonical-1'})
        self.assertTrue(all(h['boundarySource']=='reviewed' and h['shotStart']==0 for h in result['hits']))
    def test_invalid_canonical_intervals_do_not_enter_catalog(self):
        from media_evidence import shot_revision
        source=self.video('invalid.mkv'); folder=self.root/'cache'
        for shots in ([{'id':'a','start':0.,'end':5.}],
                      [{'id':'a','start':0.,'end':2.},{'id':'b','start':1.,'end':4.}],
                      [{'id':'a','start':1.,'end':4.}]):
            with self.assertRaises(ValueError): self.adapter.index(source,folder,{},[],shots,shot_revision(shots))


if __name__=='__main__': unittest.main()
