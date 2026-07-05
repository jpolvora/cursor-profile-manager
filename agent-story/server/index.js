const { Proxy } = require('http-mitm-proxy');
const express = require('express');
const cors = require('cors');
const {
  insertInteraction,
  getInteractions,
  searchInteractions,
  getThreads,
  getInteractionsByThread,
  getProjects,
  getInstances,
  getLatestInteractionId
} = require('./db');
const { extractInteractionContext } = require('./metadata');
const { shouldCaptureHost, buildCaptureRecord, isStreamingContentType } = require('./capture');
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

proxy.onError(function(ctx, err) {
  console.error('Proxy Error:', err);
  if (err && err.code === 'EADDRINUSE') {
    process.exit(1);
  }
});

proxy.onRequest(function(ctx, callback) {
  const host = ctx.clientToProxyRequest.headers.host || '';
  ctx.requestStartTime = Date.now();
  ctx.captureKey = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  if (!shouldCaptureHost(host)) {
    return callback();
  }

  ctx.profileContext = resolveProfileContextForCapture(ctx, PROXY_PORT);

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
  ctx.onResponseData(function(ctx, chunk, callback) {
    resChunks.push(chunk);

    if (!ctx.firstChunkTime) {
      ctx.firstChunkTime = Date.now();
    }
    ctx.totalResponseBytes = (ctx.totalResponseBytes || 0) + chunk.length;

    const resContentType = ctx.serverToProxyResponse?.headers?.['content-type'];
    if (isStreamingContentType(resContentType)) {
      notifyClients('stream-progress', {
        capture_key: ctx.captureKey,
        url: (ctx.isSSL ? 'https://' : 'http://') + host + (ctx.clientToProxyRequest.url || ''),
        method: ctx.clientToProxyRequest.method,
        bytes: ctx.totalResponseBytes,
        elapsed_ms: Date.now() - ctx.requestStartTime,
        time_to_first_token_ms: ctx.firstChunkTime - ctx.requestStartTime
      });
    }

    return callback(null, chunk);
  });

  ctx.onResponseEnd(function(ctx, callback) {
    ctx.resBody = Buffer.concat(resChunks);

    try {
      const record = buildCaptureRecord(ctx);
      const durationMs = Date.now() - (ctx.requestStartTime || Date.now());
      const profileContext = ctx.profileContext || resolveProfileContextForCapture(ctx, PROXY_PORT);
      const context = extractInteractionContext(
        ctx.clientToProxyRequest.headers,
        record.request_body,
        {
          duration_ms: durationMs,
          response_status: record.response_status,
          host,
          capture: record.capture,
          profileContext
        }
      );

      const result = insertInteraction.run({
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
      });

      const interactionPayload = {
        id: Number(result.lastInsertRowid),
        project_key: context.project_key,
        instance_key: context.instance_key,
        capture_key: ctx.captureKey,
        streaming: record.capture.response.streaming,
        tokens_per_second: record.capture.response.tokens_per_second
      };

      notifyClients('interaction', interactionPayload);

      const resSummary = record.capture.response;
      console.log(
        `[Proxy] #${result.lastInsertRowid} ${record.method} ${record.url}` +
        (context.project_key ? ` [${context.project_key.split('/').pop()}]` : ' [unassigned]') +
        (resSummary.streaming ? ' [stream]' : '') +
        (resSummary.tokens_per_second ? ` ${resSummary.tokens_per_second} tok/s` : '') +
        ` ${durationMs}ms`
      );
    } catch (err) {
      console.error('Capture Error:', err);
    }

    return callback();
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
