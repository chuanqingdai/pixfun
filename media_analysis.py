"""Persistent local-only understanding queue shared by every import source.

The coordinator waits outside the single model executor to avoid deadlocks.
Existing results stay visible until replacement inference succeeds.
"""
import concurrent.futures
import threading
import time
import uuid
from agent_models import AgentCancelled, retryable_analysis_error


class AnalysisFailure(Exception):
    def __init__(self, failures):
        super().__init__('; '.join(str(exc) for exc in failures))
        self.retryable = all(retryable_analysis_error(exc) for exc in failures)


class StageFailure(Exception):
    def __init__(self, state, field):
        super().__init__(state.get('message') or field + ' failed')
        self.retryable = state.get('retryable') is True


class MediaAnalysis:
    def __init__(self, library, agent, descriptions, shots, retry_delays=(10, 30)):
        self.library, self.agent = library, agent
        self.descriptions, self.shots = descriptions, shots
        self.lock = threading.RLock()
        self.jobs = {}
        self.retry_timers = {}
        self.retry_delays = tuple(retry_delays)
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.closing = False

    def update(self, key, **fields):
        item, _ = self.library.get(key)
        self.library.patch(key, mediaAnalysis={**(item.get('mediaAnalysis') or {}), **fields})

    def schedule(self, key, force=False, _resume=False):
        with self.lock:
            if self.closing: return False
            item, _ = self.library.get(key)
            if key in self.jobs and not self.jobs[key][1].done(): return False
            old = item.get('mediaAnalysis') or {}
            if not force and old.get('status') == 'ready': return False
            if key in self.retry_timers:
                if not force and not _resume: return False
                self.retry_timers.pop(key).cancel()
            if force:
                # New signatures rerun inference without deleting earlier cache/results.
                self.library.patch(key, analysisRevision=uuid.uuid4().hex)
            self.update(key, status='queued', message='Waiting for local content analysis', force=force,
                        attempt=old.get('attempt', 0) if _resume else 0, nextRetryAt=None,
                        maxAttempts=1+len(self.retry_delays), retryable=None)
            cancel = threading.Event()
            future = self.pool.submit(self.run, key, cancel)
            self.jobs[key] = (cancel, future)
            future.add_done_callback(lambda _: self.arm_retry(key, cancel))
            return True

    def arm_retry(self, key, cancel=None):
        """Delayed retries never sleep on the coordinator/model lane."""
        with self.lock:
            if self.closing or (cancel is not None and cancel.is_set()): return
            try: item, _ = self.library.get(key)
            except FileNotFoundError: return
            state = item.get('mediaAnalysis') or {}
            if state.get('status') != 'retrying' or key in self.retry_timers: return
            if state.get('attempt', 0) >= 1+len(self.retry_delays):
                self.safe_update(key, status='failed', nextRetryAt=None)
                return
            delay = max(0, (state.get('nextRetryAt') or 0)/1000-time.time())
            def resume():
                with self.lock:
                    if self.retry_timers.get(key) is not timer or self.closing: return
                    self.retry_timers.pop(key)
                    try: self.schedule(key, _resume=True)
                    except FileNotFoundError: pass
            timer = threading.Timer(delay, resume)
            timer.daemon = True
            self.retry_timers[key] = timer
            timer.start()

    def recover(self, force_all=False):
        for item in self.library.list():
            state = (item.get('mediaAnalysis') or {}).get('status')
            if force_all or state in (None, 'queued', 'running', 'interrupted'):
                self.schedule(item['id'], force=force_all, _resume=not force_all)
            elif state == 'retrying': self.arm_retry(item['id'])

    def wait(self, future, cancel):
        while True:
            if cancel.is_set():
                future.cancel()  # Do not leave a not-yet-started model task behind.
                raise AgentCancelled()
            try: return future.result(timeout=.2)
            except concurrent.futures.TimeoutError:
                # Future.result() uses the same TimeoutError class as the worker.
                # A completed task's timeout must escape, not block forever.
                if future.done(): return future.result()

    def run(self, key, cancel):
        try:
            if cancel.is_set(): raise AgentCancelled()
            with self.lock:
                if cancel.is_set(): raise AgentCancelled()
                state = self.library.get(key)[0].get('mediaAnalysis') or {}
                self.update(key, status='running', message='Preparing local analysis',
                            attempt=state.get('attempt', 0)+1, stage='prepare')
            item, source = self.agent.ready_source(key, cancel)
            # Explicit analysis (never library browsing) refreshes capture facts
            # for older imports that predate GPS support. No reverse-geocoding.
            if item['kind'] == 'video' and source.is_file() and (item.get('metadata') or {}).get('captureMetadataVersion') != 1:
                import app as engine
                metadata = engine.probe_media(source)
                if metadata.get('available'):
                    self.library.patch(key, metadata={**(item.get('metadata') or {}), **metadata})
                    item, source = self.library.get(key)
            def progress(message, stage=None):
                if cancel.is_set(): raise AgentCancelled()
                self.update(key, message=message, **({'stage':stage} if stage else {}))
            failures = []
            if item['kind'] in ('audio', 'video'):
                progress('Transcribing speech locally', 'speech')
                def transcribe():
                    # The speech service persists cues and provenance atomically;
                    # never overwrite a sidecar discovered while ASR was running.
                    self.descriptions.speech(item, source, cancel)
                try: self.wait(self.agent.pool.submit(transcribe), cancel)
                except AgentCancelled: raise
                except Exception as exc: failures.append(exc)
            if item['kind'] != 'audio':
                from video_description import reusable_shots
                latest, current_source = self.library.get(key)
                reviewed = reusable_shots(self.agent, latest, current_source) if item['kind'] == 'video' else []
                if not reviewed:
                    progress('Reading visual evidence locally', 'observe')
                    self.wait(self.agent.pool.submit(self.agent.observe, {'mode':'local'}, key, cancel,
                                                    progress=progress, window_seconds=6), cancel)
                if item['kind'] == 'video':
                    for controller in (self.shots, self.descriptions):
                        if cancel.is_set(): raise AgentCancelled()
                        progress('Writing the video description locally' if controller is self.descriptions else 'Analyzing editable shots locally', controller.field)
                        # Each stage owns its bounded format repair. Never replay a
                        # whole stage (cuts/frames/ASR) after that budget is exhausted.
                        latest, _ = self.library.get(key)
                        old = latest.get(controller.field) or {}
                        controller.start(key, force=old.get('status') in ('failed','interrupted','cancelled'))
                        with controller.lock: job = controller.jobs.get(key)
                        if job: self.wait(job[1], cancel)
                        latest, _ = self.library.get(key)
                        state = latest.get(controller.field) or {}
                        if cancel.is_set(): raise AgentCancelled()
                        if state.get('status') != 'ready':
                            failures.append(StageFailure(state, controller.field))
            if failures: raise AnalysisFailure(failures)
            if cancel.is_set(): raise AgentCancelled()
            self.update(key, status='ready', message='', nextRetryAt=None, retryable=None, stage='complete', completedAt=time.time()*1000)
        except AgentCancelled:
            self.safe_update(key, status='interrupted' if self.closing else 'cancelled', nextRetryAt=None, message='Analysis paused. Existing results are kept.')
        except Exception as exc:
            with self.lock:
                if cancel.is_set():
                    self.safe_update(key, status='interrupted' if self.closing else 'cancelled', nextRetryAt=None,
                                     message='Analysis paused. Existing results are kept.')
                    return
                try: state = self.library.get(key)[0].get('mediaAnalysis') or {}
                except FileNotFoundError: return
                attempt = state.get('attempt', 1)
                retryable = retryable_analysis_error(exc)
                retry = retryable and 1 <= attempt <= len(self.retry_delays)
                self.safe_update(key, status='retrying' if retry else 'failed', message=str(exc)[:500],
                                 retryable=retryable, nextRetryAt=(time.time()+self.retry_delays[attempt-1])*1000 if retry else None)

    def safe_update(self, key, **fields):
        try: self.update(key, **fields)
        except FileNotFoundError: pass

    def stop(self, key=None):
        with self.lock:
            # Also cover the gap between a finished future and its retry callback.
            for item in self.library.list():
                media_id = item['id']
                if (key is None or key == media_id) and (item.get('mediaAnalysis') or {}).get('status') == 'retrying':
                    timer = self.retry_timers.pop(media_id, None)
                    if timer: timer.cancel()
                    if not self.closing:
                        self.safe_update(media_id, status='cancelled', nextRetryAt=None,
                                         message='Analysis paused. Existing results are kept.')
            for media_id in list(self.retry_timers):
                if key is None or key == media_id: self.retry_timers.pop(media_id).cancel()
            for media_id, (cancel, future) in self.jobs.items():
                if (key is None or key == media_id) and not future.done():
                    cancel.set()
                    self.descriptions.stop(media_id)
                    self.shots.stop(media_id)

    def close(self):
        self.closing = True
        self.stop()
        self.pool.shutdown(wait=True)
