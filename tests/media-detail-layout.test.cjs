const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaView.swift'), 'utf8');

test('catalog status stays in search information rather than a redundant toolbar row', () => {
  const native = name => fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun', name), 'utf8');
  const toolbar = native('MediaBrowserToolbar.swift');
  assert.doesNotMatch(toolbar, /catalogMessage|catalogError|Button\("Dismiss"\)/);
  const search = native('MediaSearchView.swift');
  assert.match(search, /MediaCatalogControls\(\)/);
  assert.match(search, /Text\(store.catalogMessage\)/);
  assert.match(search, /store.stopCatalog\(\)/);
  const catalog = native('MediaCatalog.swift');
  assert.match(catalog, /error is CancellationError/);
  assert.match(catalog, /URLError\)\?\.code != \.cancelled/);
  const store = native('WorkspaceStore.swift');
  assert.equal((store.match(/CatalogFailure.message\(error\)/g) || []).length, 3);
});

test('card tags read location then subject then activity, with scene only supplementary', () => {
  const search = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaSearch.swift'), 'utf8');
  const core = search.split('static func core(')[1].split('static func detailGroups(')[0];
  assert.ok(core.includes('[best(.location), best(.subject), best(.activity), best(.scene)]'));
  assert.ok(core.includes('.compactMap { $0 }'));
  assert.ok(core.includes('.prefix(3)'));
  assert.ok(!core.includes('best(.location) ?? best(.scene)'));
});

