"""Isolated queue tests; no real library, model or network access."""
import concurrent.futures
import copy
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from media_analysis import MediaAnalysis

class Library:
    def __init__(self):
        self.items={k:{'id':k,'kind':kind,'status':'ready','favorite':True,'description':'user note'}
                    for k,kind in [('v','video'),('p','image'),('a','audio')]}
    def get(self,k):return copy.deepcopy(self.items[k]),Path('/tmp/test-media')
    def patch(self,k,**fields):self.items[k].update(fields)
    def list(self):return [self.get(k)[0] for k in self.items]

class Controller:
    def __init__(self,lib,agent,field):
        self.lib,self.agent,self.field=lib,agent,field
        self.lock=threading.RLock();self.jobs={};self.fail=False;self.forces=[]
    def start(self,key,force=False):
        self.forces.append(force)
        old=self.lib.items[key].get(self.field,{})
        if not force and old.get('status') in ('ready','failed','cancelled','interrupted'): return old
        def work():self.lib.patch(key,**{self.field:{'status':'failed' if self.fail else 'ready','message':'test failure' if self.fail else ''}})
        self.jobs[key]=(threading.Event(),self.agent.pool.submit(work))
    def stop(self,key):pass
    def speech(self,item,*args):
        cues=[{'start':0,'end':1,'text':'Test speech'}]
        self.lib.patch(item['id'],result={'analysis':{'subtitleCues':cues}})
        return cues,'local'

