"""On-demand library aesthetic sorting. Never changes a project's shot order."""
import concurrent.futures
import math
import tempfile
import threading
import uuid
from pathlib import Path

from analysis_frames import extract_frame


class BeautySort:
    def __init__(self, agent):
        self.agent = agent
        self.lock = threading.Lock()
        self.jobs = {}
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)

    def request(self, payload):
        with self.lock:
            if 'jobId' in payload:
                key = payload['jobId']
                if not isinstance(key,str) or key not in self.jobs: raise ValueError('Unknown aesthetic sorting task.')
                return dict(self.jobs[key])
            ids = payload.get('mediaIds')
            if not isinstance(ids,list) or not 1 <= len(ids) <= 100 or any(not isinstance(v,str) for v in ids) or len(set(ids)) != len(ids):
                raise ValueError('Compare 1–100 imported photos or videos at a time.')
            if not self.agent.models.capabilities().get('localBeauty'):
                raise ValueError('The trained aesthetic model is not installed. Original order is kept.')
            if any(v['status']=='running' for v in self.jobs.values()):
                raise ValueError('An aesthetic comparison is already running.')
            # Resolve IDs here; client/model-supplied paths are never accepted.
            sources = [(mid,*self.agent.library.get(mid)) for mid in ids]
            if any(r.get('status')!='ready' or r.get('missing') or r.get('kind') not in ('image','video') for _,r,_ in sources):
                raise ValueError('Wait for these materials to finish importing before comparing.')
            key = uuid.uuid4().hex
            # Bound session history, keeping only the most recent completed task.
            self.jobs = {key:dict(id=key,status='running',completed=0,total=len(ids))}
            self.pool.submit(self._run,key,sources)
            return dict(self.jobs[key])

    def _run(self, key, sources):
        cancel = threading.Event()
        try:
            with tempfile.TemporaryDirectory(prefix='beauty-',dir=self.agent.root) as temp:
                frames, groups, signatures = [], [], {}
                for mid,record,path in sources:
                    stat = path.stat(); signatures[mid] = (stat.st_size,stat.st_mtime_ns)
                    duration = float((record.get('metadata') or {}).get('duration') or 0)
                    times = [duration*f for f in (.2,.5,.8)] if record['kind']=='video' and duration>0 else [None]
                    group = []
                    for at in times:
                        frame = Path(temp)/f'{len(frames)}.jpg'
                        extract_frame(self.agent.command,path,frame,cancel,at)
                        group.append(len(frames)); frames.append(str(frame))
                    groups.append(group)
                    with self.lock: self.jobs[key]['completed'] += 1
                result = self.agent.models.beauty(frames,cancel)
                values = result.get('scores')
                if not isinstance(values,list) or len(values)!=len(frames) or any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in values):
                    raise ValueError('The aesthetic model returned incomplete results. Original order is kept.')
                # Median of three representative frames: no promise to score a
                # whole video or replace the user's selected moment.
                medians = [sorted(values[i] for i in group)[len(group)//2] for group in groups]
                for mid,_,path in sources:
                    stat=path.stat()
                    if signatures[mid] != (stat.st_size,stat.st_mtime_ns):
                        raise ValueError('A source changed during comparison. Please compare again.')
                scores = {mid:score for (mid,_,_),score in zip(sources,medians)}
            with self.lock:
                self.jobs[key].update(status='completed',scores=scores,
                    note='Relative aesthetic order; videos use three sampled frames. Story order is unchanged.')
        except Exception:
            # No partial/fake order and no local paths exposed to the interface.
            with self.lock: self.jobs[key].update(status='failed',message='Aesthetic comparison did not finish. Original order is kept; check the installed model and source files.')
