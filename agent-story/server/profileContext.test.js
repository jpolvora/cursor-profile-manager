const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const {
  buildProfileContext,
  registerProfileSession,
  lookupProfileContextByUserDataDir,
  lookupProfileContextByMainPid,
  parseUserDataDirFromCommandLine,
  clearProfileSessionCaches,
  readProfileMarker,
  MARKER_FILENAME
} = require('./profileContext');
const { extractInteractionContext } = require('./metadata');

test('parseUserDataDirFromCommandLine reads quoted and unquoted values', () => {
  const quoted = parseUserDataDirFromCommandLine('"C:\\Program Files\\cursor\\Cursor.exe" --user-data-dir="D:\\cursor\\work" --new-window');
  assert.equal(quoted, 'D:/cursor/work');

  const plain = parseUserDataDirFromCommandLine('Cursor.exe --user-data-dir=D:/cursor/demo --new-window');
  assert.equal(plain, 'D:/cursor/demo');
});

test('buildProfileContext normalizes profile fields', () => {
  const context = buildProfileContext({
    profileId: 'abc-123',
    profileName: 'Work',
    userDataDir: 'D:\\cursor\\work',
    projectPath: 'L:/source/demo-app'
  });

  assert.equal(context.profile_id, 'abc-123');
  assert.equal(context.profile_name, 'Work');
  assert.equal(context.user_data_dir, 'D:/cursor/work');
  assert.equal(context.project_path, 'L:/source/demo-app');
  assert.equal(context.project_label, 'demo-app');
});

test('registerProfileSession and marker lookup share project path', () => {
  clearProfileSessionCaches();

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-story-profile-'));
  const markerPath = path.join(tempDir, MARKER_FILENAME);
  const payload = {
    profileId: 'pid-1',
    profileName: 'Demo',
    userDataDir: tempDir,
    projectPath: 'L:/source/demo-app',
    mainProcessId: 4242
  };

  try {
    registerProfileSession(payload);
    fs.writeFileSync(markerPath, JSON.stringify(payload), 'utf8');

    const fromRegistry = lookupProfileContextByUserDataDir(tempDir);
    assert.equal(fromRegistry.project_path, 'L:/source/demo-app');
    assert.equal(fromRegistry.profile_name, 'Demo');
  }
  finally {
    clearProfileSessionCaches();
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('buildProfileContext uses userDataDir when projectPath is missing', () => {
  const context = buildProfileContext({
    profileId: 'abc-123',
    profileName: 'jpolvora',
    userDataDir: 'D:\\cursor\\jpolvora',
    projectPath: null
  });

  assert.equal(context.project_path, 'D:/cursor/jpolvora');
  assert.equal(context.project_label, 'jpolvora');
});

test('readProfileMarker strips UTF-8 BOM written by PowerShell', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-story-bom-'));
  const markerPath = path.join(tempDir, MARKER_FILENAME);
  const payload = {
    profileId: 'pid-1',
    profileName: 'Demo',
    userDataDir: tempDir,
    projectPath: 'L:/source/demo-app'
  };

  try {
    const json = JSON.stringify(payload);
    fs.writeFileSync(markerPath, `\uFEFF${json}`, 'utf8');
    const marker = readProfileMarker(tempDir);
    assert.equal(marker.profileId, 'pid-1');
    assert.equal(marker.profileName, 'Demo');
  }
  finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('registerProfileSession replaces stale main-process mapping', () => {
  clearProfileSessionCaches();

  const payload = {
    profileId: 'pid-1',
    profileName: 'Demo',
    userDataDir: 'D:/cursor/work',
    projectPath: 'L:/source/demo-app'
  };

  registerProfileSession({ ...payload, mainProcessId: 1111 });
  assert.equal(lookupProfileContextByMainPid(1111)?.profile_id, 'pid-1');

  registerProfileSession({ ...payload, mainProcessId: 2222 });
  assert.equal(lookupProfileContextByMainPid(1111), null);
  assert.equal(lookupProfileContextByMainPid(2222)?.profile_id, 'pid-1');

  clearProfileSessionCaches();
});

test('extractInteractionContext prefers registered project over empty body', () => {
  const context = extractInteractionContext(
    { 'x-session-id': 'win-42' },
    '{}',
    {
      profileContext: buildProfileContext({
        profileId: 'pid-1',
        profileName: 'Work',
        userDataDir: 'D:/cursor/work',
        projectPath: 'L:/source/cursor-profile-manager'
      })
    }
  );

  assert.equal(context.project_key, 'L:/source/cursor-profile-manager');
  assert.equal(context.instance_key, 'pid-1:win-42');

  const metadata = JSON.parse(context.metadata);
  assert.equal(metadata.profile_manager.profile_name, 'Work');
});
