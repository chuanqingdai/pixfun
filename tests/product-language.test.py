"""Language policy tests; no user library and no external requests."""
from pathlib import Path
import sys
import threading
import unittest
from unittest.mock import patch
import json

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from product_language import ENGLISH_DEFAULT, explicitly_chinese
from agent_models import ModelGateway


class LanguageTests(unittest.TestCase):
    def test_only_explicit_language_instruction_overrides_default(self):
        for text in ['理解这些视频，做下分析','用这些素材做一个旅行视频','camp.mp4','Analyze the Chinese dialogue']:
            self.assertFalse(explicitly_chinese(text))
        for text in ['请用中文回答','使用简体中文输出','中文描述','Reply in Chinese']:
            self.assertTrue(explicitly_chinese(text))
    def test_local_model_receives_english_default(self):
        gateway=ModelGateway.__new__(ModelGateway);gateway.vision='fixture'
        requests=[]
        gateway.local=lambda payload,cancel: requests.append(payload) or {'summary':'English result'}
        gateway.ask('理解这些素材',threading.Event())
        self.assertTrue(requests[0]['prompt'].startswith(ENGLISH_DEFAULT))
        self.assertIn('理解这些素材',requests[0]['prompt'])
    def test_cloud_receives_identical_policy_without_real_request(self):
        gateway=ModelGateway.__new__(ModelGateway)
        gateway.cloud={'model':'fixture','visionModel':'fixture','apiKey':'test-key','baseURL':'https://api.openai.com/v1'}
        requests=[]
        class Response:
            def __enter__(self): return self
            def __exit__(self,*args): pass
            def read(self,*args): return json.dumps({'choices':[{'message':{'content':'{"summary":"English result"}'}}]}).encode()
        class Opener:
            def open(self,req,**kwargs): requests.append(json.loads(req.data));return Response()
        with patch('agent_models.request.build_opener',return_value=Opener()): gateway.ask('理解这些素材',threading.Event(),'cloud')
        self.assertTrue(requests[0]['messages'][1]['content'].startswith(ENGLISH_DEFAULT))
    def test_asr_keeps_source_language(self):
        gateway=ModelGateway.__new__(ModelGateway);gateway.speech='fixture'
        requests=[];gateway.local=lambda payload,cancel: requests.append(payload) or {'cues':[{'text':'出发吧'}]}
        result=gateway.transcribe('fixture.wav',threading.Event())
        self.assertEqual(result['cues'][0]['text'],'出发吧');self.assertNotIn('prompt',requests[0])

if __name__=='__main__': unittest.main()
