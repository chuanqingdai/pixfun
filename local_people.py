"""Offline YuNet + SFace grouping. No network, identity lookup, or original writes."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import threading
import uuid

MODEL_VERSION = 'yunet-2023mar-sface-2021dec-v1'


def subject_eligible(hits, photo=False):
    """Conservative prominence/persistence heuristic, not knowledge of relationships."""
    if not hits:
        return False
    area = max(hit['area'] for hit in hits)
    if photo:
        return area >= .018 and any(hit['central'] for hit in hits)
    span = max(hit['time'] for hit in hits) - min(hit['time'] for hit in hits)
    return (len(hits) >= 3 and span >= 6 and area >= .008) or (
        len(hits) >= 2 and span >= 3 and area >= .035 and any(hit['central'] for hit in hits))


def choose_group(scores, occupied):
    ranked = sorted(((score, key) for key, score in scores.items() if key not in occupied), reverse=True)
    if not ranked or ranked[0][0] < .55:
        return None
    if len(ranked) > 1 and ranked[0][0] - ranked[1][0] < .08:
        return None
    return ranked[0][1]


class PeopleEngine:
    def __init__(self, library, models):
        self.library, self.models = library, Path(models)
        self.directory = library.directory / 'people'
        self.directory.mkdir(exist_ok=True, mode=0o700)
        self.cache_path = self.directory / 'analysis.json'
        self.lock = threading.RLock()
        self.cancel = threading.Event()
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=1)
        self.state = 'idle'; self.completed = 0; self.total = 0; self.current = ''; self.errors = []
        self.cache = {'version': MODEL_VERSION, 'groups': {}, 'assets': {}}
        self.load_error = None
        if self.cache_path.exists():
            try:
                value = json.loads(self.cache_path.read_text())
                if value.get('version') != MODEL_VERSION or not isinstance(value.get('groups'), dict) or not isinstance(value.get('assets'), dict):
                    raise ValueError('Unsupported people cache version')
                self.cache = value
            except Exception:
                self.load_error = 'People cache could not be read. It was left unchanged.'

    def snapshot(self):
        with self.lock:
            people = []
            active = {item['id'] for item in self.library.list() if item['kind'] != 'audio'}
            for group_id, group in self.cache['groups'].items():
                assets = [key for key, asset in self.cache['assets'].items()
                          if key in active and group_id in asset.get('people', [])]
                if assets and Path(group['avatarPath']).is_file():
                    people.append({'id': group_id, 'avatarPath': group['avatarPath'], 'mediaIDs': assets})
            return {'state': self.state, 'completed': self.completed, 'total': self.total,
                    'current': self.current, 'people': people, 'scannedIDs': list(self.cache['assets']),
                    'errors': ([self.load_error] if self.load_error else []) + self.errors,
                    'method': 'YuNet + SFace; sampled frames; prominence and persistence filtering'}

    def start(self, ids=None):
        with self.lock:
            if self.state == 'running':
                return
            if self.load_error:
                raise ValueError(self.load_error)
            records = [item for item in self.library.list() if item['kind'] != 'audio' and not item.get('missing')]
            if ids is not None:
                if not isinstance(ids, list) or not all(isinstance(i, str) for i in ids):
                    raise ValueError('Invalid media IDs')
                records = [item for item in records if item['id'] in ids]
            self.state = 'running'; self.completed = 0; self.total = len(records); self.errors = []
            self.cancel.clear()
            self.pool.submit(self.run, records)

    def stop(self):
        self.cancel.set()

    def save(self):
        temp = self.cache_path.with_suffix('.tmp')
        temp.write_text(json.dumps(self.cache, separators=(',', ':')))
        os.chmod(temp, 0o600)
        temp.replace(self.cache_path)

    def run(self, records):
        try:
            import cv2 as cv
            import numpy as np
            cv.setNumThreads(2)
            detector = cv.FaceDetectorYN.create(str(self.models / 'yunet.onnx'), '', (320, 320), .9, .3, 200)
            recognizer = cv.FaceRecognizerSF.create(str(self.models / 'sface.onnx'), '')
            for item in records:
                if self.cancel.is_set():
                    break
                with self.lock: self.current = item['file']['name']
                try:
                    _, path = self.library.get(item['id'])
                    stat = path.stat()
                    signature = hashlib.sha256(f'{path}:{stat.st_size}:{stat.st_mtime_ns}:{MODEL_VERSION}'.encode()).hexdigest()
                    if self.cache['assets'].get(item['id'], {}).get('signature') != signature:
                        result = self.scan(item, path, detector, recognizer, cv, np)
                        if self.cancel.is_set():
                            break
                        with self.lock:
                            self.cache['assets'][item['id']] = {**result, 'signature': signature}
                            self.save()
                except Exception as exc:
                    with self.lock: self.errors.append(f"{item['file']['name']}: {str(exc)[:180]}")
                with self.lock: self.completed += 1
            with self.lock: self.state = 'cancelled' if self.cancel.is_set() else ('needsReview' if self.errors else 'complete')
        except Exception as exc:
            with self.lock:
                self.state = 'error'; self.errors.append(f'Local people model could not run: {str(exc)[:240]}')
        finally:
            with self.lock: self.current = ''

    def scan(self, item, path, detector, recognizer, cv, np):
        photo = item['kind'] == 'image'
        capture = None
        if photo:
            frame = cv.imread(str(path))
            if frame is None:
                # HEIC and other formats supported by the bundled FFmpeg decoder.
                import subprocess
                data = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(path), '-frames:v', '1', '-f', 'image2pipe', '-vcodec', 'mjpeg', '-'], capture_output=True, timeout=30, check=True).stdout
                frame = cv.imdecode(np.frombuffer(data, np.uint8), cv.IMREAD_COLOR)
            if frame is None:
                raise ValueError('Image could not be decoded')
            times = [0.0]
        else:
            capture = cv.VideoCapture(str(path))
            if not capture.isOpened():
                capture.release(); raise ValueError('Video could not be decoded for people analysis')
            capture.set(cv.CAP_PROP_ORIENTATION_AUTO, 1)
            duration = (item.get('metadata') or {}).get('duration') or capture.get(cv.CAP_PROP_FRAME_COUNT) / max(1, capture.get(cv.CAP_PROP_FPS))
            if not np.isfinite(duration) or duration <= 0:
                capture.release(); raise ValueError('Video duration is unavailable')
            interval = max(3.0, duration / 600)
            times = list(np.arange(0, duration, interval))
        hits = {}; decoded = 0
        try:
            for second in times:
                if self.cancel.is_set(): break
                if capture is not None:
                    capture.set(cv.CAP_PROP_POS_MSEC, float(second) * 1000)
                    ok, frame = capture.read()
                    if not ok: continue
                decoded += 1
                height, width = frame.shape[:2]
                scale = min(1, 960 / max(width, height))
                if scale < 1: frame = cv.resize(frame, (round(width * scale), round(height * scale)))
                height, width = frame.shape[:2]
                detector.setInputSize((width, height))
                _, faces = detector.detect(frame)
                occupied = set()
                if faces is None: continue
                for face in sorted(faces, key=lambda f: float(f[2] * f[3]), reverse=True)[:12]:
                    x, y, w, h = [float(v) for v in face[:4]]
                    if min(w, h) < 32: continue
                    aligned = recognizer.alignCrop(frame, face)
                    if cv.Laplacian(cv.cvtColor(aligned, cv.COLOR_BGR2GRAY), cv.CV_64F).var() < 25: continue
                    vector = recognizer.feature(aligned).flatten()
                    norm = np.linalg.norm(vector)
                    if not np.isfinite(norm) or norm <= 0: continue
                    vector /= norm
                    with self.lock:
                        scores = {key: float(np.dot(vector, group['anchor'])) for key, group in self.cache['groups'].items()}
                        group_id = choose_group(scores, occupied)
                        if group_id is None:
                            group_id = str(uuid.uuid4())
                            avatar = self.directory / f'{group_id}.jpg'
                            # Same-frame portrait crop; never substitute a generated face.
                            left, top = max(0, int(x - w * .25)), max(0, int(y - h * .25))
                            right, bottom = min(width, int(x + w * 1.25)), min(height, int(y + h * 1.25))
                            crop = cv.resize(frame[top:bottom, left:right], (128, 128))
                            if not cv.imwrite(str(avatar), crop): raise ValueError('Could not write face thumbnail')
                            os.chmod(avatar, 0o600)
                            self.cache['groups'][group_id] = {'anchor': vector.tolist(), 'avatarPath': str(avatar)}
                    occupied.add(group_id)
                    hits.setdefault(group_id, []).append({'time': float(second), 'area': w * h / (width * height), 'central': .15 < (x + w / 2) / width < .85})
            if decoded == 0: raise ValueError('No video frames could be decoded')
            return {'people': [key for key, found in hits.items() if subject_eligible(found, photo)],
                    'sampledFrames': decoded, 'plannedFrames': len(times), 'samplingSeconds': 0 if photo else interval,
                    'suppressedGroups': sum(not subject_eligible(found, photo) for found in hits.values())}
        finally:
            if capture is not None: capture.release()
