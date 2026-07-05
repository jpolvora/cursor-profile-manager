const test = require('node:test');
const assert = require('node:assert/strict');
const {
  shouldCaptureHost,
  categorizeEndpoint,
  analyzeInteractions,
  hostMatchesSuffix
} = require('./endpointAnalysis');

test('shouldCaptureHost matches Cursor and AI provider domains', () => {
  assert.equal(shouldCaptureHost('api2.cursor.sh'), true);
  assert.equal(shouldCaptureHost('agent.api5.cursor.sh'), true);
  assert.equal(shouldCaptureHost('metrics.cursor.sh'), true);
  assert.equal(shouldCaptureHost('marketplace.cursorapi.com'), true);
  assert.equal(shouldCaptureHost('cursor.com'), true);
  assert.equal(shouldCaptureHost('api.openai.com'), true);
  assert.equal(shouldCaptureHost('api.anthropic.com'), true);
  assert.equal(shouldCaptureHost('github.com'), false);
  assert.equal(shouldCaptureHost('example.com'), false);
});

test('hostMatchesSuffix avoids false positives on unrelated domains', () => {
  assert.equal(hostMatchesSuffix('notcursorapi.evil.com', 'cursorapi.com'), false);
  assert.equal(hostMatchesSuffix('api2.cursor.sh', '.cursor.sh'), true);
});

test('categorizeEndpoint groups chat, telemetry, and auth paths', () => {
  assert.equal(categorizeEndpoint('/v1/chat/completions', 'api2.cursor.sh'), 'chat');
  assert.equal(categorizeEndpoint('/aiserver.v1.ChatService/StreamUnifiedChatWithTools', 'api2.cursor.sh'), 'chat');
  assert.equal(categorizeEndpoint('/tev1/v1/rgstr', 'api3.cursor.sh'), 'telemetry');
  assert.equal(categorizeEndpoint('/auth/full_stripe_profile', 'api2.cursor.sh'), 'auth');
  assert.equal(categorizeEndpoint('/_apis/public/gallery/extensionquery', 'marketplace.cursorapi.com'), 'extensions');
});

test('categorizeEndpoint groups agent, stream, composer, and subagent RPC paths', () => {
  assert.equal(categorizeEndpoint('/aiserver.v1.AgentService/Run', 'api2.cursor.sh'), 'agent');
  assert.equal(categorizeEndpoint('/aiserver.v1.BidiService/BidiAppend', 'api2.cursor.sh'), 'agent-stream');
  assert.equal(categorizeEndpoint('/aiserver.v1.ComposerService/Submit', 'api2.cursor.sh'), 'composer');
  assert.equal(categorizeEndpoint('/aiserver.v1.TaskService/Run', 'agent.api5.cursor.sh'), 'subagent');
});

test('analyzeInteractions aggregates endpoint counts', () => {
  const summary = analyzeInteractions([
    { method: 'POST', url: 'https://api2.cursor.sh/v1/chat/completions', response_status: 200, req_len: 100, res_len: 200 },
    { method: 'POST', url: 'https://api2.cursor.sh/v1/chat/completions', response_status: 200, req_len: 50, res_len: 80 },
    { method: 'GET', url: 'https://api2.cursor.sh/auth/full_stripe_profile', response_status: 200, req_len: 0, res_len: 10 }
  ]);

  assert.equal(summary.total, 3);
  assert.equal(summary.categories.chat, 2);
  assert.equal(summary.categories.auth, 1);
  assert.equal(summary.endpoints[0].path, '/v1/chat/completions');
  assert.equal(summary.endpoints[0].count, 2);
});
