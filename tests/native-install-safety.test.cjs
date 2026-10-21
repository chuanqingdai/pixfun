const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {assertAppStopped} = require('../scripts/native-install-safety.cjs');
const app = '/Users/fixture/Work with spaces/dist-native/Pixfun.app';
const processes = stdout => () => ({status:0, stdout});
test('never replace a running client or its remaining backend', () => {
  for (const executable of ['Contents/MacOS/Pixfun', 'Contents/Resources/backend/pixfun-service/pixfun-service']) {
    for (const args of ['', ' --fixture']) {
      assert.throws(() => assertAppStopped(app, processes('  ' + path.join(app, executable) + args + '\n')), /still running/);
    }
  }
});
test('other bundles and staged test services do not block an idle destination', () => {
  assert.doesNotThrow(() => assertAppStopped(app, processes('/tmp/staged/Pixfun.app/Contents/MacOS/Pixfun\n/usr/bin/node scripts/build-native.cjs\n')));
});
test('failed process inspection fails closed', () => {
  assert.throws(() => assertAppStopped(app, () => ({status:1, stdout:''})), /Cannot verify/);
  assert.throws(() => assertAppStopped(app, () => ({error:new Error('unavailable')})), /Cannot verify/);
});
test('installation guard precedes every mutation of the installed bundle', () => {
  const source = fs.readFileSync(path.join(__dirname, '../scripts/build-native.cjs'), 'utf8');
  const guard = source.indexOf('assertAppStopped(destinationApp)');
  assert(guard > source.indexOf("process.argv.includes('--stage-only')"));
  assert(guard < source.indexOf('fs.renameSync(destinationApp'));
  assert(guard < source.indexOf('fs.renameSync(app, destinationApp)'));
});
