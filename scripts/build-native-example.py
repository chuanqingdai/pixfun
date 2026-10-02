"""Build the offline Mac example from a credited, continuous NPS excerpt.

No model inference is claimed: visual cuts and source subtitles are prepared here;
users can run normal local understanding on the example from Media.
"""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'native/Examples/wild-alaska'
FFMPEG = 'ffmpeg'  # Build-time encoder; the app's LGPL runtime only needs playback/analysis.
FFPROBE = str(ROOT / 'build-desktop/media/bin/ffprobe')
SOURCE = ROOT / 'data/travel-import-20260927/Lake Clark Alaska Journey.mp4'
START, END = 25, 234
BASE = '/assets/examples/wild-alaska/'


def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True)


def seconds(value):
    h, m, s = value.split(':')
    return int(h) * 3600 + int(m) * 60 + float(s)


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    video = OUT / 'wild-alaska.mp4'
    if not video.exists():
        run([FFMPEG, '-v', 'error', '-ss', str(START), '-i', str(SOURCE), '-t', str(END-START),
             '-map', '0:v:0', '-map', '0:a:0', '-c:v', 'libx264', '-preset', 'fast', '-crf', '19',
             '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', str(video)])
    probe = json.loads(run([FFPROBE, '-v', 'error', '-show_streams', '-show_format', '-of', 'json', str(video)]).stdout)
    duration = float(probe['format']['duration'])
    stream = next(s for s in probe['streams'] if s['codec_type'] == 'video')
    scan = run([FFMPEG, '-hide_banner', '-i', str(video), '-vf',
                r'scale=480:-1,select=gt(scene\,0.22),showinfo', '-an', '-f', 'null', '-'])
    cuts = []
    for value in re.findall(r'pts_time:([0-9.]+)', scan.stderr):
        t = float(value)
        if 0.7 < t < duration - 0.7 and (not cuts or t-cuts[-1] > 0.7):
            cuts.append(round(t, 3))
    segments = []
    boundaries = [0] + cuts + [duration]
    for index, (start, end) in enumerate(zip(boundaries, boundaries[1:])):
        filename = f'shot-{index+1:02}.jpg'
        run([FFMPEG, '-v', 'error', '-y', '-ss', str((start+end)/2), '-i', str(video),
             '-frames:v', '1', '-vf', 'scale=640:-1', str(OUT/filename)])
        segments.append({'id': f'example-shot-{index+1:03}', 'label': f'Shot {index+1}',
                         'start': start, 'end': end, 'thumbnailUrl': BASE+filename,
                         'boundary': {'type': 'video_start' if index == 0 else 'detected_cut'},
                         'note': 'Detected visual cut · prepared example; semantic analysis available on request'})
    # A bright, representative snow peak; independent from the first-shot thumbnail.
    run([FFMPEG, '-v', 'error', '-y', '-ss', str(145-START), '-i', str(video),
         '-frames:v', '1', '-vf', 'scale=1280:-1', str(OUT/'cover.jpg')])
    text = (ROOT/'data/landing-cases-v2/alaska-reference.vtt').read_text()
    cues = []
    for block in re.split(r'\n\s*\n', text):
        match = re.search(r'(\d{2}:\d{2}:\d{2}\.\d+) --> (\d{2}:\d{2}:\d{2}\.\d+)\s*\n([\s\S]+)', block)
        if not match:
            continue
        a, b = seconds(match[1]), seconds(match[2])
        content = re.sub(r'\[[^\]]*\]', '', match[3]).strip()
        if b > START and a < END and content:
            cues.append({'start': max(0, a-START), 'end': min(duration, b-START),
                         'text': ' '.join(content.split())})
    record = {
        'id': 'example-wild-alaska-v1', 'isExample': True, 'kind': 'video', 'status': 'ready',
        'file': {'name': 'Wild Alaska.mp4', 'type': 'video/mp4', 'size': video.stat().st_size},
        'title': 'Wild Alaska', 'coverUrl': BASE+'cover.jpg',
        'metadata': {'width': stream['width'], 'height': stream['height'], 'duration': duration,
                     'fps': eval_fraction(stream['avg_frame_rate']), 'hasAudio': True},
        'context': {'location': 'Lake Clark, Alaska', 'credit': 'NPS · T. Vaughn & J. Pfeiffenberger',
                    'source': 'https://www.nps.gov/media/video/view.htm?id=a7ea1719-005e-42cd-b7c9-79cda436ecad',
                    'license': 'Public domain · NPS credit', 'example': 'Continuous excerpt, source 00:25–03:54. Original narration/music; not raw camera footage.'},
        'videoDescription': {'status': 'ready', 'title': 'Wild Alaska', 'model': 'Prepared editorial example',
            'coverage': 'Prepared, visually reviewed sample description; not a new AI analysis.',
            'full_description': 'Lakes and forest introduce Lake Clark before fishing, net handling and riverside scenes bring the landscape into everyday life. Beneath the surface, salmon move through the water; nearby, a brown bear feeds along the shore. Aerial views follow winding rivers, blue bays and snow-covered peaks, opening the story to a wider scale. Coastal bears and cubs lead into shoreline research and a final beach scene. The original narration links people, wildlife and conservation. For an edit, use the fishing sequences to establish human activity, the bear close-ups as wildlife highlights, and the sunlit summit as a visual high point. Shorten repeated landscape holds while preserving complete actions and the continuity of the existing narration and music.'},
        'result': {'ok': True, 'analysis': {'segments': segments, 'cuts': cuts,
            'segmentationMethod': 'detected-cuts', 'subtitleCues': cues, 'subtitleState': 'source-reference',
            'subtitleMessage': 'Official NPS captions, offset to the continuous excerpt; not a new transcription.'}}
    }
    (OUT/'manifest.json').write_text(json.dumps({'filename': video.name, 'record': record}, ensure_ascii=False, indent=2))
    (OUT/'SOURCE.txt').write_text('Wild Alaska — bundled demonstration footage\n'+record['context']['source']+'\n'
        +record['context']['credit']+'\n'+record['context']['license']+'\n'+record['context']['example']+'\n'
        +'Visual cuts are precomputed; description is editorially reviewed. Captions are from the official source.\n')
    print(json.dumps({'duration': duration, 'shots': len(segments), 'captions': len(cues), 'bytes': video.stat().st_size}))


def eval_fraction(value):
    a, b = value.split('/')
    return float(a) / max(float(b), 1)


if __name__ == '__main__':
    build()
