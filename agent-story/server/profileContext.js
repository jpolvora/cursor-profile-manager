const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { normalizePath, basenameFromPath } = require('./metadata');

const MARKER_FILENAME = 'cursor-profile-manager.context.json';
const DEFAULT_PROXY_PORT = 8080;

/** @type {Map<string, object>} normalized userDataDir -> registration */
const registryByUserDataDir = new Map();
/** @type {Map<number, string>} mainProcessId -> normalized userDataDir */
const registryByMainPid = new Map();
/** @type {Map<string, object>} x-session-id -> resolved profile context */
const sessionCache = new Map();

let clientPidCache = new Map();
const CLIENT_PID_CACHE_MAX = 500;
let clientPortMapCache = { at: 0, port: DEFAULT_PROXY_PORT, map: new Map() };

function refreshClientPortMap(proxyPort = DEFAULT_PROXY_PORT) {
  const now = Date.now();
  if (now - clientPortMapCache.at < 1500 && clientPortMapCache.port === proxyPort) {
    return clientPortMapCache.map;
  }

  const map = new Map();
  if (process.platform === 'win32') {
    try {
      const script = [
        `$out = @{};`,
        `Get-NetTCPConnection -LocalPort ${Number(proxyPort)} -State Established -ErrorAction SilentlyContinue | ForEach-Object {`,
        `  $rp = $_.RemotePort;`,
        `  $client = Get-NetTCPConnection -LocalPort $rp -RemotePort ${Number(proxyPort)} -State Established -ErrorAction SilentlyContinue | Select-Object -First 1;`,
        `  if ($client) { $out[[string]$rp] = $client.OwningProcess }`,
        `};`,
        `$out | ConvertTo-Json -Compress`
      ].join(' ');
      const output = runPowerShell(script);
      if (output) {
        const parsed = JSON.parse(output.replace(/^\uFEFF/, ''));
        for (const [remotePort, pid] of Object.entries(parsed)) {
          const portNum = Number(remotePort);
          const pidNum = Number(pid);
          if (portNum > 0 && pidNum > 0) {
            map.set(portNum, pidNum);
          }
        }
      }
    } catch {
      // keep previous map if refresh fails
      return clientPortMapCache.map;
    }
  }

  clientPortMapCache = { at: now, port: proxyPort, map };
  return map;
}

function getClientSocketFromContext(ctx) {
  return ctx?.clientToProxyRequest?.socket
    || ctx?.connectRequest?.socket
    || null;
}

function normalizeUserDataDir(raw) {
  if (!raw) return null;
  return String(raw).replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();
}

