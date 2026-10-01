"""Offline contract tests: never transmit footage or consume API credits."""
import copy
import json
import os
import sys
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib import request, error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cloud_vision as vision
import app
from transcript_quality import repetitive, checked_cues


def fixture():
    return {key: 'A traveler stands on a sandy path beside green trees.' if key == 'summary' else [] for key in vision.CONTENT_FIELDS}


class CloudVisionTests(unittest.TestCase):
    def test_editing_summary_is_concise_and_separates_recommendations(self):
        for text in ('60 words maximum', 'Theme:', 'Key shots:', 'Suggested use:', 'Watch out:', 'at most 20 words', 'recommendation, never a claim'):
            self.assertIn(text, vision.INSTRUCTIONS)
        self.assertNotIn('80–160', vision.INSTRUCTIONS)

    def test_bounded_sampling_preserves_every_scene(self):
        segments=[{'id':str(i),'start':i*10,'end':(i+1)*10} for i in range(8)]
        frames=vision.frame_plan(segments)
        self.assertEqual(len(frames),24)
        for scene in segments:
            samples=[f for f in frames if f['id']==scene['id']]
            self.assertEqual(len(samples),3)
            self.assertTrue(all(scene['start'] < f['time'] < scene['end'] for f in samples))

    def test_no_key_never_calls_provider(self):
        with patch.dict(os.environ, {'OPENAI_API_KEY':''}), patch.object(vision,'send_response') as send:
            with self.assertRaises(vision.VisionError) as caught:
                vision.analyze_frames([])
            self.assertEqual(caught.exception.state,'not_configured')
            send.assert_not_called()

    def test_structured_multiframe_request_and_mapping(self):
        data=fixture();data['summary']='Actual visual description. '*50
        data['scenes']=[{'id':'seg-1',**fixture()}]
        def send(payload,key):
            self.assertEqual(key,'test-only')
            self.assertFalse(payload['store'])
            self.assertTrue(payload['text']['format']['strict'])
            self.assertEqual(payload['input'][0]['content'][1]['type'],'input_image')
            self.assertIn('untrusted',payload['instructions'])
            return {'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':json.dumps(data)}]}]}
        with patch.dict(os.environ,{'OPENAI_API_KEY':'test-only'}):
            result=vision.analyze_frames([{'id':'seg-1','time':1,'image':'data:image/jpeg;base64,fixture'}],send)
        self.assertEqual(result['assetUnderstanding']['summary'],data['summary'].strip())
        self.assertIn('seg-1',result['sceneUnderstanding'])
        self.assertEqual(result['visualAnalysis']['coverage'],'sampled_frames')
        self.assertNotIn('test-only',json.dumps(result))

    def test_refusal_incomplete_invalid_and_missing_scene(self):
        cases=[{'status':'incomplete'}, {'status':'completed','output':[{'type':'message','content':[{'type':'refusal'}]}]},
               {'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':'invalid'}]}]}]
        data={**fixture(),'scenes':[]}
        cases.append({'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':json.dumps(data)}]}]})
        with patch.dict(os.environ,{'OPENAI_API_KEY':'test-only'}):
            for response in cases:
                with self.assertRaises(vision.VisionError):
                    vision.analyze_frames([{'id':'seg-1','time':1,'image':'fixture'}],lambda *_:response)

    def test_repetition_is_rejected_not_rewritten(self):
        self.assertTrue(repetitive('surprise '*100))
        self.assertTrue(repetitive('thank you very much '*25))
        self.assertFalse(repetitive('No, no, no. Look at the beautiful view from this trail.'))
        good,bad=checked_cues([{'text':'surprise '*100},{'text':'We reached the village just before sunset.'}])
        self.assertEqual(bad,1);self.assertEqual(len(good),1)

    def test_http_boundary_and_missing_configuration(self):
        server=app.ThreadingHTTPServer(('127.0.0.1',0),app.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            with patch.dict(os.environ,{'OPENAI_API_KEY':''}):
                url=f'http://127.0.0.1:{server.server_port}/api/vision'
                for origin,status in [('https://untrusted.example',403),(f'http://127.0.0.1:{server.server_port}',503)]:
                    req=request.Request(url,data=b'{"jobId":"f6aa07a04b19"}',headers={'Content-Type':'application/json','Origin':origin})
                    with self.assertRaises(error.HTTPError) as caught:request.urlopen(req)
                    self.assertEqual(caught.exception.code,status)
                    payload=json.loads(caught.exception.read())
                    if status==503:self.assertEqual(payload['state'],'not_configured')
        finally:server.shutdown();server.server_close();thread.join()

    def test_native_does_not_dispatch_cloud(self):
        source=Path(__file__).resolve().parents[1].joinpath('desktop_service.py').read_text()
        post=source.split('    def do_POST(self):')[1].split('\ndef main()')[0]
        self.assertNotIn('super().do_POST',post)
        self.assertNotIn('handle_vision',post)
        self.assertNotIn('analyze_frames',source)


if __name__=='__main__':unittest.main()
