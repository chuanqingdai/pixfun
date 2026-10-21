"""Read-only real catalog verification through a temporary native service."""
import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import urllib.request
import urllib.error

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--query', default='湖边的风景')
parser.add_argument('--expected-assets', type=int)
parser.add_argument('--expected-shots', type=int)
args=parser.parse_args()
root=Path(__file__).resolve().parents[1]
app=Path((root/'build-native/connected-app-path.txt').read_text().strip())
config=json.loads((app/'Contents/Resources/vf-local.json').read_text())
token=os.urandom(32).hex(); native=os.urandom(32).hex()
report={}
with tempfile.TemporaryDirectory(prefix='pixfun-native-live-') as temp:
    env={**os.environ,**config,'PIXFUN_DATA_DIR':temp,'PIXFUN_SERVICE_TOKEN':token,
         'PIXFUN_NATIVE_TOKEN':native,'PIXFUN_AGENT_WORKER':str(root/'scripts/agent-model-worker.py')}
    with open(Path(temp)/'service.log','w+') as log:
        child=subprocess.Popen([sys.executable,'-u',str(root/'desktop_service.py')],env=env,stdout=subprocess.PIPE,stderr=log,text=True)
        try:
            sel=selectors.DefaultSelector();sel.register(child.stdout,selectors.EVENT_READ)
            assert sel.select(30),'Native service startup timed out'
            ready=json.loads(child.stdout.readline());base=f"http://127.0.0.1:{ready['port']}"
            def req(path, native_auth=True, payload=None, headers=None):
                h={'Authorization':'Bearer '+token}
                if native_auth:h['X-Pixfun-Native']=native
                if payload is not None:h['Content-Type']='application/json'
                h.update(headers or {})
                return urllib.request.urlopen(urllib.request.Request(base+path,headers=h,data=json.dumps(payload).encode() if payload is not None else None),timeout=120)
            def data(path,**kwargs):
                with req(path,**kwargs) as r:return json.load(r)
            status=data('/api/desktop/vf/status');report['catalog']=status
            rows=data('/api/desktop/library')['items']
            report['files']=len(rows);report['shots']=sum(len(r['result']['analysis']['segments']) for r in rows)
            assert report['files'] > 0 and report['shots'] >= report['files']
            if args.expected_assets is not None: assert report['files'] == args.expected_assets
            if args.expected_shots is not None: assert report['shots'] == args.expected_shots
            report['cues']=sum(len(r['result']['analysis']['subtitleCues']) for r in rows)
            report['excluded_cues']=sum(r['vfCatalog'].get('excludedTranscripts',0) for r in rows)
            assert len({r['id'] for r in rows})==len(rows)
            row=next(r for r in rows if r.get('coverUrl') and Path(r['vfCatalog']['source']).is_file())
            with req(row['coverUrl']) as response: assert response.read(3)==b'\xff\xd8\xff'
            with req(row['url'],headers={'Range':'bytes=0-31'}) as response:
                assert response.status==206 and len(response.read())==32
            assert Path(data('/api/desktop/native/'+row['id'])['path']).is_file()
            try:req('/api/desktop/library',native_auth=False);raise AssertionError('Native path protection missing')
            except urllib.error.HTTPError as error:assert error.code==401
            report['access_and_preview']='passed'
            original=next((r for r in rows if r['vfCatalog']['originalSource'] != r['vfCatalog']['source']
                           and Path(r['vfCatalog']['originalSource']).is_file()),None)
            if original:
                capture=data('/api/desktop/analysis/map-metadata',payload={'id':original['id']})['metadata']
                assert capture['metadataSource']=='catalog-linked-original' and 'duration' not in capture
                report['original_metadata_read']='passed'
            assert all(t['category']=='detail' for r in rows for t in r.get('analysisEvidence',{}).get('tags',[]))
            report['legacy_tags_kept_as_details']='passed'

            caps=data('/api/desktop/agent/capabilities')
            assert all(caps[k] for k in ['localText','localVision','localSpeech','localRetrieval'])
            report['capabilities']=caps
            from urllib.parse import urlencode
            query=urlencode(dict(similar=row['result']['analysis']['segments'][0]['id'],collection=row['vfCatalog']['collection']))
            similar=data('/api/desktop/vf/search?'+query)['matches']
            byid={r['id']:r for r in rows}
            assert similar and all(byid[r['mediaId']]['vfCatalog']['collection']==row['vfCatalog']['collection'] for r in similar)
            report['similar_same_trip']=len(similar)
            matches=data('/api/desktop/vf/search?'+urlencode({'q':args.query}))['matches']
            assert matches;report['semantic_hits']=len(matches)
            # A native favorite and title survive an explicit catalog refresh.
            data('/api/desktop/update',payload={'id':row['id'],'favorite':True,'title':'Native smoke title'})
            data('/api/desktop/vf/sync',payload={})
            saved=next(r for r in data('/api/desktop/library')['items'] if r['id']==row['id'])
            assert saved['favorite'] and saved['title']=='Native smoke title'
            report['annotation_preservation']='passed'
            (root/'data/vf-integration/native-http-check.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
            print(json.dumps({k:v for k,v in report.items() if k!='capabilities'},ensure_ascii=False))
        finally:
            child.terminate();child.wait(timeout=10);child.stdout.close()
