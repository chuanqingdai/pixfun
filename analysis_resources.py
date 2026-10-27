"""Conservative admission control: one inference job, at most two CPU helpers.

Unknown/warning pressure serializes *both* lanes. In-flight work drains rather
than being killed; healthy pressure must persist before parallelism returns.
No GPU batch size is inferred from CPU count. No user media is read here.
"""
from concurrent.futures import ThreadPoolExecutor, Future, wait
from contextlib import contextmanager
import re
import subprocess
import sys
import threading
import time


def memory_snapshot():
    if sys.platform != 'darwin': return None
    try:
        values = subprocess.check_output(
            ['/usr/sbin/sysctl', '-n', 'hw.memsize', 'kern.memorystatus_vm_pressure_level'],
            text=True, timeout=2).split()
        stats = subprocess.check_output(['/usr/bin/vm_stat'], text=True, timeout=2)
        page_size = int(re.search(r'page size of (\d+) bytes', stats)[1])
        pages = dict((name, int(value)) for name, value in re.findall(r'^(Pages [\w ]+):\s+(\d+)', stats, re.M))
        available = sum(pages[key] for key in ('Pages free', 'Pages inactive', 'Pages speculative')) * page_size
        return {'total': int(values[0]), 'pressure': int(values[1]), 'available': available}
    except (OSError, subprocess.SubprocessError, ValueError, IndexError, KeyError, TypeError):
        return None  # fail conservatively, not by CPU count


class AnalysisResources:
    def __init__(self, probe=memory_snapshot, clock=time.monotonic):
        self.probe, self.clock = probe, clock
        self.condition = threading.Condition()
        self.local = threading.local()
        self.executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix='media-preprocess')
        self.active = {'model': 0, 'prepare': 0}
        self.parallel = False
        self.forced_serial = False
        self.healthy_since = None
        self.checked_at = float('-inf')
        self.snapshot = None

    def refresh(self):
        now = self.clock()
        if now - self.checked_at < 1: return
        self.checked_at = now
        self.snapshot = self.probe()
        sample = self.snapshot
        # A 16 GiB Apple-silicon Mac shares memory with MLX/Metal. Two Python
        # helpers importing OpenCV + Vision can be killed even while vm pressure
        # still reports normal, so only larger machines may use lookahead=2.
        healthy = bool(not self.forced_serial and sample and sample['pressure'] == 1 and
                       sample['total'] >= 24 * 1024**3 and
                       sample['available'] >= max(3 * 1024**3, sample['total'] * .20))
        if not healthy:
            self.parallel = False
            self.healthy_since = None
        else:
            if self.healthy_since is None: self.healthy_since = now
            if now - self.healthy_since >= 10: self.parallel = True

    @contextmanager
    def lease(self, kind, cancel):
        from agent_models import AgentCancelled
        if kind not in self.active: raise ValueError('Invalid analysis resource lane')
        if getattr(self.local, 'kind', None):
            if self.local.kind != kind: raise RuntimeError('Preprocessing must not invoke inference')
            if cancel.is_set(): raise AgentCancelled()
            yield
            return
        with self.condition:
            while True:
                if cancel.is_set(): raise AgentCancelled()
                self.refresh()
                allowed = (self.active[kind] < (2 if kind == 'prepare' else 1)
                           if self.parallel else not any(self.active.values()))
                if allowed: break
                self.condition.wait(.2)
            self.active[kind] += 1
            self.local.kind = kind
        try:
            yield
        finally:
            with self.condition:
                self.local.kind = None
                self.active[kind] -= 1
                self.condition.notify_all()

    def submit(self, cancel, function, *args, **kwargs):
        def work():
            with self.lease('prepare', cancel): return function(*args, **kwargs)
        return self.executor.submit(work)

    def status(self):
        with self.condition:
            self.refresh()
            return {'modelProcesses': 1, 'preprocessingLimit': 2 if self.parallel else 1,
                    'serial': not self.parallel, 'active': dict(self.active),
                    'reason': 'memory-headroom' if self.parallel else 'memory-pressure-or-warmup'}

    def force_serial(self):
        """Keep future preprocessing single-file after an OS resource kill."""
        with self.condition:
            self.forced_serial = True
            self.parallel = False
            self.healthy_since = None
            self.condition.notify_all()

    def shutdown(self):
        self.executor.shutdown(wait=True, cancel_futures=True)


@contextmanager
def prepared_windows(resources, windows, cancel, prepare):
    """Bounded lookahead, with no orphan helpers after failure/cancellation."""
    stopped = threading.Event()
    class Token:
        def is_set(self): return stopped.is_set() or cancel.is_set()
    token = Token()
    pending = {}
    def submit(index):
        if isinstance(resources, AnalysisResources):
            return resources.submit(token, prepare, index, *windows[index], token)
        future = Future()  # deterministic fallback for isolated/fake adapters
        try: future.set_result(prepare(index, *windows[index], token))
        except Exception as exc: future.set_exception(exc)
        return future
    def results():
        ahead = 0
        for index, (start, end) in enumerate(windows):
            while ahead < min(len(windows), index + 2):
                pending[ahead] = submit(ahead)
                ahead += 1
            value = pending[index].result()
            del pending[index]
            # Start the next window while the caller performs inference on this one.
            if ahead < len(windows):
                pending[ahead] = submit(ahead)
                ahead += 1
            yield index, start, end, value
    try:
        yield results()
    finally:
        stopped.set()
        for future in pending.values(): future.cancel()
        if pending: wait(pending.values())
