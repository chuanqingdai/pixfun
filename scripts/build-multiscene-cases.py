"""Reproducible, local-only public demo media. Never accesses the user's library."""
import json, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'data/landing-cases-v2'
OUT = ROOT / 'public/media/cases/v3'
DATA.mkdir(exist_ok=True); OUT.mkdir(exist_ok=True)

def run(args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout

def probe(file):
    return json.loads(run(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(file)]))

def source(file, start, duration, page, credit='Mixkit contributors', license='Mixkit Stock Video Free License'):
    return dict(file=file,start=start,duration=duration,page=page,credit=credit,license=license)

CASES = [
 dict(id='alpine',label='Wild Alaska',highlight=40.4,audio=True,sources=[source('data/travel-import-20260927/Lake Clark Alaska Journey.mp4',102.8,50.2,'https://www.nps.gov/media/video/view.htm?id=a7ea1719-005e-42cd-b7c9-79cda436ecad','NPS / T. Vaughn and J. Pfeiffenberger','Public domain · NPS')]),
 dict(id='citywalk',label='Tokyo after dark',highlight=9,audio=False,sources=[
  source('data/landing-quality-20261001/4308.mp4',2,8,'https://mixkit.co/free-stock-video/aerial-view-of-a-city-during-the-night-4308/'),
  source('data/landing-quality-20261001/4451.mp4',4,8,'https://mixkit.co/free-stock-video/quiet-tokyo-street-at-night-4451/'),
  source('data/landing-quality-20261001/4447.mp4',8,8,'https://mixkit.co/free-stock-video/neon-signs-with-japanese-letters-4447/')]),
 dict(id='food',label='Slow mornings',highlight=10.5,audio=False,sources=[
  source('data/landing-quality-20261001/1669.mp4',1,8,'https://mixkit.co/free-stock-video/a-chef-covering-dough-with-flour-1669/'),
  source('data/landing-quality-20261001/41859.mp4',0,8,'https://mixkit.co/free-stock-video/serving-a-sparkling-cappuccino-in-a-cup-41859/'),
  source('data/landing-quality-20261001/4866.mp4',2,8,'https://mixkit.co/free-stock-video/breakfast-at-a-table-with-bread-coffee-and-fruit-4866/')]),
 dict(id='outdoors',label='Geysers at golden hour',highlight=27.5,audio=True,sources=[source('data/landing-cases-v2/geysers-source.mp4',237.8,43.45,'https://www.nps.gov/media/video/view.htm?id=DBA52FFD-155D-451F-67C4471D28BA5344','NPS / Steven M. Bumgardner','Public domain · NPS')]),
 dict(id='islands',label='Island escape',highlight=10,audio=False,sources=[
  source('data/landing-quality-20261001/2883.mp4',2,8,'https://mixkit.co/free-stock-video/paradise-port-on-an-island-2883/'),
  source('data/landing-quality-20261001/1579.mp4',2,8,'https://mixkit.co/free-stock-video/a-man-paddling-on-a-board-to-get-to-a-1579/'),
  source('data/landing-cases-20261001/islands.mp4',2,8,'https://mixkit.co/free-stock-video/white-sand-beach-background-1564/')])
]

def main():
    manifests=[]
    for case in CASES:
        target=OUT/(case['id']+'.mp4')
        force=('--force-'+case['id']) in sys.argv
        # Match the weakest source's real resolution, never upscale to claim HD.
        heights=[next(s for s in probe(ROOT/x['file'])['streams'] if s['codec_type']=='video')['height'] for x in case['sources']]
        height=1080 if min(heights)>=1080 else 720; width=height*16//9
        if not target.exists() or force:
            parts=[]
            for i,s in enumerate(case['sources']):
                part=DATA/f"{case['id']}-v3-part-{i}.mp4"; parts.append(part)
                if not part.exists() or force:
                    args=['ffmpeg','-v','error','-y','-ss',str(s['start']),'-i',str(ROOT/s['file']),'-t',str(s['duration']),'-map','0:v:0','-vf',f'scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,fps=25','-c:v','libx264','-threads','2','-preset','fast','-crf','18','-pix_fmt','yuv420p']
                    args+=['-map','0:a:0','-c:a','aac','-b:a','160k'] if case['audio'] else ['-an']
                    run(args+['-movflags','+faststart',str(part)])
            concat=DATA/(case['id']+'-concat.txt')
            concat.write_text('\n'.join("file '"+str(p)+"'" for p in parts))
            run(['ffmpeg','-v','error','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy','-movflags','+faststart',str(target)])
        info=probe(target); video=next(s for s in info['streams'] if s['codec_type']=='video')
        case['duration']=float(info['format']['duration']);case['width']=video['width'];case['height']=video['height']
        case['videoDuration']=float(video['duration'])
        preview=OUT/(case['id']+'-preview.mp4')
        if not preview.exists() or force or '--refresh-previews' in sys.argv:
            run(['ffmpeg','-v','error','-y','-ss',str(case['highlight']),'-i',str(target),'-t','5','-vf','scale=1280:720','-an','-c:v','libx264','-threads','2','-preset','fast','-crf','21','-movflags','+faststart',str(preview)])
        run(['ffmpeg','-v','error','-y','-ss',str(case['highlight']+1),'-i',str(target),'-frames:v','1','-q:v','2',str(OUT/(case['id']+'.jpg'))])
        run(['ffmpeg','-v','error','-y','-i',str(target),'-vf','fps=1/2,scale=320:-2,tile=5x6','-frames:v','1',str(DATA/(case['id']+'-contact.jpg'))])
        cuts=subprocess.run(['ffmpeg','-hide_banner','-i',str(target),'-vf',"select='gt(scene,0.25)',showinfo",'-an','-f','null','-'],capture_output=True,text=True)
        (DATA/(case['id']+'-cuts.log')).write_text(cuts.stderr)
        manifests.append(case);print(case['id'],case['duration'],flush=True)
    (DATA/'manifest.json').write_text(json.dumps(manifests,indent=2))

if __name__=='__main__': main()