function readProfileMarker(userDataDir) {
  if (!userDataDir) return null;

  const candidates = [
    userDataDir,
    userDataDir.replace(/\//g, '\\'),
    userDataDir.replace(/\\/g, '/')
  ];

  for (const dir of candidates) {
    const markerPath = path.join(dir, MARKER_FILENAME);
    try {
      if (!fs.existsSync(markerPath)) continue;
      let raw = fs.readFileSync(markerPath, 'utf8');
      if (raw.charCodeAt(0) === 0xFEFF) {
        raw = raw.slice(1);
      }
      const parsed = JSON.parse(raw);
      if (!parsed || typeof parsed !== 'object') continue;
      return parsed;
    } catch {
      // try next path variant
    }
  }

  return null;
}

function buildProfileContext(source) {
  if (!source || typeof source !== 'object') return null;

  const userDataDir = normalizePath(source.userDataDir || source.UserDataDir || source.user_data_dir);
  const projectPath = normalizePath(source.projectPath || source.ProjectPath || source.project_path);
  const profileId = source.profileId || source.ProfileId || source.profile_id || null;
  const profileName = source.profileName || source.ProfileName || source.profile_name || null;
  const mainProcessId = source.mainProcessId || source.main_process_id || source.mainPid || null;

  if (!userDataDir && !profileId && !projectPath) {
    return null;
  }

  const context = {
    profile_id: profileId,
    profile_name: profileName,
    user_data_dir: userDataDir,
    project_path: projectPath || userDataDir || null,
    project_label: projectPath
      ? basenameFromPath(projectPath)
      : (profileName || (userDataDir ? basenameFromPath(userDataDir) : null)),
    main_process_id: mainProcessId ? Number(mainProcessId) : null,
    source: source.source || 'unknown'
  };

  return context;
}

function registerProfileSession(payload) {
  const context = buildProfileContext({ ...payload, source: 'registry' });
  if (!context || !context.user_data_dir) {
    return null;
  }

  const key = normalizeUserDataDir(context.user_data_dir);
  const previous = registryByUserDataDir.get(key);
  if (previous?.main_process_id && previous.main_process_id !== context.main_process_id) {
    registryByMainPid.delete(previous.main_process_id);
  }

  registryByUserDataDir.set(key, context);
  if (context.main_process_id) {
    registryByMainPid.set(context.main_process_id, key);
  }
  return context;
}

function lookupProfileContextByMainPid(mainProcessId) {
  const pid = Number(mainProcessId);
  if (!Number.isFinite(pid) || pid <= 0) return null;

  const key = registryByMainPid.get(pid);
  if (!key) return null;

  const registered = registryByUserDataDir.get(key);
  if (!registered) return null;

  return { ...registered, source: 'registry' };
}

function setClientPidCacheEntry(cacheKey, pid) {
  if (clientPidCache.size >= CLIENT_PID_CACHE_MAX) {
    const oldestKey = clientPidCache.keys().next().value;
    if (oldestKey != null) {
      clientPidCache.delete(oldestKey);
    }
  }
  clientPidCache.set(cacheKey, { at: Date.now(), pid });
}

function unregisterProfileSession(profileId) {
  for (const [key, ctx] of registryByUserDataDir.entries()) {
    if (ctx.profile_id === profileId) {
      registryByUserDataDir.delete(key);
      if (ctx.main_process_id) {
        registryByMainPid.delete(ctx.main_process_id);
      }
      return true;
    }
  }
  return false;
}

function listProfileSessions() {
  return Array.from(registryByUserDataDir.values());
}

function lookupProfileContextByUserDataDir(userDataDir) {
  const key = normalizeUserDataDir(userDataDir);
  if (!key) return null;

  const registered = registryByUserDataDir.get(key);
  if (registered) {
    return { ...registered, source: 'registry' };
  }

  const marker = readProfileMarker(userDataDir);
  if (marker) {
    return buildProfileContext({ ...marker, source: 'marker' });
  }

  return null;
}

function parseUserDataDirFromCommandLine(commandLine) {
  if (!commandLine) return null;
  const match = commandLine.match(/--user-data-dir=(?:"([^"]+)"|([^\s]+))/i);
  if (!match) return null;
  return normalizePath(match[1] || match[2]);
}

function runPowerShell(command) {
  return execFileSync(
    'powershell.exe',
    ['-NoProfile', '-Command', command],
    { encoding: 'utf8', timeout: 4000, windowsHide: true }
  ).trim();
}

function resolveClientProcessId(clientRemotePort, proxyPort = DEFAULT_PROXY_PORT) {
  if (!clientRemotePort) return null;

  const cacheKey = `${proxyPort}:${clientRemotePort}`;
  const cached = clientPidCache.get(cacheKey);
  if (cached && Date.now() - cached.at < 30000) {
    return cached.pid;
  }

  const portMap = refreshClientPortMap(proxyPort);
  let pid = portMap.get(Number(clientRemotePort)) || null;

  if (!pid && process.platform === 'win32') {
    try {
      const script = [
        `$row = Get-NetTCPConnection -LocalPort ${Number(clientRemotePort)} -RemotePort ${Number(proxyPort)} -State Established -ErrorAction SilentlyContinue | Select-Object -First 1`,
        'if ($row) { $row.OwningProcess }'
      ].join('; ');
      const output = runPowerShell(script);
      const parsed = parseInt(output, 10);
      if (Number.isFinite(parsed) && parsed > 0) {
        pid = parsed;
      }
    } catch {
      pid = null;
    }
  }

  if (pid) {
    setClientPidCacheEntry(cacheKey, pid);
  }
  return pid;
}

function getParentProcessId(pid) {
  if (process.platform !== 'win32' || !pid) return null;
  try {
    const output = runPowerShell(`(Get-CimInstance Win32_Process -Filter "ProcessId=${Number(pid)}").ParentProcessId`);
    const parentPid = parseInt(output, 10);
    return Number.isFinite(parentPid) && parentPid > 0 ? parentPid : null;
  } catch {
    return null;
  }
}

function getProcessCommandLine(pid) {
  if (process.platform !== 'win32' || !pid) return null;
  try {
    return runPowerShell(`(Get-CimInstance Win32_Process -Filter "ProcessId=${Number(pid)}").CommandLine`);
  } catch {
    return null;
  }
}

function resolveUserDataDirFromProcessTree(startPid, maxDepth = 10) {
  let pid = Number(startPid);
  for (let depth = 0; depth < maxDepth && pid; depth++) {
    const commandLine = getProcessCommandLine(pid);
    const userDataDir = parseUserDataDirFromCommandLine(commandLine);
    if (userDataDir) {
      return userDataDir;
    }
    pid = getParentProcessId(pid);
  }
  return null;
}

function resolveProfileContextFromClientSocket(socket, proxyPort = DEFAULT_PROXY_PORT) {
  if (!socket) return null;

  const clientRemotePort = socket.remotePort;
  const clientPid = resolveClientProcessId(clientRemotePort, proxyPort);
  if (!clientPid) return null;

  const registeredKey = registryByMainPid.get(clientPid);
  if (registeredKey && registryByUserDataDir.has(registeredKey)) {
    return { ...registryByUserDataDir.get(registeredKey), source: 'registry-pid', client_pid: clientPid };
  }

  const userDataDir = resolveUserDataDirFromProcessTree(clientPid);
  if (!userDataDir) return null;

  const context = lookupProfileContextByUserDataDir(userDataDir);
  if (!context) {
    return buildProfileContext({
      userDataDir,
      source: 'process-tree',
      mainProcessId: clientPid
    });
  }

  return { ...context, client_pid: clientPid };
}

function rememberSessionProfile(sessionId, profileContext) {
  if (!sessionId || !profileContext) return;
  sessionCache.set(String(sessionId), profileContext);
}

function lookupSessionProfile(sessionId) {
  if (!sessionId) return null;
  return sessionCache.get(String(sessionId)) || null;
}

function resolveProfileContextForCapture(ctx, proxyPort = DEFAULT_PROXY_PORT) {
  const headers = ctx?.clientToProxyRequest?.headers || {};
  const sessionId = headers['x-session-id'] || headers['x-cursor-session-id'] || null;

  let profileContext = resolveProfileContextFromClientSocket(
    getClientSocketFromContext(ctx),
    proxyPort
  );

  if (!profileContext && sessionId) {
    profileContext = lookupSessionProfile(sessionId);
  }

  if (!profileContext) {
    const sessions = listProfileSessions();
    if (sessions.length === 1) {
      profileContext = { ...sessions[0], source: 'single-session-fallback' };
    }
  }

  if (profileContext && sessionId) {
    rememberSessionProfile(sessionId, profileContext);
  }

  return profileContext;
}

function clearProfileSessionCaches() {
  registryByUserDataDir.clear();
  registryByMainPid.clear();
  sessionCache.clear();
  clientPidCache.clear();
  clientPortMapCache = { at: 0, port: DEFAULT_PROXY_PORT, map: new Map() };
}

function resolveProfilesJsonPath() {
  const fromEnv = process.env.CURSOR_PROFILES_DIR;
  if (fromEnv) {
    return path.join(fromEnv, 'profiles.json');
  }
  const home = process.env.USERPROFILE || process.env.HOME;
  if (!home) return null;
  return path.join(home, '.cursor-profiles', 'profiles.json');
}

function loadProfileSessionsFromMarkers() {
  const profilesPath = resolveProfilesJsonPath();
  if (!profilesPath || !fs.existsSync(profilesPath)) {
    return [];
  }

  let profiles = [];
  try {
    let raw = fs.readFileSync(profilesPath, 'utf8');
    if (raw.charCodeAt(0) === 0xFEFF) {
      raw = raw.slice(1);
    }
    profiles = JSON.parse(raw);
  } catch {
    return [];
  }

  if (!Array.isArray(profiles)) {
    return [];
  }

  const registered = [];
  for (const profile of profiles) {
    const userDataDir = profile?.UserDataDir || profile?.userDataDir;
    if (!userDataDir) continue;

    const marker = readProfileMarker(userDataDir);
    if (!marker) continue;

    const context = registerProfileSession({
      profileId: marker.profileId || profile.Id || profile.id,
      profileName: marker.profileName || profile.Name || profile.name,
      userDataDir: marker.userDataDir || userDataDir,
      projectPath: marker.projectPath || profile.ProjectPath || profile.projectPath || null,
      mainProcessId: marker.mainProcessId || null
    });
    if (context) {
      registered.push(context);
    }
  }

  return registered;
}

function getProjectLabelForKey(projectKey) {
  if (!projectKey || projectKey === '__unassigned__') {
    return 'Unassigned';
  }

  for (const session of registryByUserDataDir.values()) {
    if (session.project_path === projectKey || session.user_data_dir === projectKey) {
      return session.project_label || session.profile_name || basenameFromPath(projectKey);
    }
  }

  return basenameFromPath(projectKey) || projectKey;
}

module.exports = {
  MARKER_FILENAME,
  buildProfileContext,
  registerProfileSession,
  unregisterProfileSession,
  listProfileSessions,
  readProfileMarker,
  lookupProfileContextByUserDataDir,
  lookupProfileContextByMainPid,
  parseUserDataDirFromCommandLine,
  resolveProfileContextFromClientSocket,
  resolveProfileContextForCapture,
  rememberSessionProfile,
  lookupSessionProfile,
  clearProfileSessionCaches,
  normalizeUserDataDir,
  getClientSocketFromContext,
  loadProfileSessionsFromMarkers,
  getProjectLabelForKey,
  readProfileMarkerContent: readProfileMarker
};
