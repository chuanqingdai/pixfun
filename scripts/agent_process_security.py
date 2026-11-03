"""Least-privilege environment for local Media model workers."""
import os


def worker_environment(source=None):
    source = os.environ if source is None else source
    allowed = ('PATH', 'HOME', 'TMPDIR', 'LANG', 'LC_ALL', 'TZ',
               'PIXFUN_VF_ROOT', 'PIXFUN_BEAUTY_MANIFEST',
               'HF_HOME', 'HUGGINGFACE_HUB_CACHE', 'MLX_METAL_PATH')
    env = {key: source[key] for key in allowed if key in source}
    env.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
               HF_HUB_DISABLE_TELEMETRY='1', PYTHONDONTWRITEBYTECODE='1')
    return env
