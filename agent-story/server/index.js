const { Proxy } = require('http-mitm-proxy');
const express = require('express');
const cors = require('cors');
const {
  insertInteraction,
  updateInteraction,
  getInteractions,
  searchInteractions,
  getThreads,
  getInteractionsByThread,
  getProjects,
  getInstances,
  getLatestInteractionId,
  readDb
} = require('./db');
const { extractInteractionContext } = require('./metadata');
const { buildCaptureRecord, isStreamingContentType, bufferToPlainText, decompressBody } = require('./capture');
const { shouldCaptureHost, analyzeInteractions } = require('./endpointAnalysis');
const {
  registerProfileSession,
  unregisterProfileSession,
  listProfileSessions,
  resolveProfileContextForCapture,
  loadProfileSessionsFromMarkers,
  getProjectLabelForKey
} = require('./profileContext');
const sse = require('./sse');

const proxy = new Proxy();
const app = express();
const API_PORT = 3001;

app.use(cors());
app.use(express.json());

function parseInteractionFilters(query) {
  return {
    thread: query.thread || null,
    project: query.project || null,
    instance: query.instance || null,
    q: query.q || '',
    method: query.method || 'ALL'
  };
}

function fetchInteractions(filters, limit = 100) {
  const { thread, project, instance, q, method } = filters;
  if (thread && !q.trim()) {
    return getInteractionsByThread.all(thread, limit);
  }
  if (q.trim()) {
    const methodFilter = method && method !== 'ALL' ? method : '%';
    return searchInteractions.all(q.trim(), methodFilter, limit, { thread, project, instance });
  }
  return getInteractions.all({ thread, project, instance, method });
}

function notifyClients(event, data) {
  sse.broadcast(event, data);
}

function snapshotCaptureContext(ctx, resChunks) {
  return {
    captureKey: ctx.captureKey,
    provisionalRowId: ctx.provisionalRowId || null,
    requestStartTime: ctx.requestStartTime,
    firstChunkTime: ctx.firstChunkTime,
    totalResponseBytes: ctx.totalResponseBytes,
    isSSL: ctx.isSSL,
    profileContext: ctx.profileContext || null,
    reqBody: ctx.reqBody ? Buffer.from(ctx.reqBody) : Buffer.alloc(0),
    resBody: Buffer.concat(resChunks),
    method: ctx.clientToProxyRequest.method,
    url: ctx.clientToProxyRequest.url || '',
    reqHeaders: { ...ctx.clientToProxyRequest.headers },
    resStatusCode: ctx.serverToProxyResponse?.statusCode || 0,
    resHeaders: { ...(ctx.serverToProxyResponse?.headers || {}) },
    host: ctx.clientToProxyRequest.headers.host || ''
  };
}

function buildCaptureRecordFromSnapshot(snapshot) {
  return buildCaptureRecord({
    clientToProxyRequest: {
      method: snapshot.method,
      url: snapshot.url,
      headers: snapshot.reqHeaders
    },
    serverToProxyResponse: {
      statusCode: snapshot.resStatusCode,
      headers: snapshot.resHeaders
    },
    isSSL: snapshot.isSSL,
    requestStartTime: snapshot.requestStartTime,
    firstChunkTime: snapshot.firstChunkTime,
    totalResponseBytes: snapshot.totalResponseBytes,
    reqBody: snapshot.reqBody,
    resBody: snapshot.resBody
  });
}

function persistCaptureRecord(snapshot) {
  const record = buildCaptureRecordFromSnapshot(snapshot);
  const durationMs = Date.now() - (snapshot.requestStartTime || Date.now());
  const profileContext = snapshot.profileContext;
  const context = extractInteractionContext(
    snapshot.reqHeaders,
    record.request_body,
    {
      duration_ms: durationMs,
      response_status: record.response_status,
      host: snapshot.host,
      capture: record.capture,
      profileContext
    }
  );

  const rowPayload = {
    method: record.method,
    url: record.url,
    request_headers: record.request_headers,
    request_body: record.request_body,
    response_status: record.response_status,
    response_headers: record.response_headers,
    response_body: record.response_body,
    project_key: context.project_key,
    instance_key: context.instance_key,
    metadata: context.metadata
  };

  let rowId = snapshot.provisionalRowId;
  if (rowId) {
    updateInteraction.run({ ...rowPayload, id: rowId });
  } else {
    const result = insertInteraction(rowPayload);
    rowId = Number(result.lastInsertRowid);
  }

  const interactionPayload = {
    id: rowId,
    project_key: context.project_key,
    instance_key: context.instance_key,
    capture_key: snapshot.captureKey,
    streaming: record.capture.response.streaming,
    tokens_per_second: record.capture.response.tokens_per_second
  };

  notifyClients('interaction', interactionPayload);

  const resSummary = record.capture.response;
  console.log(
    `[Proxy] #${rowId} ${record.method} ${record.url}` +
    (context.project_key ? ` [${context.project_key.split('/').pop()}]` : ' [unassigned]') +
    (resSummary.streaming ? ' [stream]' : '') +
    (resSummary.tokens_per_second ? ` ${resSummary.tokens_per_second} tok/s` : '') +
    ` ${durationMs}ms`
  );
}

