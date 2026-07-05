const WORKSPACE_FIELDS = [
  'workspacePath', 'workspace', 'rootPath', 'repoPath', 'projectPath', 'cwd', 'workspaceRoot'
];

const METADATA_HEADER_KEYS = [
  'x-session-id',
  'x-request-id',
  'x-cursor-client-version',
  'x-cursor-client-type',
  'x-cursor-client-os',
  'x-cursor-client-arch',
  'x-cursor-timezone',
  'x-cursor-config-version',
  'x-ghost-mode',
  'connect-protocol-version',
  'content-type',
  'user-agent'
];

const WINDOWS_PATH = /[A-Za-z]:[\\/][^\s"'<>|]+/g;
const UNIX_PATH = /\/(?:Users|home|source|projects|work|dev|src|opt)[^\s"'<>|]+/g;

function normalizeHeaders(headers) {
  const out = {};
  if (!headers || typeof headers !== 'object') return out;
  for (const [key, value] of Object.entries(headers)) {
    out[String(key).toLowerCase()] = Array.isArray(value) ? value[0] : value;
  }
  return out;
}

function normalizePath(raw) {
  if (!raw || typeof raw !== 'string') return null;
  const trimmed = raw.trim().replace(/^file:\/\//i, '');
  if (!trimmed) return null;
  const normalized = trimmed.replace(/\\/g, '/').replace(/\/+$/, '');
  return normalized || null;
}

function basenameFromPath(pathValue) {
  const parts = pathValue.split('/').filter(Boolean);
  return parts.length ? parts[parts.length - 1] : pathValue;
}

function findWorkspaceInObject(obj, depth = 0) {
  if (!obj || depth > 6) return null;
  if (typeof obj === 'string') {
    const normalized = normalizePath(obj);
    if (normalized && (WINDOWS_PATH.test(obj) || UNIX_PATH.test(obj) || obj.includes('\\'))) {
      WINDOWS_PATH.lastIndex = 0;
      UNIX_PATH.lastIndex = 0;
      return normalized;
    }
    return null;
  }
  if (Array.isArray(obj)) {
    for (const item of obj) {
      const found = findWorkspaceInObject(item, depth + 1);
      if (found) return found;
    }
    return null;
  }
  if (typeof obj === 'object') {
    for (const field of WORKSPACE_FIELDS) {
      if (obj[field]) {
        const normalized = normalizePath(String(obj[field]));
        if (normalized) return normalized;
      }
    }
    for (const value of Object.values(obj)) {
      const found = findWorkspaceInObject(value, depth + 1);
      if (found) return found;
    }
  }
  return null;
}

function findPathInText(text) {
  if (!text) return null;
  const winMatch = text.match(WINDOWS_PATH);
  if (winMatch && winMatch.length) {
    return normalizePath(winMatch[0]);
  }
  const unixMatch = text.match(UNIX_PATH);
  if (unixMatch && unixMatch.length) {
    return normalizePath(unixMatch[0]);
  }
  return null;
}

function inferProjectKey(headers, bodyText) {
  const normalizedHeaders = normalizeHeaders(headers);
  const headerWorkspace = normalizedHeaders['x-cursor-workspace'] || normalizedHeaders['x-workspace-path'];
  if (headerWorkspace) {
    return normalizePath(headerWorkspace);
  }

  if (bodyText) {
    try {
      const parsed = JSON.parse(bodyText);
      const fromObject = findWorkspaceInObject(parsed);
      if (fromObject) return fromObject;
    } catch {
      // fall through to regex scan
    }
    const fromText = findPathInText(bodyText);
    if (fromText) {
      const parts = fromText.split('/');
      if (parts.length > 1) {
        parts.pop();
        return parts.join('/') || fromText;
      }
      return fromText;
    }
  }

  return null;
}

function inferInstanceKey(headers) {
  const normalizedHeaders = normalizeHeaders(headers);
  return normalizedHeaders['x-session-id']
    || normalizedHeaders['x-cursor-session-id']
    || normalizedHeaders['x-cursor-checksum']
    || null;
}

function buildMetadata(headers, bodyText, extras = {}) {
  const normalizedHeaders = normalizeHeaders(headers);
  const headerSnapshot = {};
  for (const key of METADATA_HEADER_KEYS) {
    if (normalizedHeaders[key]) {
      headerSnapshot[key] = normalizedHeaders[key];
    }
  }

  const metadata = {
    headers: headerSnapshot,
    instance_id: inferInstanceKey(headers),
    project_path: inferProjectKey(headers, bodyText),
    ...extras
  };

  if (metadata.project_path) {
    metadata.project_label = basenameFromPath(metadata.project_path);
  }

  if (extras.capture) {
    metadata.capture = extras.capture;
    const req = extras.capture.request;
    const res = extras.capture.response;
    if (req?.usage) metadata.request_usage = req.usage;
    if (res?.usage) metadata.usage = res.usage;
    if (res?.tokens_per_second != null) metadata.tokens_per_second = res.tokens_per_second;
    if (res?.time_to_first_token_ms != null) metadata.time_to_first_token_ms = res.time_to_first_token_ms;
    if (res?.streaming != null) metadata.streaming = res.streaming;
    if (res?.stream_event_count != null) metadata.stream_event_count = res.stream_event_count;
    if (req?.tools?.length) metadata.tools = req.tools;
    if (req?.system_prompt_preview) metadata.system_prompt_preview = req.system_prompt_preview;
    if (req?.prompt_preview) metadata.prompt_preview = req.prompt_preview;
    if (res?.assistant_text_preview) metadata.assistant_text_preview = res.assistant_text_preview;
  }

  return metadata;
}

function extractInteractionContext(headers, bodyText, extras = {}) {
  const metadata = buildMetadata(headers, bodyText, extras);
  return {
    project_key: metadata.project_path || null,
    instance_key: metadata.instance_id || null,
    metadata: JSON.stringify(metadata)
  };
}

module.exports = {
  extractInteractionContext,
  inferProjectKey,
  inferInstanceKey,
  buildMetadata,
  normalizeHeaders
};
