"""Offline capture metadata / track extraction; no personal files or inference."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import app
from media_metadata import location_from_tags


class CaptureTests(unittest.TestCase):
    def test_coordinates_and_recorded_name_not_a_guessed_place(self):
        result = location_from_tags({'com.apple.quicktime.location.ISO6709':'+39.9000+116.4000+40.0/', 'com.apple.quicktime.location.name':'Recorded place'})
        self.assertEqual(result, {'name':'Recorded place','latitude':39.9,'longitude':116.4,'altitude':40.,'source':'file-metadata'})
        self.assertEqual(location_from_tags({'location':'-33.8500+151.2000/'} )['latitude'], -33.85)
        self.assertAlmostEqual(location_from_tags({'location':'+3954.00+11624.00/'})['longitude'],116.4)
        self.assertAlmostEqual(location_from_tags({'location':'+395400+1162400/'})['latitude'],39.9)
        for invalid in ('Beijing', '+91.0+116.0/', '+39.0+181.0/', '+3960+1162400/', 'nan,inf', ''):
            self.assertIsNone(location_from_tags({'location':invalid}))
        self.assertEqual(location_from_tags({'location_name':'Named by camera'}), {'name':'Named by camera','source':'file-metadata'})
        self.assertIsNone(location_from_tags({'title':'Shot in Shanghai'}))

    def test_chinese_sidecar_and_original_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'clip.mov'; source.touch()
            source.with_suffix('.zh-CN.srt').write_text('1\n00:00:00,000 --> 00:00:01,000\n你好，世界\n', encoding='utf8')
            result=app.local_subtitle_track(source)
            self.assertEqual(result['subtitleState'],'sidecar')
            self.assertEqual(result['subtitleSource'],'clip.zh-CN.srt')
            self.assertEqual(result['subtitleCues'][0]['text'],'你好，世界')

    def test_bitmap_track_does_not_hide_later_text_track(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(app,'OUTPUTS',Path(tmp)), patch.object(app,'command_exists',return_value=True):
            calls=[]
            def run(args, **kwargs):
                calls.append(args)
                Path(args[-1]).write_text('1\n00:00:00,000 --> 00:00:01,000\n真实字幕\n',encoding='utf8')
                return 0,'',''
            with patch.object(app,'run_command',side_effect=run):
                track=app.extract_subtitle_track(Path('fixture.mkv'),'job',{'subtitleTracks':[{'index':2,'codec':'hdmv_pgs_subtitle'},{'index':3,'codec':'subrip','language':'zho'}]})
            self.assertEqual(len(calls),1)
            self.assertIn('0:3',calls[0])
            self.assertEqual(track['subtitleLanguage'],'zho')
            self.assertEqual(track['subtitleCues'][0]['text'],'真实字幕')

    def test_real_quicktime_metadata_and_editable_subtitle(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(app,'OUTPUTS',Path(tmp)/'out'):
            folder=Path(tmp); captions=folder/'caption.srt'
            captions.write_text('1\n00:00:00,000 --> 00:00:01,000\n字幕原文，不翻译。\n',encoding='utf8')
            video=folder/'fixture.mov'
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=blue:s=160x90:d=2','-i',str(captions),'-map','0:v','-map','1:s','-c:v','libx264','-c:s','mov_text','-metadata','com.apple.quicktime.location.ISO6709=+39.9000+116.4000/','-metadata','com.apple.quicktime.model=Fixture Camera','-movflags','use_metadata_tags',str(video)],check=True,timeout=30)
            metadata=app.probe_media(video)
            self.assertEqual(metadata['camera'],'Fixture Camera')
            self.assertEqual(metadata['location']['latitude'],39.9)
            result=app.extract_subtitle_track(video,'real',metadata)
            self.assertEqual(result['subtitleState'],'embedded')
            self.assertEqual(result['subtitleCues'][0]['text'],'字幕原文，不翻译。')


if __name__ == '__main__': unittest.main()