function insertProvisionalStreamingCapture(ctx, host) {
  if (ctx.provisionalRowId) return;

  const profileContext = ctx.profileContext || null;
  const urlStr = (ctx.isSSL ? 'https://' : 'http://') + host + (ctx.clientToProxyRequest.url || '');
  const reqRaw = decompressBody(ctx.reqBody || Buffer.alloc(0), ctx.clientToProxyRequest.headers['content-encoding']);
  const requestBody = bufferToPlainText(reqRaw, ctx.clientToProxyRequest.headers['content-type']);
  const context = extractInteractionContext(
    ctx.clientToProxyRequest.headers,
    requestBody,
    {
      duration_ms: Date.now() - (ctx.requestStartTime || Date.now()),
      response_status: ctx.serverToProxyResponse?.statusCode || 0,
      host,
      profileContext
    }
  );

  let metadata = {};
  try {
    metadata = JSON.parse(context.metadata);
  } catch {
    metadata = {};
  }
  metadata.streaming_in_progress = true;

  const result = insertInteraction({
    method: ctx.clientToProxyRequest.method,
    url: urlStr,
    request_headers: JSON.stringify(ctx.clientToProxyRequest.headers),
    request_body: requestBody,
    response_status: ctx.serverToProxyResponse?.statusCode || 0,
    response_headers: JSON.stringify(ctx.serverToProxyResponse?.headers || {}),
    response_body: '',
    project_key: context.project_key,
    instance_key: context.instance_key,
    metadata: JSON.stringify(metadata)
  });

  ctx.provisionalRowId = Number(result.lastInsertRowid);

  notifyClients('interaction', {
    id: ctx.provisionalRowId,
    project_key: context.project_key,
    instance_key: context.instance_key,
    capture_key: ctx.captureKey,
    streaming: true,
    provisional: true
  });
}

// SSE stream for live UI updates
app.get('/api/events', (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders();

  const latest = getLatestInteractionId.get();
  res.write(`event: connected\ndata: ${JSON.stringify({ max_id: latest.max_id || 0 })}\n\n`);

  sse.addClient(res);

  const heartbeat = setInterval(() => {
    res.write(': heartbeat\n\n');
  }, 25000);

  req.on('close', () => {
    clearInterval(heartbeat);
  });
});

app.get('/api/interactions', (req, res) => {
  const filters = parseInteractionFilters(req.query);
  try {
    res.json(fetchInteractions(filters));
  } catch (err) {
    const isSearchError = filters.q && filters.q.trim();
    res.status(isSearchError ? 400 : 500).json({ error: err.message });
  }
});

