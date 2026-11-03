"""Real bundled H.264 source exports with isolated libraries and fixture planning."""
import importlib.util
import json
import os
from pathlib import Path
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
os.environ['PATH'] = str(ROOT/'build-desktop/media/bin') + os.pathsep + os.environ['PATH']
spec = importlib.util.spec_from_file_location('agent_contracts', ROOT/'tests/agent.test.py')
base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
from agent_export import profile, codec
from agent_models import CapabilityMissing


class ExportTests(unittest.TestCase):
    setUp = base.AgentTests.setUp
    start = base.AgentTests.start

    def plan(self, aspect='16:9'):
        self.models.intent = 'plan'
        run = base.wait(self.agent, self.start('Plan a short video')['id'])
        self.assertEqual(run['status'], 'completed', run['message'])
        run['timeline'][0].update(start=0, end=.5)
        run['aspect'] = aspect
        run['artifacts'].append(dict(id='preview-fixture', type='preview', title='Preview', text='', path='/not-an-original/preview.mp4'))
        self.agent.save(run)
        return self.agent.get(run['id'])

    def wait_export(self, job):
        deadline = time.monotonic()+90
        while job['status'] in ('queued', 'running'):
            self.assertLess(time.monotonic(), deadline, 'Export timeout')
            time.sleep(.05)
            job = self.agent.exports.action({'action':'status', 'exportId':job['id']})
        return job

    def export(self, run, **fields):
        return self.agent.exports.action(dict(id=run['id'], version=run['version'], **fields))

    def test_default_1080_from_original_keeps_preview_and_edit(self):
        run = self.plan(); commands = []; command = self.agent.command
        def record(args, *a, **kw): commands.append(list(map(str, args))); return command(args, *a, **kw)
        with patch.object(self.agent, 'command', side_effect=record):
            job = self.wait_export(self.export(run))
        self.assertEqual(job['status'], 'completed', job['message'])
        self.assertEqual((job['width'],job['height'],job['codec']), (1920,1080,'h264'))
        self.assertEqual(self.agent.get(run['id']), run)
        self.assertFalse(any('/not-an-original/preview.mp4' in c for c in commands))
        self.assertTrue(any(str(self.library.get(self.asset)[1]) in c for c in commands))
        manifest = json.loads((Path(job['path']).parent/'export.json').read_text())
        self.assertFalse(manifest['usesPreview'])
        self.assertEqual(manifest['timeline'], run['timeline'])

    def test_all_aspects_and_both_resolutions(self):
        run = self.plan()
        for quality, aspect, size in [('1080p','9:16',(1080,1920)), ('1080p','1:1',(1080,1080)),
                                      ('4k','16:9',(3840,2160)), ('4k','9:16',(2160,3840)), ('4k','1:1',(2160,2160))]:
            with self.subTest(quality=quality, aspect=aspect):
                run['aspect'] = aspect; self.agent.save(run)
                job = self.wait_export(self.export(run, resolution=quality))
                self.assertEqual(job['status'], 'completed', job['message'])
                probe = json.loads(self.agent.command(['ffprobe','-v','error','-show_streams','-of','json',job['path']], threading.Event()))
                video = next(s for s in probe['streams'] if s['codec_type'] == 'video')
                self.assertEqual((video['width'],video['height']),size)
                self.assertEqual(video['codec_name'],'h264')

    def test_invalid_quality_and_stale_version(self):
        run = self.plan()
        for fields in ({'resolution':'720p'}, {'version':0}, {'version':True}):
            with self.subTest(fields=fields), self.assertRaises(ValueError):
                self.agent.exports.action({'id':run['id'], 'version':run['version'], **fields})

    def test_missing_h264_does_not_downgrade(self):
        with self.assertRaises(CapabilityMissing): codec(profile('4k','16:9'), 'mpeg4 encoder')

    def test_missing_original_fails_without_changing_preview(self):
        run = self.plan()
        with patch('agent_export.fingerprint', side_effect=FileNotFoundError('Source offline')):
            with self.assertRaises(FileNotFoundError): self.export(run)
        self.assertEqual(self.agent.get(run['id']), run)

    def test_cancel_does_not_change_agent_or_publish_path(self):
        run = self.plan(); entered = threading.Event(); release = threading.Event(); command = self.agent.command
        def block(*args, **kwargs): entered.set(); release.wait(5); return command(*args, **kwargs)
        with patch.object(self.agent, 'command', side_effect=block):
            job = self.export(run)
            try:
                self.assertTrue(entered.wait(5))
                cancelled = self.agent.exports.action({'action':'cancel','exportId':job['id']})
                self.assertEqual(cancelled['status'],'cancelled')
            finally: release.set()
            self.agent.pool.submit(lambda: None).result(timeout=10)
        self.assertNotIn('path',self.agent.exports.get(job['id']))
        self.assertEqual(self.agent.get(run['id']),run)

    def test_edit_during_export_uses_snapshot(self):
        run = self.plan(); entered = threading.Event(); release = threading.Event(); command = self.agent.command
        def block(*args, **kwargs): entered.set(); release.wait(5); return command(*args, **kwargs)
        with patch.object(self.agent, 'command', side_effect=block):
            job = self.export(run)
            try:
                self.assertTrue(entered.wait(5))
                with self.assertRaises(ValueError): self.export(run)
                changed = [dict(run['timeline'][0],end=1)]
                updated = self.agent.action({'id':run['id'], 'version':run['version'], 'action':'timeline','timeline':changed})
            finally: release.set()
            job = self.wait_export(job)
        self.assertEqual(job['status'],'completed',job['message'])
        self.assertAlmostEqual(job['duration'],.5,delta=.1)
        self.assertEqual(job['timelineVersion'],run['version'])
        self.assertEqual(self.agent.get(run['id'])['timeline'],updated['timeline'])

    def test_source_change_after_render_rejects_result(self):
        run = self.plan()
        with patch('agent_export.SourceSnapshot.verify', side_effect=[None, ValueError('Source changed')]):
            job = self.wait_export(self.export(run))
        self.assertEqual(job['status'],'failed')
        self.assertNotIn('path',job)
        self.assertEqual(self.agent.get(run['id']),run)

    def test_layers_use_export_dimensions(self):
        run = self.plan()
        run['finishing'] = {'captions':[{'id':'caption','start':0,'end':.5,'text':'Original source export'}],
                            'clipAudio':[{'shotId':run['timeline'][0]['id'],'volume':.5,'muted':False}],
                            'originalVolume':.5, 'transition':{'kind':'fade','duration':.1}}
        self.agent.save(run)
        job = self.wait_export(self.export(run, resolution='4k'))
        self.assertEqual(job['status'],'completed',job['message'])
        self.assertEqual(job['width'],3840)
        manifest = json.loads((Path(job['path']).parent/'export.json').read_text())
        self.assertEqual(manifest['finishing'],run['finishing'])


if __name__ == '__main__': unittest.main()
