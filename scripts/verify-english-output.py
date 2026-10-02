"""Real local text-model language check; never opens the user's media library."""
import json
from pathlib import Path
import re
import sys
import tempfile
import threading

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from agent_models import ModelGateway
from agent_report import summarize_report
from video_description import DESCRIPTION_PROMPT, validate_description


def main():
    with tempfile.TemporaryDirectory(prefix='pixfun-english-') as directory:
        class CheckedGateway(ModelGateway):
            def ask(self,*args,**kwargs):
                try:
                    result=super().ask(*args,**kwargs)
                    print(json.dumps({'modelResult':result},ensure_ascii=False),flush=True)
                    return result
                except Exception as exc:
                    print(type(exc).__name__+': '+str(exc),flush=True)
                    raise
        gateway=CheckedGateway(directory);cancel=threading.Event()
        try:
            run={'prompt':'理解这些视频，做下分析','artifacts':[
                {'type':'analysis','mediaId':'camp','text':'一名穿橙色衬衫的人在户外打开背包，整理物品。\n用于展示营地准备过程。'}]}
            records={'camp':{'kind':'video','file':{'name':'camp.mp4'}}}
            report=summarize_report(run,records,{},gateway,cancel,'local')
            assert report['synthesized'], 'Report did not complete the real writing pass'
            assert not re.search(r'[\u4e00-\u9fff]',json.dumps(report,ensure_ascii=False)), 'Report was not English'
            description=gateway.ask(DESCRIPTION_PROMPT+'\nEvidence: Two travelers sit at a campsite table with cups. One lifts a cup. They face each other. A tent and trees are visible. No transcript or verified metadata is supplied. Evidence is sampled; do not invent dialogue, weather, location or relationships.',cancel,max_tokens=1600)
            validate_description(description)
            assert not re.search(r'[\u4e00-\u9fff]',json.dumps(description,ensure_ascii=False)), 'Description was not English'
            print(json.dumps({'scope':'Real local text inference on fixture evidence, not new visual analysis','report':report,'description':description,'passed':True},ensure_ascii=False,indent=2))
        finally: gateway.close()

if __name__=='__main__': main()
