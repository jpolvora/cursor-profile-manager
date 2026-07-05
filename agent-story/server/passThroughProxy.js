#!/usr/bin/env node
/**
 * Pass-through HTTP CONNECT proxy for traffic discovery.
 * Logs every CONNECT tunnel and plain HTTP request to NDJSON; does not MITM TLS.
 */
const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PASS_THROUGH_PROXY_PORT || '8081', 10);
const HOST = process.env.PASS_THROUGH_PROXY_HOST || '127.0.0.1';
const LOG_PATH = process.env.PASS_THROUGH_LOG_PATH
  || path.resolve(__dirname, 'pass-through-proxy.log');

const HEADER_ALLOWLIST = [
  'host', 'user-agent', 'content-type', 'content-length', 'accept',
  'x-session-id', 'x-cursor-client-version', 'connect-protocol-version'
];

let logStream = null;

function ensureLogStream() {
  if (logStream) return logStream;
  fs.mkdirSync(path.dirname(LOG_PATH), { recursive: true });
  logStream = fs.createWriteStream(LOG_PATH, { flags: 'a' });
  return logStream;
}

function sanitizeHeaders(headers) {
  const out = {};
  if (!headers) return out;
  for (const key of Object.keys(headers)) {
    const lower = key.toLowerCase();
    if (HEADER_ALLOWLIST.includes(lower)) {
      out[lower] = String(headers[key]).slice(0, 500);
    }
  }
  return out;
}

function writeLog(entry) {
  const line = JSON.stringify({ ts: new Date().toISOString(), ...entry }) + '\n';
  ensureLogStream().write(line);
}

function pipeSockets(client, upstream) {
  client.pipe(upstream);
  upstream.pipe(client);
  client.on('error', () => upstream.destroy());
  upstream.on('error', () => client.destroy());
}

function handleConnect(req, clientSocket, head) {
  const target = req.url || '';
  const colon = target.indexOf(':');
  const host = colon >= 0 ? target.slice(0, colon) : target;
  const port = colon >= 0 ? parseInt(target.slice(colon + 1), 10) || 443 : 443;

  writeLog({
    kind: 'connect',
    method: 'CONNECT',
    host,
    port,
    target
  });

  const upstream = net.connect(port, host, () => {
    clientSocket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
    if (head && head.length) upstream.write(head);
    pipeSockets(clientSocket, upstream);
  });

  upstream.on('error', (err) => {
    writeLog({ kind: 'error', phase: 'connect_upstream', host, port, message: err.message });
    clientSocket.end('HTTP/1.1 502 Bad Gateway\r\n\r\n');
  });

  clientSocket.on('error', () => upstream.destroy());
}

function handleHttpRequest(req, res) {
  let host = req.headers.host || '';
  let port = 80;
  let pathPart = req.url || '/';

  if (req.url && req.url.startsWith('http://')) {
    try {
      const parsed = new URL(req.url);
      host = parsed.hostname;
      port = parsed.port ? parseInt(parsed.port, 10) : 80;
      pathPart = parsed.pathname + parsed.search;
    } catch {
      // keep defaults
    }
  }

  const bodyChunks = [];
  req.on('data', (chunk) => bodyChunks.push(chunk));
  req.on('end', () => {
    const body = Buffer.concat(bodyChunks);
    writeLog({
      kind: 'http',
      method: req.method,
      host,
      port,
      path: pathPart,
      url: req.url,
      request_headers: sanitizeHeaders(req.headers),
      request_body_bytes: body.length
    });

    const headers = { ...req.headers, host };
    const upstreamReq = http.request({
      host,
      port,
      method: req.method,
      path: pathPart,
      headers
    }, (upstreamRes) => {
      writeLog({
        kind: 'http_response',
        method: req.method,
        host,
        path: pathPart,
        status: upstreamRes.statusCode,
        response_headers: sanitizeHeaders(upstreamRes.headers)
      });
      res.writeHead(upstreamRes.statusCode, upstreamRes.headers);
      upstreamRes.pipe(res);
    });

    upstreamReq.on('error', (err) => {
      writeLog({ kind: 'error', phase: 'http_upstream', host, message: err.message });
      if (!res.headersSent) {
        res.writeHead(502);
      }
      res.end();
    });

    if (body.length) upstreamReq.write(body);
    upstreamReq.end();
  });
}

const server = http.createServer(handleHttpRequest);
server.on('connect', handleConnect);

server.listen(PORT, HOST, () => {
  console.log(`Pass-through proxy listening on http://${HOST}:${PORT}`);
  console.log(`Logging to ${LOG_PATH}`);
});

server.on('error', (err) => {
  console.error('Pass-through proxy error:', err.message);
  if (err.code === 'EADDRINUSE') process.exit(1);
});

process.on('SIGINT', () => {
  if (logStream) logStream.end();
  process.exit(0);
});

process.on('SIGTERM', () => {
  if (logStream) logStream.end();
  process.exit(0);
});
