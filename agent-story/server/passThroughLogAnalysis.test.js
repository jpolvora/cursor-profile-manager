const test = require('node:test');
const assert = require('node:assert/strict');
const {
  readPassThroughLogEntries,
  analyzePassThroughLog,
  classifyCapturePolicy,
  formatPassThroughReport
} = require('./passThroughLogAnalysis');

test('classifyCapturePolicy marks Cursor and unknown hosts', () => {
  assert.equal(classifyCapturePolicy('api2.cursor.sh'), 'default_mitm');
  assert.equal(classifyCapturePolicy('registry.npmjs.org'), 'not_in_default_mitm');
  assert.equal(classifyCapturePolicy('127.0.0.1'), 'expected_bypass');
});

test('analyzePassThroughLog aggregates connect and http entries', () => {
  const entries = readPassThroughLogEntries([
    '{"kind":"connect","host":"api2.cursor.sh","port":443}',
    '{"kind":"connect","host":"registry.npmjs.org","port":443}',
    '{"kind":"http","method":"GET","host":"api2.cursor.sh","path":"/auth/full_stripe_profile"}'
  ].join('\n'));

  const summary = analyzePassThroughLog(entries);
  assert.equal(summary.total, 3);
  assert.equal(summary.kinds.connect, 2);
  assert.equal(summary.hosts['api2.cursor.sh'], 2);
  assert.equal(summary.discovery.not_in_default_mitm.length, 1);
  assert.equal(summary.discovery.not_in_default_mitm[0].host, 'registry.npmjs.org');
});

test('formatPassThroughReport includes discovery section', () => {
  const summary = analyzePassThroughLog([
    { kind: 'connect', host: 'mcp.context7.com', port: 443 }
  ]);
  const report = formatPassThroughReport(summary);
  assert.match(report, /Pass-Through Proxy Traffic Analysis/);
  assert.match(report, /mcp\.context7\.com/);
  assert.match(report, /not_in_default_mitm/);
});
