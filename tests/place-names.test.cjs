const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const read = name => fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun', name), 'utf8');

test('place lookup uses only Apple coordinate geocoding, never device location or source uploads', () => {
  const code = read('PlaceNameResolver.swift');
  assert.match(code, /reverseGeocodeLocation\(location, preferredLocale:/);
  assert.doesNotMatch(code, /CLLocationManager\(|requestWhenInUseAuthorization|requestAlwaysAuthorization|URLSession|Data\(contentsOf:/);
  assert.match(code, /mark\.areasOfInterest/);
  assert.match(code, /area: area, nearbyName: mark.name/);
  assert.doesNotMatch(code, /MKLocalSearch/);
  assert.match(code, /geocoder.cancelGeocode\(\)/);
  assert.match(code, /guard enabled, foreground else/);
  assert.match(code, /!pending.isEmpty, canRequest\(\)/);
});

test('place consent is off by default and saved only by settings confirmation', () => {
  assert.match(read('AppLanguage.swift'), /var onlinePlaceNames = false/);
  const settings = read('AppSettingsView.swift');
  assert.match(settings, /isOn: \$draft.onlinePlaceNames/);
  const confirm = settings.slice(settings.indexOf('private func confirm()'));
  assert.match(confirm, /store.savePlaceSettings\(names: draft.onlinePlaceNames, boundaries: draft.onlinePlaceBoundaries\)/);
  assert.doesNotMatch(settings.slice(0, settings.indexOf('private func confirm()')), /savePlaceSettings\(/);
  assert.match(read('AppLanguage.swift'), /var onlinePlaceBoundaries = false/);
  assert.match(settings, /isOn: \$draft.onlinePlaceBoundaries/);
});

test('boundary lookup is bounded, opt-in and independent of video analysis', () => {
  const code = read('PlaceBoundaryLookup.swift');
  assert.match(code, /is_in\(/);
  assert.match(code, /around:100/);
  assert.match(code, /count < 100/);
  assert.match(code, /http.statusCode == 200/);
  assert.match(code, /response.remark == nil/);
  assert.match(code, /data.count < 1_048_576/);
  assert.match(code, /PixfunBoundaryEndpoint/);
  assert.doesNotMatch(code, /sourcePath|file.name|MKLocalSearch/);
  assert.match(read('PlaceNameResolver.swift'), /if useBoundaries\(\), canRequest\(\), generation == current/);
  assert.match(read('PlaceNameResolver.swift'), /placeNamesCache.v3/);
  assert.match(read('PlaceNameResolver.swift'), /boundaryRetry == true \? 900/);
});

test('library refresh overlays local cache and keeps source coordinates searchable', () => {
  const store = read('WorkspaceStore.swift');
  assert.match(store, /applyingCache\(to: library.items, language: language.rawValue\)/);
  assert.match(store, /foreground: NSApp\?\.isActive == true/);
  assert.match(read('MediaSearch.swift'), /"Recorded coordinates", item.metadata\?\.location\?\.coordinates/);
  assert.match(read('MediaView.swift'), /Text\(LocalizedStringKey\(item.locationAttribution\)\)/);
  assert.match(store, /\/api\/desktop\/analysis\/place/);
  assert.match(read('MediaSearch.swift'), /item.locationGroup/);
});