app.get('/api/threads', (req, res) => {
  try {
    res.json(getThreads.all());
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/projects', (req, res) => {
  try {
    const projects = getProjects.all();
    const instances = getInstances.all(null, null);
    const instancesByProject = instances.reduce((acc, row) => {
      const key = row.project_key || '__none__';
      if (!acc[key]) acc[key] = [];
      acc[key].push(row);
      return acc;
    }, {});

    res.json(projects.map(project => {
      const instanceBucket = project.project_key === '__unassigned__' ? '__none__' : project.project_key;
      const sessions = (instancesByProject[instanceBucket] || [])
        .slice()
        .sort((a, b) => String(b.last_timestamp).localeCompare(String(a.last_timestamp)));

      return {
        ...project,
        label: getProjectLabelForKey(project.project_key),
        sessions
      };
    }));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/instances', (req, res) => {
  const project = req.query.project || null;
  try {
    res.json(getInstances.all(project, project));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/endpoints/summary', (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit, 10) || 5000, 10000);
    const rows = readDb.prepare(`
      SELECT method, url, response_status,
        length(request_body) AS req_len,
        length(response_body) AS res_len
      FROM interactions
      ORDER BY id DESC
      LIMIT ?
    `).all(limit);
    res.json(analyzeInteractions(rows));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/interactions/search', (req, res) => {
  const filters = parseInteractionFilters(req.query);
  const parsedLimit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
  try {
    res.json(fetchInteractions(filters, parsedLimit));
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.get('/api/profile-sessions', (req, res) => {
  try {
    res.json(listProfileSessions());
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/profile-sessions/register', (req, res) => {
  try {
    const context = registerProfileSession(req.body || {});
    if (!context) {
      res.status(400).json({ error: 'userDataDir is required' });
      return;
    }
    res.json(context);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.delete('/api/profile-sessions/:profileId', (req, res) => {
  try {
    const removed = unregisterProfileSession(req.params.profileId);
    res.json({ removed });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

const PROXY_PORT = 8080;

const EXPECTED_BYPASS_HOST_SUFFIXES = [
  'localhost',
  '127.0.0.1',
  'github.com',
  'gitlab.com',
  'bitbucket.org'
];

function isExpectedBypassHost(host) {
  const h = String(host || '').toLowerCase();
  if (!h) return true;
  return EXPECTED_BYPASS_HOST_SUFFIXES.some((suffix) => h === suffix || h.endsWith('.' + suffix));
}

function logBypassTunnelConnect(host, port) {
  const target = `${host}:${port}`;
  const expected = isExpectedBypassHost(host);
  console.log(`[Bypass] CONNECT ${target}${expected ? ' (expected)' : ' (unexpected — not MITM)'}`);

  if (expected) {
    return;
  }

  setImmediate(() => {
    try {
      insertInteraction({
        method: 'CONNECT',
        url: `tunnel://${target}`,
        request_headers: '{}',
        request_body: '',
        response_status: 0,
        response_headers: '{}',
        response_body: '',
        project_key: null,
        instance_key: null,
        metadata: JSON.stringify({
          capture_kind: 'bypass_tunnel',
          host,
          port: Number(port) || port,
          unexpected: true
        })
      });
    } catch (err) {
      console.error('Bypass tunnel log error:', err);
    }
  });
}

function persistPartialCapture(ctx, resChunks, reason, err) {
  const host = ctx?.clientToProxyRequest?.headers?.host || '';
  if (!host || !shouldCaptureHost(host)) {
    return;
  }

  setImmediate(() => {
    try {
      if (!ctx.profileContext) {
        ctx.profileContext = resolveProfileContextForCapture(ctx, PROXY_PORT);
      }
      const snapshot = snapshotCaptureContext(ctx, resChunks || []);
      const record = buildCaptureRecordFromSnapshot(snapshot);
      const durationMs = Date.now() - (snapshot.requestStartTime || Date.now());
      const profileContext = snapshot.profileContext;
      const context = extractInteractionContext(
        snapshot.reqHeaders,
        record.request_body,
        {
          duration_ms: durationMs,
          response_status: record.response_status,
          host: snapshot.host,
          capture: record.capture,
          profileContext
        }
      );

      let metadata = {};
      try {
        metadata = JSON.parse(context.metadata);
      } catch {
        metadata = {};
      }
      metadata.capture_kind = 'partial';
      metadata.capture_reason = reason;
      if (err && err.message) {
        metadata.error_message = String(err.message);
      }

      const rowPayload = {
        method: record.method,
        url: record.url,
        request_headers: record.request_headers,
        request_body: record.request_body,
        response_status: record.response_status || 0,
        response_headers: record.response_headers,
        response_body: record.response_body,
        project_key: context.project_key,
        instance_key: context.instance_key,
        metadata: JSON.stringify(metadata)
      };

      let rowId = snapshot.provisionalRowId;
      if (rowId) {
        updateInteraction.run({ ...rowPayload, id: rowId });
      } else {
        const result = insertInteraction(rowPayload);
        rowId = Number(result.lastInsertRowid);
      }

      notifyClients('interaction', {
        id: rowId,
        project_key: context.project_key,
        instance_key: context.instance_key,
        capture_key: snapshot.captureKey,
        partial: true,
        capture_reason: reason
      });

      console.log(`[Proxy] #${rowId} partial ${record.method} ${record.url} (${reason})`);
    } catch (persistErr) {
      console.error('Partial capture error:', persistErr);
    }
  });
}

proxy.onError(function(ctx, err) {
  console.error('Proxy Error:', err);
  if (ctx) {
    persistPartialCapture(ctx, ctx._captureResChunks || [], 'proxy_error', err);
  }
  if (err && err.code === 'EADDRINUSE') {
    process.exit(1);
  }
});

proxy.onConnect(function(req, socket, head, callback) {
  const hostParts = req.url.split(':');
  const host = hostParts[0];
  const port = hostParts[1] || 443;

  if (shouldCaptureHost(host)) {
    return callback(); // continue to MITM
  }

  logBypassTunnelConnect(host, port);

  // Bypass MITM (direct tunnel) for non-captured hosts (e.g. github.com)
  const net = require('net');
  const conn = net.connect(port, host, () => {
    socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    conn.write(head);
    conn.pipe(socket);
    socket.pipe(conn);
  });
  conn.on('error', (err) => {
    console.error('Tunnel Error:', host, err.message);
    socket.end();
  });
  socket.on('error', () => {
    conn.end();
  });
});

proxy.onRequest(function(ctx, callback) {
  const host = ctx.clientToProxyRequest.headers.host || '';
  ctx.requestStartTime = Date.now();
  ctx.captureKey = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  if (!shouldCaptureHost(host)) {
    return callback();
  }

  const reqChunks = [];
  ctx.onRequestData(function(ctx, chunk, callback) {
    reqChunks.push(chunk);
    return callback(null, chunk);
  });

  ctx.onRequestEnd(function(ctx, callback) {
    ctx.reqBody = Buffer.concat(reqChunks);
    return callback();
  });

  const resChunks = [];
  ctx._captureResChunks = resChunks;
  ctx.onResponseData(function(ctx, chunk, callback) {
    resChunks.push(chunk);

    if (!ctx.firstChunkTime) {
      ctx.firstChunkTime = Date.now();
    }
    ctx.totalResponseBytes = (ctx.totalResponseBytes || 0) + chunk.length;

    const resContentType = ctx.serverToProxyResponse?.headers?.['content-type'];
    if (isStreamingContentType(resContentType)) {
      if (!ctx.provisionalRowId && !ctx.provisionalCaptureQueued) {
        ctx.provisionalCaptureQueued = true;
        setImmediate(() => {
          try {
            insertProvisionalStreamingCapture(ctx, host);
          } catch (err) {
            console.error('Provisional capture error:', err);
          }
        });
      }
      setImmediate(() => {
        notifyClients('stream-progress', {
          capture_key: ctx.captureKey,
          url: (ctx.isSSL ? 'https://' : 'http://') + host + (ctx.clientToProxyRequest.url || ''),
          method: ctx.clientToProxyRequest.method,
          bytes: ctx.totalResponseBytes,
          elapsed_ms: Date.now() - ctx.requestStartTime,
          time_to_first_token_ms: ctx.firstChunkTime - ctx.requestStartTime
        });
      });
    }

    return callback(null, chunk);
  });

  ctx.onResponseEnd(function(ctx, callback) {
    callback();

    setImmediate(() => {
      try {
        if (!ctx.profileContext) {
          ctx.profileContext = resolveProfileContextForCapture(ctx, PROXY_PORT);
        }
        const snapshot = snapshotCaptureContext(ctx, resChunks);
        persistCaptureRecord(snapshot);
      } catch (err) {
        console.error('Capture Error:', err);
        persistPartialCapture(ctx, resChunks, 'capture_error', err);
      }
    });
  });

  // Forward immediately; resolve profile context in the background so agent
  // API requests are not blocked on PowerShell/CIM lookups.
  setImmediate(() => {
    if (!ctx.profileContext) {
      ctx.profileContext = resolveProfileContextForCapture(ctx, PROXY_PORT);
    }
  });

  return callback();
});

function startApiServer() {
  const server = app.listen(API_PORT, () => {
    const loaded = loadProfileSessionsFromMarkers();
    if (loaded.length > 0) {
      console.log(`Loaded ${loaded.length} profile session(s) from markers.`);
    }
    console.log(`Agent Story API listening on http://localhost:${API_PORT}`);
  });
  server.on('error', (err) => {
    console.error(`Failed to start API on port ${API_PORT}:`, err.message);
    process.exit(1);
  });
}

startApiServer();

// Bind IPv4 explicitly — Node/http-mitm-proxy may otherwise listen on [::1] only,
// while Cursor's --proxy-server=http://127.0.0.1:8080 connects over IPv4.
proxy.listen({ host: '127.0.0.1', port: PROXY_PORT }, function(err) {
  if (err) {
    console.error(`Failed to start MITM proxy on port ${PROXY_PORT}:`, err.message);
    process.exit(1);
  }
  console.log(`MITM Proxy listening on http://127.0.0.1:${PROXY_PORT}.`);
  console.log('Run Cursor with: --proxy-server="http://127.0.0.1:8080" --ignore-certificate-errors');
});
