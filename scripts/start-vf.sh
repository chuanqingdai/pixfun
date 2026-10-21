#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${VF_LIBRARY_STATE:?Set VF_LIBRARY_STATE to the unified catalog server.json}"
PIXFUN_PYTHON="${PIXFUN_PYTHON:-python3}"
"$PIXFUN_PYTHON" - <<'PY'
import sys, shutil
if not (3, 9) <= sys.version_info[:2] <= (3, 12):
    raise SystemExit('Pixfun currently needs Python 3.9–3.12. Set PIXFUN_PYTHON to that interpreter.')
try:
    import PIL
except ImportError:
    raise SystemExit('Install Pillow into the selected Python environment for export.')
for name in ('ffmpeg', 'ffprobe'):
    if not shutil.which(name): raise SystemExit(name + ' must be available on PATH.')
PY
export PIXFUN_DATA_DIR="${PIXFUN_DATA_DIR:-$PWD/data/vf-integration}"
export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2
exec "$PIXFUN_PYTHON" -u vf_server.py
