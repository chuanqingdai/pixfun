"""Local development bundle using installed tools; not a distributable package."""
import plistlib
import shlex
import shutil
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--python', required=True, help='Existing Python 3.9–3.12 with Pillow')
parser.add_argument('--model-python', required=True, help='Existing VisionFlow/MLX Python')
parser.add_argument('--vf-root', required=True)
parser.add_argument('--catalog-state', required=True)
args = parser.parse_args()
sys.path.insert(0,str(root))
from agent_models import cached_model
app = root / f'build-native/connected-{time.time_ns()}/Pixfun.app'
contents = app / 'Contents'
resources = contents / 'Resources'
executable = contents / 'MacOS/Pixfun'
executable.parent.mkdir(parents=True, exist_ok=True)
resources.mkdir(parents=True, exist_ok=True)
shutil.copy2(root / 'build-native/release/Pixfun', executable)
executable.chmod(0o755)
launcher = resources / 'backend/pixfun-service/pixfun-service'
launcher.parent.mkdir(parents=True, exist_ok=True)
# Preserve venv launcher paths: resolving the symlink selects the base interpreter.
python = str(Path(args.python).expanduser().absolute())
launcher.write_text('\n'.join([
    '#!/bin/bash', 'set -euo pipefail',
    'export OMP_NUM_THREADS=2 OPENBLAS_NUM_THREADS=2 MKL_NUM_THREADS=2 VECLIB_MAXIMUM_THREADS=2',
    'export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 PIXFUN_SERIAL_ANALYSIS=1 PIXFUN_AUTO_ANALYZE_EXISTING=0',
    'exec ' + shlex.quote(python) + ' -u ' + shlex.quote(str(root / 'desktop_service.py')),
    '',
]))
launcher.chmod(0o755)
# Captions and static titles are part of the native renderer, not HyperFrames.
subprocess.run(['swiftc', '-O', '-module-cache-path', str(root/'build-native/cache/swift'),
                str(root/'scripts/render-title.swift'), '-o', str(root/'build-native/pixfun-title')], check=True)
for relative, source in {
    'bin/ffmpeg': Path('/opt/homebrew/bin/ffmpeg'),
    'bin/ffprobe': Path('/opt/homebrew/bin/ffprobe'),
    'bin/pixfun-title': root/'build-native/pixfun-title',
    **{name: root / 'scripts' / name for name in ('agent-model-worker.py', 'vf_story.py', 'vf_media_catalog.py', 'vf_beauty.py', 'vf_hyperframes.py', 'vf_travel_graphics.py', 'agent_process_security.py', 'hyperframes-templates')},
    'public': root / 'public',
    'Fonts': root / 'public/fonts',
    'Brand/pixfun-lockup-v2.png': root / 'public/images/pixfun-lockup-v2.png',
    'CreatorSkills': root / 'creator-skills',
}.items():
    dest = resources / relative
    dest.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        if relative=='public': dest.mkdir(exist_ok=True)
        else: shutil.copytree(source,dest)
    else: shutil.copy2(source,dest)
for locale in (root/'native/Localization').glob('*.lproj'):
    shutil.copytree(locale, resources/locale.name)

config = {'VF_LIBRARY_STATE':str(Path(args.catalog_state).resolve()),
          'PIXFUN_MODEL_PYTHON':str(Path(args.model_python).expanduser().absolute()),
          'PIXFUN_VF_ROOT':str(Path(args.vf_root).resolve()),
          'PYTHONPATH':str(Path(args.vf_root).resolve()),
          'PIXFUN_LOCAL_VLM':cached_model('mlx-community/Qwen3-VL-4B-Instruct-4bit'),
          'PIXFUN_LOCAL_ASR':cached_model('mlx-community/Qwen3-ASR-1.7B-bf16'),
          'PIXFUN_ASR_ENGINE':'qwen3asr',
          'PIXFUN_LOCAL_RETRIEVAL':cached_model('google/siglip2-base-patch16-256')}
(resources/'vf-local.json').write_text(json.dumps(config,indent=2))
skills = subprocess.check_output(['node','-e',"const {skills,buildBrief}=require('./public/desktop-skills.js');process.stdout.write(JSON.stringify(skills.map(s=>({...s,strategy:buildBrief(s,'')}))))"],cwd=root)
(resources/'skills.json').write_bytes(skills)
(resources/'SkillCovers').mkdir()
for skill in json.loads(skills):
    src = root/'public/media/travel'/f"{skill['image']}.jpg"
    if src.exists(): shutil.copy2(src,resources/'SkillCovers'/src.name)
with (contents / 'Info.plist').open('wb') as f:
    plistlib.dump({
        'CFBundleExecutable': 'Pixfun', 'CFBundleIdentifier': 'com.pixfun.native',
        'CFBundleName': 'Pixfun', 'CFBundleDisplayName': 'Pixfun',
        'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '0.3.0',
        'CFBundleVersion': '300', 'LSMinimumSystemVersion': '13.0',
        'NSHighResolutionCapable': True, 'NSPrincipalClass': 'NSApplication',
        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
    }, f)
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
(root/'build-native/connected-app-path.txt').write_text(str(app))
print(app)