class Tests(unittest.TestCase):
    def setUp(self):
        self.lib=Library();self.agent=Mock()
        self.agent.pool=concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.agent.ready_source.side_effect=lambda key,cancel:self.lib.get(key)
        self.agent.models.capabilities.return_value={'localSpeech':True}
        def observe(run,key,cancel,**kwargs):
            self.assertEqual(run,{'mode':'local'})
            self.lib.patch(key,analysisTags=['mountain'])
        self.agent.observe.side_effect=observe
        self.desc=Controller(self.lib,self.agent,'videoDescription')
        self.shots=Controller(self.lib,self.agent,'shotAnalysis')
        self.queue=MediaAnalysis(self.lib,self.agent,self.desc,self.shots)
    def tearDown(self):
        self.queue.close();self.agent.pool.shutdown(wait=True)
    def wait(self,key):self.queue.jobs[key][1].result(timeout=3)
    def until(self, predicate):
        deadline=time.monotonic()+3
        while not predicate() and time.monotonic()<deadline: time.sleep(.005)
        self.assertTrue(predicate())
    def test_completed_worker_timeout_does_not_stall_the_queue(self):
        self.queue.retry_delays=(60,60)
        self.agent.observe.side_effect=TimeoutError('Local inference timed out')
        self.queue.schedule('p');self.queue.schedule('a')
        self.wait('p');self.wait('a')
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'retrying')
        self.assertEqual(self.lib.items['a']['mediaAnalysis']['status'],'ready')
    def test_bounded_retries_release_lane_and_keep_revision(self):
        self.queue.retry_delays=(.01,.01)
        self.agent.observe.side_effect=TimeoutError('temporary')
        self.queue.schedule('p',force=True)
        revision=self.lib.items['p']['analysisRevision']
        self.until(lambda:self.lib.items['p']['mediaAnalysis']['status']=='failed')
        self.assertEqual(self.agent.observe.call_count,3)
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['attempt'],3)
        self.assertIsNone(self.lib.items['p']['mediaAnalysis']['nextRetryAt'])
        self.assertEqual(self.lib.items['p']['analysisRevision'],revision)
    def test_transient_failure_recovers_automatically(self):
        self.queue.retry_delays=(.01,)
        self.agent.observe.side_effect=[BrokenPipeError(),None]
        self.queue.schedule('p')
        self.until(lambda:self.lib.items['p']['mediaAnalysis']['status']=='ready')
        self.assertEqual(self.agent.observe.call_count,2)
    def test_stop_pending_retry_is_persistent_and_manual_retry_reuses_revision(self):
        self.queue.retry_delays=(60,)
        self.agent.observe.side_effect=TimeoutError()
        self.queue.schedule('p',force=True);self.wait('p')
        revision=self.lib.items['p']['analysisRevision']
        self.queue.stop('p')
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'cancelled')
        self.assertFalse(self.queue.retry_timers)
        self.queue.recover()
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'cancelled')
        self.agent.observe.side_effect=None
        self.queue.schedule('p');self.wait('p')
        self.assertEqual(self.lib.items['p']['analysisRevision'],revision)
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['attempt'],1)
    def test_restart_keeps_retry_deadline_and_attempt_budget(self):
        self.queue.retry_delays=(60,)
        self.agent.observe.side_effect=TimeoutError()
        self.queue.schedule('p');self.wait('p')
        deadline=self.lib.items['p']['mediaAnalysis']['nextRetryAt']
        self.queue.close()
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'retrying')
        self.queue=MediaAnalysis(self.lib,self.agent,self.desc,self.shots,retry_delays=(60,))
        self.queue.recover()
        self.assertIn('p',self.queue.retry_timers)
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['nextRetryAt'],deadline)
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['attempt'],1)
    def test_missing_original_is_not_retried(self):
        self.agent.ready_source.side_effect=FileNotFoundError('Original file missing')
        self.queue.schedule('p');self.wait('p')
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'failed')
        self.assertFalse(self.lib.items['p']['mediaAnalysis']['retryable'])
        self.assertFalse(self.queue.retry_timers)
    def test_retry_only_incomplete_stage_and_preserve_reviewed_shots(self):
        self.queue.retry_delays=(.01,)
        self.lib.items['v']['shotAnalysis']={'status':'ready'}
        calls=[]
        def description(key,force=False):
            calls.append(force)
            state={'status':'failed','message':'worker stopped','retryable':True} if len(calls)==1 else {'status':'ready'}
            self.lib.patch(key,videoDescription=state)
        self.desc.start=description
        with patch('video_description.reusable_shots',return_value=[{'id':'reviewed'}]):
            self.queue.schedule('v')
            self.until(lambda:self.lib.items['v']['mediaAnalysis']['status']=='ready')
        self.agent.observe.assert_not_called()
        self.assertEqual(calls,[False,True])
        self.assertEqual(self.shots.forces,[False,False])
    def test_recovery_does_not_reset_exhausted_budget(self):
        self.lib.items['p']['mediaAnalysis']={'status':'retrying','attempt':3,'nextRetryAt':0}
        self.queue.recover()
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'failed')
        self.assertNotIn('p',self.queue.jobs)
    def test_cancel_removes_model_task_that_has_not_started(self):
        future=concurrent.futures.Future();token=threading.Event();token.set()
        from agent_models import AgentCancelled
        with self.assertRaises(AgentCancelled):self.queue.wait(future,token)
        self.assertTrue(future.cancelled())
    def test_all_kinds_and_preserve_user_data(self):
        self.queue.recover(force_all=True)
        for k in self.lib.items:
            self.wait(k)
            self.assertEqual(self.lib.items[k]['mediaAnalysis']['status'],'ready')
            self.assertTrue(self.lib.items[k]['favorite'])
            self.assertEqual(self.lib.items[k]['description'],'user note')
            self.assertIn('analysisRevision',self.lib.items[k])
        self.assertEqual(self.lib.items['v']['analysisTags'],['mountain'])
        self.assertEqual(self.lib.items['p']['analysisTags'],['mountain'])
        self.assertEqual(self.lib.items['a']['result']['analysis']['subtitleCues'][0]['text'],'Test speech')
    def test_failure_not_ready_and_no_cloud_fallback(self):
        self.agent.observe.side_effect=ValueError('Model unavailable')
        self.queue.schedule('p');self.wait('p')
        self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'failed')
        self.assertEqual(self.agent.observe.call_count,1)
    def test_video_speech_survives_later_visual_failure(self):
        self.agent.observe.side_effect=ValueError('Visual model unavailable')
        self.queue.schedule('v');self.wait('v')
        self.assertEqual(self.lib.items['v']['mediaAnalysis']['status'],'failed')
        self.assertEqual(self.lib.items['v']['result']['analysis']['subtitleCues'][0]['text'],'Test speech')
    def test_secondary_failure_not_silently_ready(self):
        self.shots.fail=True
        self.queue.schedule('v');self.wait('v')
        self.assertEqual(self.lib.items['v']['mediaAnalysis']['status'],'failed')
        self.assertEqual(self.lib.items['v']['analysisTags'],['mountain'])
    def test_force_uses_new_revision_and_nonforce_reuses(self):
        self.queue.schedule('p',True);self.wait('p')
        old=self.lib.items['p']['analysisRevision']
        self.assertFalse(self.queue.schedule('p'))
        self.queue.schedule('p',True);self.wait('p')
        self.assertNotEqual(old,self.lib.items['p']['analysisRevision'])
    def test_dedup_and_explicit_cancel_not_auto_resumed(self):
        gate=threading.Event()
        self.agent.pool.submit(gate.wait)
        try:
            self.assertTrue(self.queue.schedule('p'))
            self.assertFalse(self.queue.schedule('p'))
            self.queue.stop('p');self.wait('p')
            self.assertEqual(self.lib.items['p']['mediaAnalysis']['status'],'cancelled')
        finally:gate.set()
    def test_interrupt_resume(self):
        self.lib.items['p']['mediaAnalysis']={'status':'interrupted'}
        self.lib.items['v']['mediaAnalysis']={'status':'cancelled'}
        self.lib.items['a']['mediaAnalysis']={'status':'failed'}
        self.queue.recover();self.wait('p')
        self.assertEqual(set(self.queue.jobs),{'p'})
    def test_interrupted_stages_resume_without_losing_completed_stages(self):
        self.lib.items['v']['mediaAnalysis']={'status':'interrupted'}
        self.lib.items['v']['videoDescription']={'status':'ready'}
        self.lib.items['v']['shotAnalysis']={'status':'interrupted'}
        self.queue.schedule('v');self.wait('v')
        self.assertEqual(self.desc.forces,[False])
        self.assertEqual(self.shots.forces,[True])
        self.assertEqual(self.lib.items['v']['mediaAnalysis']['status'],'ready')
    def test_failed_stages_are_not_replayed_after_internal_repair(self):
        self.shots.fail=True
        self.queue.schedule('v');self.wait('v')
        self.assertEqual(self.shots.forces,[False])
        self.assertEqual(self.lib.items['v']['mediaAnalysis']['status'],'failed')
    def test_retry_partial_shot_failure_keeps_completed_description(self):
        saved={'status':'ready','title':'Saved title','full_description':'Saved user-facing description'}
        self.lib.items['v'].update(mediaAnalysis={'status':'failed'},
                                   shotAnalysis={'status':'failed','message':'Incomplete JSON'},
                                   videoDescription=copy.deepcopy(saved))
        self.assertTrue(self.queue.schedule('v'))
        self.wait('v')
        self.assertEqual(self.shots.forces,[True])
        self.assertEqual(self.desc.forces,[False])
        self.assertEqual(self.lib.items['v']['videoDescription'],saved)
        self.assertEqual(self.lib.items['v']['shotAnalysis']['status'],'ready')
        self.assertEqual(self.lib.items['v']['mediaAnalysis']['status'],'ready')
    def test_description_resume_does_not_reobserve_completed_shots(self):
        self.lib.items['v']['shotAnalysis']={'status':'ready','sourceStamp':'fixture','revision':'fixture',
            'segments':[{'id':'s','start':0,'end':4,'label':'Saved shot'}]}
        self.lib.items['v']['videoDescription']={'status':'failed'}
        self.queue.schedule('v');self.wait('v')
        self.assertEqual(self.lib.items['v']['mediaAnalysis']['status'],'ready')
        self.agent.observe.assert_not_called()
        self.assertEqual(self.desc.forces,[True])
    def test_register_hooks_all_imports_and_avoids_duplicates(self):
        from desktop_service import Library as RealLibrary
        with tempfile.TemporaryDirectory() as tmp:
            lib=RealLibrary(Path(tmp)/'library')
            try:
                lib.enqueue=Mock();lib.content_analysis=Mock()
                path=Path(tmp)/'photo.jpg';path.write_bytes(b'test')
                first=lib.register([str(path)])
                lib.register([str(path)])
                lib.content_analysis.schedule.assert_called_once_with(first['items'][0]['id'])
            finally:lib.close()

if __name__=='__main__':unittest.main()
