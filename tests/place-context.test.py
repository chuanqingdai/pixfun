import copy
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from place_context import validate_place, description_context


class PlaceContextTests(unittest.TestCase):
    def setUp(self):
        self.item = {'metadata':{'location':{'latitude':40.0036,'longitude':116.3181}}, 'resolvedPlace':{
            'version':2,'provider':'apple-geocoder','language':'zh-Hans','latitude':40.0036,'longitude':116.3181,
            'label':'北京市 · 海淀区 · 清华大学 · 双清路30号', 'area':'清华大学',
            'nearbyName':'清华大学药学院','resolvedAt':1792100000}}
    def test_verified_area_not_nearest_building_enters_description(self):
        before = copy.deepcopy(self.item)
        self.assertEqual(description_context(self.item), {'location':'清华大学'})
        self.assertEqual(self.item, before)
        self.assertEqual(validate_place(self.item,self.item['resolvedPlace'])['nearbyName'],'清华大学药学院')
    def test_explicit_user_and_original_names_take_priority(self):
        self.item['metadata']['location']['name'] = '原片地名'
        self.assertEqual(description_context(self.item)['location'],'原片地名')
        self.item['context']={'location':'用户确认的地点'}
        self.assertEqual(description_context(self.item)['location'],'用户确认的地点')
    def test_mismatch_or_missing_coordinates_never_ground_a_description(self):
        self.item['metadata']['location']['latitude'] = 30
        self.assertEqual(description_context(self.item), {})
        with self.assertRaises(ValueError): validate_place(self.item,self.item['resolvedPlace'])
    def test_invalid_values_are_rejected(self):
        for field,value in [('latitude',True),('longitude',float('nan')),('provider','unknown'),('area','北京大学'),('resolvedAt',float('inf'))]:
            place = {**self.item['resolvedPlace'],field:value}
            with self.subTest(field=field), self.assertRaises(ValueError): validate_place(self.item,place)
    def test_address_fallback_without_area(self):
        self.item['resolvedPlace']['area'] = None
        self.assertEqual(description_context(self.item)['location'], self.item['resolvedPlace']['label'])

    def boundary_place(self, nearby=False):
        self.item['resolvedPlace'].update(version=3, provider='apple-osm',
            label='青海省 · 青海湖附近' if nearby else '北京市 · 清华大学 · 至善路',
            area='青海湖' if nearby else '清华大学',
            displayName='青海 青海湖附近' if nearby else '北京 清华大学',
            boundaryID='relation/1234' if nearby else 'area/3607469216',
            areaRelation='nearby' if nearby else 'inside', placeKind='lake' if nearby else 'campus')
        return self.item['resolvedPlace']

    def test_boundary_city_and_name_reach_description(self):
        self.boundary_place()
        self.assertEqual(description_context(self.item)['location'], '北京 清华大学')

    def test_lakeside_proximity_cannot_be_promoted_to_containment(self):
        place = self.boundary_place(True)
        self.assertEqual(description_context(self.item)['location'], '青海 青海湖附近')
        for field, value in [('displayName', '青海 青海湖'), ('placeKind', 'campus'),
                             ('areaRelation', 'inside'), ('boundaryID', 'area/1234')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                validate_place(self.item, {**place, field: value})

    def test_boundary_result_still_respects_coordinate_and_user_priority(self):
        self.boundary_place()
        self.item['context'] = {'location': '用户指定地点'}
        self.assertEqual(description_context(self.item)['location'], '用户指定地点')
        self.item['context'] = {}
        self.item['metadata']['location']['latitude'] = 20
        self.assertEqual(description_context(self.item), {})


if __name__=='__main__': unittest.main()
