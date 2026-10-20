#!/usr/bin/env python3
import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import agent_trip


def record(media_id, name, captured, lat, lon, place):
    return {
        'id': media_id, 'file': {'name': name},
        'metadata': {'capturedAt': captured, 'location': {
            'latitude': lat, 'longitude': lon, 'source': 'file-metadata', 'datum': 'WGS84'}},
        'context': {'location': place},
    }


class FakeLibrary:
    def __init__(self, records):
        self.records = records
        self.patches = []

    def get(self, media_id):
        return self.records[media_id], Path('/tmp') / self.records[media_id]['file']['name']

    def patch(self, media_id, **values):
        self.patches.append((media_id, values))
        self.records[media_id].update(values)


class TripTests(unittest.TestCase):
    def setUp(self):
        self.records = {
            'three': record('three', 'IMG_0072.MOV', '2026-10-11T14:11:00+08:00', 40.0031, 116.3176, '北京 清华大学'),
            'four': record('four', 'IMG_0073.MOV', '2026-10-11T14:23:00+08:00', 40.0044, 116.3137, '北京 圆明园遗址公园'),
        }

    def test_picker_copies_anchor_without_changing_original(self):
        trip = agent_trip.proposal(self.records)
        corrected = agent_trip.manual_correction(trip, [2], 1)
        self.assertEqual(corrected['entries'][1]['location'], corrected['entries'][0]['location'])
        self.assertEqual(corrected['entries'][1]['originalLocation']['longitude'], 116.3137)
        self.assertEqual(corrected['entries'][1]['place'], '北京 清华大学')

    def test_confirmed_overlay_retains_original_coordinates(self):
        trip = agent_trip.manual_correction(agent_trip.proposal(self.records), [2], 1)
        trip['status'] = 'confirmed'
        library = FakeLibrary(self.records)
        self.assertEqual(agent_trip.apply(library, trip), 1)
        review = library.patches[0][1]['locationReview']
        self.assertEqual(review['latitude'], 40.0031)
        self.assertEqual(review['originalLatitude'], 40.0044)
        self.assertEqual(self.records['four']['metadata']['location']['latitude'], 40.0044)

    def test_invalid_anchor_is_rejected(self):
        with self.assertRaisesRegex(ValueError, '行程已变化'):
            agent_trip.manual_correction(agent_trip.proposal(self.records), [2], 99)


if __name__ == '__main__':
    unittest.main()
