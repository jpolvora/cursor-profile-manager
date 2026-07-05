const test = require('node:test');
const assert = require('node:assert/strict');
const {
  extractInteractionContext,
  inferProjectKey,
  inferInstanceKey
} = require('./metadata');

test('inferInstanceKey prefers x-session-id', () => {
  const key = inferInstanceKey({
    'x-session-id': 'session-abc',
    'x-cursor-checksum': 'checksum-123'
  });
  assert.equal(key, 'session-abc');
});

test('inferProjectKey reads x-cursor-workspace header', () => {
  const key = inferProjectKey({
    'x-cursor-workspace': 'L:/source/cursor-profile-manager'
  }, '');
  assert.equal(key, 'L:/source/cursor-profile-manager');
});

test('inferProjectKey extracts workspacePath from JSON body', () => {
  const body = JSON.stringify({
    workspacePath: 'C:/Users/dev/projects/demo-app/src/index.ts'
  });
  const key = inferProjectKey({}, body);
  assert.equal(key, 'C:/Users/dev/projects/demo-app/src/index.ts');
});

test('extractInteractionContext stores metadata without authorization', () => {
  const context = extractInteractionContext(
    {
      authorization: 'Bearer secret-token',
      'x-session-id': 'win-1',
      'x-cursor-client-version': '2.0.0'
    },
    JSON.stringify({ workspace: '/Users/dev/my-app' }),
    { duration_ms: 120, response_status: 200 }
  );

  assert.equal(context.instance_key, 'win-1');
  assert.equal(context.project_key, '/Users/dev/my-app');

  const metadata = JSON.parse(context.metadata);
  assert.equal(metadata.duration_ms, 120);
  assert.equal(metadata.headers['x-session-id'], 'win-1');
  assert.equal(metadata.headers.authorization, undefined);
});
