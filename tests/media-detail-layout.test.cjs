const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaView.swift'), 'utf8');

test('terminal analysis issues identify the stage and affected card instead of looking like pending work', () => {
  const overview = fs.readFileSync(path.join(__dirname, '../native/Sources/Pixfun/MediaLibraryOverview.swift'), 'utf8');
  assert.ok(!overview.includes('个素材待处理'));
  assert.match(overview, /parts.append\(contentsOf: attentionSummaries\)/);
  assert.match(overview, /\$0.processingLabel == "Queued…"/);
  assert.match(overview, /Button\("Retry failed analyses"\) \{ store.retryFailedAnalysis\(\) \}/);
  assert.match(source, /else if let reason = item.attentionReason/);
  assert.match(source, /Label\(LocalizedStringKey\(reason.rawValue\), systemImage: "exclamationmark.circle"\)/);
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
