"""Adapter contracts: clock mapping, trust, local-only access and clip reuse."""
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from vf_bridge import BridgeError, Catalog, clip_analysis, prepare_clip
from vf_server import Handler


def shot():
    return dict(id='stable-shot', asset='trip/clip.mp4', start=2., end=4., online=True,
                playback=dict(start=2.025, end=4.025, origin=.025),
                representative='frame-1', context={'place': '湖边'}, scores={'beauty': None},
                metadata={'observation': {'fingerprint': ['file', 100, 200, 300]}},
                tags=[{'tag': '人工标记', 'origin': 'user'}], cover_choice={'locked': True},
                transcript_segments=[dict(start=1., end=3., overlap_start=2., overlap_end=3.,
                                         text='跨切点句子', searchable=True, human_verified=False),
                                     dict(start=3., end=4., overlap_start=3., overlap_end=4.,
                                          text='错误歌词', searchable=False),
                                     dict(start=3., end=4., overlap_start=3., overlap_end=4.,
                                          text='时钟不明', searchable=True, timing_status='legacy_clock_unverified')])


class AdapterTests(unittest.TestCase):
    def test_cues_rebased_clipped_and_untrusted_excluded(self):
        value = shot()
        result = clip_analysis(value, {'duration': 2.})
        self.assertEqual(result['subtitleCues'][0]['start'], 0.)
        self.assertEqual(result['subtitleCues'][0]['end'], 1.)
        self.assertTrue(result['subtitleCues'][0]['clipped'])
        self.assertEqual(result['transcript'], '跨切点句子')
        self.assertEqual(len(result['catalogEvidence']['excludedTranscripts']), 2)
        self.assertIsNone(result['catalogEvidence']['scores']['beauty'])
        self.assertTrue(result['catalogEvidence']['coverChoice']['locked'])
        self.assertEqual(result['segments'][0]['end'], 2.)

    def test_only_known_loopback_catalog_addresses(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder) / 'server.json'; client = Catalog(state)
            for url in ('https://example.com/' + 'a'*32 + '/',
                        'http://127.0.0.1:62600/' + 'a'*32 + '/?redirect=x',
                        'http://user:pass@127.0.0.1:62600/' + 'a'*32 + '/',
                        'http://localhost:62600/' + 'a'*32 + '/'):
                state.write_text(json.dumps({'url': url}))
                with self.assertRaises(BridgeError): client.base()
            url = 'http://127.0.0.1:62600/' + 'a'*32 + '/'
            state.write_text(json.dumps({'url': url}))
            self.assertEqual(client.base(), url)

    def test_search_preserves_filters_and_limits_pages(self):
        client = Catalog('unused'); client.json = Mock(return_value=[])
        client.search({'q': '湖边', 'tag': '人工标记', 'mode': 'text', 'k': '49', 'offset': '48'})
        self.assertEqual(client.json.call_args.args[1]['k'], '49')
        self.assertEqual(client.json.call_args.args[1]['offset'], '48')
        with self.assertRaises(BridgeError): client.search({'url': 'https://example.com'})
        with self.assertRaises(BridgeError): client.search({'k': '1001'})

    def test_ui_navigation_does_not_relax_api_origin_checks(self):
        handler = object.__new__(Handler)
        handler.server = SimpleNamespace(server_port=8765)
        handler.client_address = ('127.0.0.1', 10000)
        handler.command = 'GET'; handler.path = '/library'
        handler.headers = {'Host': '127.0.0.1:8765', 'Sec-Fetch-Site': 'cross-site',
                           'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'document'}
        self.assertTrue(handler.local_request())
        handler.path = '/api/vf/search'
        self.assertFalse(handler.local_request())
        handler.headers = {'Host': 'evil.example:8765'}
        self.assertFalse(handler.local_request())
        handler.headers = {'Host': '127.0.0.1:8765', 'Origin': 'http://localhost:9000'}
        self.assertFalse(handler.local_request())
        handler.headers = {'Host': '127.0.0.1:8765', 'Origin': 'http://127.0.0.1:8765'}
        self.assertTrue(handler.local_request())

    def test_edit_clip_identity_clock_and_reuse(self):
        with tempfile.TemporaryDirectory() as folder:
            jobs = {}; calls = []
            def run(args, **kwargs):
                calls.append(args); Path(args[-1]).write_bytes(b'encoded'); return 0, '', ''
            def read(ident):
                if ident not in jobs: raise FileNotFoundError(ident)
                return jobs[ident]
            engine = SimpleNamespace(UPLOADS=Path(folder), read_job=read,
                                     write_job=lambda j: jobs.update({j['id']:j}), run_command=run,
                                     probe_media=lambda _: {'available': True, 'duration': 2.},
                                     media_url=lambda kind, jid, name: f'/media/{kind}/{jid}/{name}')
            catalog = Catalog('unused'); value = shot()
            catalog.shot = Mock(return_value=value); catalog.base = Mock(return_value='http://127.0.0.1:62600/token/')
            catalog.open = Mock(side_effect=lambda *a, **kw: io.BytesIO(b'x'))
            result = prepare_clip(catalog, engine, value['id'])
            self.assertFalse(result['reused']); self.assertEqual(len(calls), 1)
            args = calls[0]
            self.assertEqual(float(args[args.index('-ss')+1]), 2.025)
            self.assertAlmostEqual(float(args[args.index('-t')+1]), 2.)
            self.assertEqual(args.count('-threads'), 2)
            self.assertTrue(prepare_clip(catalog, engine, value['id'])['reused'])
            self.assertEqual(len(calls), 1)
            self.assertEqual(catalog.open.call_count, 2)  # Revalidate before reuse.
            value['online'] = False
            with self.assertRaises(BridgeError): prepare_clip(catalog, engine, value['id'])
            self.assertFalse(catalog.work_lock.locked())

    def test_failed_duration_check_leaves_no_job_or_pending_clip(self):
        with tempfile.TemporaryDirectory() as folder:
            catalog = Catalog('unused'); catalog.shot = Mock(return_value=shot())
            catalog.base = Mock(return_value='http://127.0.0.1:62600/token/')
            catalog.open = Mock(side_effect=lambda *a, **kw: io.BytesIO(b'x'))
            engine = SimpleNamespace(UPLOADS=Path(folder), read_job=Mock(side_effect=FileNotFoundError),
                                     write_job=Mock(), probe_media=lambda _: {'available': True, 'duration': 40.})
            def run(args, **kwargs): Path(args[-1]).write_bytes(b'bad'); return 0, '', ''
            engine.run_command = run
            with self.assertRaisesRegex(BridgeError, 'duration'): prepare_clip(catalog, engine, 'stable-shot')
            engine.write_job.assert_not_called()
            self.assertFalse(list(Path(folder).rglob('*.mp4')))
            self.assertFalse(catalog.work_lock.locked())

    def test_only_one_heavy_task(self):
        client = Catalog('unused'); client.work_lock.acquire()
        try:
            with self.assertRaisesRegex(BridgeError, 'Another clip'): prepare_clip(client, None, 'shot')
        finally: client.work_lock.release()

    def test_frame_timebase_slash_and_video_ranges_are_relayed(self):
        for route, remote in (('/api/vf/frame/abc%3A123%3A1%2F90000', 'frame/abc%3A123%3A1%2F90000'),
                              ('/api/vf/video/shot-1', 'video/shot-1')):
            with self.subTest(route=route):
                response = io.BytesIO(b'frame')
                response.status = 206
                response.headers = {'Content-Type': 'image/jpeg', 'Content-Length': '5',
                                    'Content-Range': 'bytes 0-4/100', 'Accept-Ranges': 'bytes'}
                client = Mock(); client.open.return_value = response
                handler = object.__new__(Handler)
                handler.server = SimpleNamespace(catalog=client)
                handler.local_request = lambda: True
                handler.path = route; handler.headers = {'Range': 'bytes=0-4'}
                handler.wfile = io.BytesIO()
                handler.send_response = Mock(); handler.send_header = Mock(); handler.end_headers = Mock()
                handler.do_GET()
                client.open.assert_called_once_with(remote, headers={'Range': 'bytes=0-4'})
                handler.send_response.assert_called_once_with(206)
                self.assertEqual(handler.wfile.getvalue(), b'frame')
                handler.send_header.assert_any_call('Content-Range', 'bytes 0-4/100')


if __name__ == '__main__': unittest.main()
