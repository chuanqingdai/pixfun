"""Public case routes and seekable video, independent of user media state."""
import http.client
from pathlib import Path
import sys
import threading
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app

class LandingCaseRoutes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=app.ThreadingHTTPServer(('127.0.0.1',0),app.Handler)
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True)
        cls.thread.start()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown();cls.server.server_close();cls.thread.join()
    def get(self,path,headers=None):
        conn=http.client.HTTPConnection(*self.server.server_address,timeout=5)
        conn.request('GET',path,headers=headers or {})
        response=conn.getresponse(); result=(response.status,dict(response.getheaders()),response.read());conn.close();return result
    def test_five_routes_and_trailing_slashes(self):
        for name in ('alpine','citywalk','food','outdoors','islands'):
            for suffix in ('','/'):
                status,_,body=self.get('/stories/'+name+suffix)
                self.assertEqual(status,200);self.assertIn(b'id="caseVideo"',body)
        self.assertEqual(self.get('/stories/not-a-case')[0],404)
    def test_full_video_supports_seek_ranges(self):
        status,headers,body=self.get('/assets/media/cases/v3/food.mp4',{'Range':'bytes=100-199'})
        self.assertEqual(status,206);self.assertEqual(len(body),100)
        self.assertTrue(headers['Content-Range'].startswith('bytes 100-199/'))
    def test_catalog_and_asset_isolation(self):
        self.assertEqual(self.get('/assets/media/cases/catalog.json')[0],200)
        self.assertEqual(self.get('/assets/../data/landing-cases-20261001/sources.json')[0],404)
    def test_captions_are_served_as_webvtt(self):
        for name in ('alpine','outdoors'):
            status,headers,body=self.get('/assets/media/cases/v3/'+name+'.vtt')
            self.assertEqual(status,200);self.assertIn('text/vtt',headers['Content-Type'])
            self.assertTrue(body.startswith(b'WEBVTT'))

if __name__=='__main__':unittest.main()