test('terminal analysis issues identify the stage and affected card instead of looking like pending work', () => {
  const overview = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaLibraryOverview.swift'), 'utf8');
  assert.ok(!overview.includes('个素材待处理'));
  assert.match(overview, /"失败 \\\(failed\)"/);
  assert.match(overview, /\$0.processingLabel == "Queued…"/);
  assert.match(overview, /Button \{ store.retryFailedAnalysis\(\) \} label:/);
  assert.match(overview, /Label\("Retry", systemImage: "arrow.clockwise"\)/);
  assert.match(overview, /PixfunButtonStyle\(kind: \.primary\)/);
  assert.match(overview, /accessibilityLabel\("Retry failed analyses"\)/);
  assert.match(overview, /item.attentionReason.map \{ item.name/);
  assert.match(source, /else if let reason = item.attentionReason/);
  assert.match(source, /Label\(LocalizedStringKey\(reason.rawValue\), systemImage: "exclamationmark.circle"\)/);
});

test('activity caption merges active and pending work while keeping real failures distinct', () => {
  const overview = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaLibraryOverview.swift'), 'utf8');
  const caption = overview.split('private var statusLine: String')[1].split('private var detail: String')[0];
  assert.match(caption, /"处理中 \\\(analyzing\)"/);
  assert.match(caption, /"失败 \\\(failed\)"/);
  assert.doesNotMatch(caption, /attentionSummaries|个素材|个排队中|未完成|排队|待重试/);
  assert.match(overview, /max\(0, analyzing - waiting - retrying\)/);
  assert.match(overview, /等待自动重试/);
  assert.match(overview, /\["failed", "error"\]\.contains/);
  assert.match(overview, /\.help\(detail\)/);
});

test('analysis status has a restrained accent surface and can wrap without a details entry', () => {
  const overview = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaLibraryOverview.swift'), 'utf8').split('struct MediaLibraryWelcomeView')[0];
  assert.match(overview, /font\(\.pixfun\(15, semibold: true\)\)/);
  assert.match(overview, /\.lineLimit\(2\)\.fixedSize\(horizontal: false, vertical: true\)/);
  assert.match(overview, /minHeight: 44/);
  assert.match(overview, /pixfunBrandSoft\.opacity\(0\.65\)/);
  assert.match(overview, /strokeBorder\(Color\.pixfunGold\.opacity\(0\.24\)\)/);
  assert.doesNotMatch(overview, /DisclosureGroup|Button\("Details"/);
});

test('original metadata uses a taller player and compact factual rows with optional technical details', () => {
  assert.match(source, /frame\(height: 420\)\.background\(\.black\)/);
  assert.match(source, /frame\(width: 240, alignment: \.leading\)/);
  assert.match(source, /originalMetadata\s+sourceFolderLink/);
  const metadata = source.split('private var originalMetadata: some View')[1].split('@ViewBuilder var analysisDetails')[0];
  for (const field of ['captureDate', 'camera', 'frameRateLabel', 'videoCodec', 'audioCodec', 'coordinates', 'mediaCreatedAt', 'dateSource']) {
    assert.ok(metadata.includes(field), field);
  }
  assert.match(metadata, /DisclosureGroup\("More file metadata"\)/);
  assert.match(metadata, /Text\(verbatim: value\)/);
  assert.match(metadata, /if item.kind != "image", let hasAudio/);
  assert.match(metadata, /if item.kind == "video", let fps/);
  assert.doesNotMatch(metadata, /resolvedPlace|recordedLocation|duration \?\? 0|hasAudio == true \? "Included" : "None"/);
});

test('shot navigation sits inside the player column, before original-file information', () => {
  const player = source.indexOf('else if let player = playback.player');
  const strip = source.indexOf('shotFilmstrip', player);
  const original = source.indexOf('Text("Original")', player);
  assert.ok(player < strip && strip < original);
  assert.match(source.slice(player, original), /item.kind == "video", item.segments.count > 1/);
});

test('one collapsed analysis panel combines parameters and description evidence without shot UI', () => {
  const analysis = source.slice(source.indexOf('var analysisDetails:'), source.indexOf('var shotFilmstrip:'));
  assert.ok(!analysis.includes('shotCard('));
  assert.ok(analysis.includes('analysisParameters('));
  assert.ok(analysis.includes('descriptionEvidence'));
  assert.match(analysis, /DisclosureGroup\("Analysis details"\)/);
  assert.ok(!source.includes('DisclosureGroup("Description details")'));
  assert.ok(!source.includes('DisclosureGroup("Shots & analysis")'));
  assert.ok(!source.includes('DisclosureGroup("Analysis & evidence")'));
  assert.ok(!source.includes('DisclosureGroup("Editing suggestions")'));
  const parameters = source.slice(source.indexOf('func analysisParameters('), source.indexOf('func shotTitle('));
  assert.ok(!parameters.includes('shotTitle('));
  assert.ok(!parameters.includes('timestamp('));
  assert.ok(parameters.includes('Updates with the thumbnail selected above.'));
  const status = source.slice(source.indexOf('var shotAnalysisStatus:'), source.indexOf('func analysisParameters('));
  assert.ok(!status.includes('Editable shots'));
  assert.ok(!status.includes('segments.count'));
  assert.match(source, /ScrollView\(\.horizontal, showsIndicators: true\)/);
  assert.match(source, /shotCard\(segment\)\.frame\(width: 180\)/);
  assert.match(source, /selectedSegment = segment.id; seek\(segment.start\)/);
});

test('generated title belongs above description text, not inside technical details', () => {
  const description = source.slice(source.indexOf('var editorialDescription:'), source.indexOf('var descriptionEvidence:'));
  const title = description.indexOf('media.description.title');
  const body = description.indexOf('if !item.descriptionParagraphs.isEmpty');
  assert.ok(title >= 0 && title < body);
  assert.ok(!description.includes('DisclosureGroup('));
  assert.ok(description.includes('title != item.name'));
  assert.ok(description.includes('Text(title).font(.pixfun(15, semibold: true))'));
  assert.ok(!description.includes('Text("Suggested title")'));
  const evidence = source.slice(source.indexOf('var descriptionEvidence:'), source.indexOf('func analysisActivity('));
  assert.ok(!evidence.includes('description.title'));
});
