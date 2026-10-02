"""Private JSON-lines worker using the installed VisionFlow MLX engine. Offline only."""
import contextlib
import json
import os
from pathlib import Path
import sys
import gc
import ast
import subprocess
from types import SimpleNamespace

os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'
runtime = Path(os.environ.get('PIXFUN_VF_ROOT', str(Path.home() / 'work/visionflow/vf-agent')))
sys.path.insert(0, str(runtime / 'scripts'))
engine = None
for line in sys.stdin:
    try:
        job = json.loads(line)
        with contextlib.redirect_stdout(sys.stderr):
            if job['operation'] == 'motion':
                # Reuse VisionFlow's analysis functions without its CLI side effects.
                # Its CLI assumes VideoToolbox; our decoder uses the bundled portable FFmpeg.
                module = ast.parse((runtime / 'scripts/vf_motion.py').read_text())
                definitions = ast.Module(body=[n for n in module.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[])
                scope = {'a':SimpleNamespace(fps=8,width=320)}
                exec(compile(definitions, str(runtime / 'scripts/vf_motion.py'), 'exec'),scope)
                def decoded_frames(path):
                    import numpy as np
                    probe = json.loads(subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','json',path]))['streams'][0]
                    width=320; height=round(probe['height']*width/probe['width']/2)*2
                    decoder=subprocess.Popen(['ffmpeg','-v','error','-i',path,'-vf',f'fps=8,scale={width}:{height},format=gray','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
                    try:
                        while True:
                            frame=decoder.stdout.read(width*height)
                            if len(frame)!=width*height: break
                            yield np.frombuffer(frame,np.uint8).reshape(height,width)
                        if decoder.wait()!=0: raise RuntimeError('Motion frame decoding failed')
                    finally:
                        if decoder.poll() is None: decoder.kill(); decoder.wait()
                        decoder.stdout.close()
                scope['frames']=decoded_frames
                result=scope['analyze'](job['source'])
                value={'status':'complete' if result else 'insufficient-frames','source':'VisionFlow optical flow','sampleFPS':8,
                       'note':'Sampled camera-motion estimate, not proof of aesthetic quality.',
                       'segments':result['seq'] if result else [],
                       'stableRanges':result['smooth_segs'] if result else [],
                       'jitter':result['jitter_px'] if result else None,
                       'spikes':result['spikes'] if result else []}
            elif job['operation'] == 'inspect':
                import cv2
                from vf_agent import photo_metrics
                # Use the app's own YuNet/SFace pipeline for people. Never trigger InsightFace downloads here.
                photo_metrics._faces = lambda image: []
                quality = [photo_metrics.metrics(cv2.imread(p)) for p in job['images']]
                try:
                    from vf_agent.web_analysis import ocr_images
                    ocr = ocr_images(job['images'])
                    ocr_status = 'complete'
                except (ImportError, RuntimeError):
                    ocr = []; ocr_status = 'unavailable'
                value = {'quality': [{k: q[k] for k in ('sharp_all','mean_L','clip_hi','clip_lo','tilt')} for q in quality],
                         'ocr': ocr, 'ocrStatus': ocr_status, 'source': 'VisionFlow OpenCV metrics + Apple Vision OCR'}
            elif job['operation'] == 'rank':
                engine = None; gc.collect()
                import mlx.core as mx
                mx.clear_cache()
                import torch
                from PIL import Image
                from vf_agent import search
                search.MODEL = job['model']
                model, processor, device = search._load()
                scores = []
                with torch.no_grad():
                    limit = getattr(model.config.text_config, 'max_position_embeddings', 64)
                    text = search._txt_emb(model, processor(text=[job['query']],return_tensors='pt',padding='max_length',max_length=limit,truncation=True).to(device))
                    for i in range(0,len(job['images']),16):
                        images = [Image.open(p).convert('RGB') for p in job['images'][i:i+16]]
                        vectors = search._img_emb(model,processor(images=images,return_tensors='pt').to(device))
                        scores.extend((vectors @ text.T).flatten().cpu().tolist())
                value = {'scores': scores, 'model': 'SigLIP2', 'note': 'Relative similarity, not probability; verify against visual evidence.'}
                search._m = None; del model, processor; gc.collect()
                if device == 'mps': torch.mps.empty_cache()
            elif job['operation'] == 'transcribe':
                engine = None; gc.collect()
                import mlx_whisper
                result = mlx_whisper.transcribe(job['source'], path_or_hf_repo=job['model'], verbose=False,
                    word_timestamps=False, condition_on_previous_text=False)
                value = {'cues': [{'start': s['start'], 'end': s['end'], 'text': s['text'].strip()}
                                  for s in result.get('segments', []) if s.get('text', '').strip()]}
            elif job['operation'] == 'ask':
                if engine is None:
                    from vf_engine import Engine
                    engine = Engine('mlx', job['model'], max_tokens=1800)
                engine.max_tokens = job.get('maxTokens', 1800)
                value, usage = engine.ask(job['prompt'], job.get('images', []))
            else:
                raise ValueError('Unsupported local operation')
        print(json.dumps({'ok': True, 'value': value}, ensure_ascii=False), flush=True)
    except Exception as error:
        print(json.dumps({'ok': False, 'error': type(error).__name__ + ': ' + str(error)[:300]}), flush=True)
