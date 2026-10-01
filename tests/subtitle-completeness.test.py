from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import app
from desktop_service import Library


class SubtitleCompletenessTests(unittest.TestCase):
    def test_all_cues_and_full_text(self):
        blocks = []
        for index in range(275):
            start = index * 3
            blocks.append(f'{index}\n00:{start//60:02d}:{start%60:02d},000 --> 00:{(start+2)//60:02d}:{(start+2)%60:02d},900\nCaption {index}')
        cues = app.parse_subtitle_text('\n\n'.join(blocks))
        self.assertEqual(len(cues), 275)
        self.assertEqual(cues[-1]['text'], 'Caption 274')
        self.assertEqual(cues[-1]['start'], 822)
        long_text = 'complete text ' * 100
        cue = app.parse_subtitle_text('00:00.000 --> 00:04.000\n' + long_text)[0]
        self.assertEqual(cue['text'], long_text.strip())

    def test_webvtt_markup_settings_and_invalid_blocks(self):
        cues = app.parse_subtitle_text('\ufeffWEBVTT\r\n\r\nNOTE ignored\n00:00.000 --> 00:01.000\nNot a cue\n\nintro\n00:00.000 --> 00:02.000 align:start\n<v Ranger>Hello &amp; welcome</v>\nHere today\n\ninvalid --> 00:04.000\nInvalid')
        self.assertEqual(len(cues), 1)
        self.assertEqual(cues[0]['text'], 'Hello & welcome Here today')

    def test_existing_library_picks_up_sidecar_without_reimport(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'recording.mp4'
            source.touch()
            library = Library(Path(directory) / 'library')
            import json
            record = {'id':'sample','kind':'video','status':'ready','result':{'analysis':{'subtitleCues':[],'segments':[{'start':0}]}}}
            with library.connect() as db:
                db.execute('INSERT INTO media(id,source,record) VALUES(?,?,?)', ('sample', str(source), json.dumps(record)))
            source.with_suffix('.vtt').write_text('WEBVTT\n\n00:00.000 --> 00:02.000\nHello\n\n11:20.000 --> 11:29.000\nFinal caption', encoding='utf8')
            analysis = library.list()[0]['result']['analysis']
            self.assertEqual(len(analysis['subtitleCues']), 2)
            self.assertEqual(analysis['subtitleCues'][-1]['start'], 680)
            self.assertEqual(analysis['subtitleState'], 'sidecar')
            self.assertEqual(analysis['segments'], [{'start':0}])
            self.assertEqual(library.list()[0]['result']['analysis'], analysis)
            self.assertEqual(library.get('sample')[0]['result']['analysis'], analysis)
            library.pool.shutdown()

    def test_nps_caption_timestamp_variant(self):
        cues = app.parse_subtitle_text('WEBVTT\n\n0:11:27.743,0:11:30.579\nHappy Glacier Science Day! Bye!')
        self.assertEqual(len(cues), 1)
        self.assertEqual(cues[0]['end'], 690.579)


if __name__ == '__main__':
    unittest.main()
