const { Proxy } = require('http-mitm-proxy');
const express = require('express');
const cors = require('cors');
const zlib = require('zlib');
const { insertInteraction, getInteractions, searchInteractions, getThreads, getInteractionsByThread } = require('./db');

const proxy = new Proxy();
const app = express();
const API_PORT = 3001;

app.use(cors());
app.use(express.json());

// API Endpoint to fetch interactions for the UI
app.get('/api/interactions', (req, res) => {
  const { thread, q, method } = req.query;
  try {
    let rows;
    if (thread) {
      rows = getInteractionsByThread.all(thread, 100);
    } else if (q && q.trim()) {
      const methodFilter = method && method !== 'ALL' ? method : '%';
      rows = searchInteractions.all(q.trim() + '*', methodFilter, 100);
    } else {
      rows = getInteractions.all();
    }
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/threads', (req, res) => {
  try {
    const rows = getThreads.all();
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/interactions/search', (req, res) => {
  const { q = '', method = '', limit = 100 } = req.query;
  const methodFilter = method && method !== 'ALL' ? method : '%';
  const parsedLimit = Math.min(parseInt(limit, 10) || 100, 500);
  try {
    let rows;
    if (q.trim()) {
      rows = searchInteractions.all(q.trim() + '*', methodFilter, parsedLimit);
    } else {
      rows = getInteractions.all();
    }
    res.json(rows);
  } catch (err) {
    // FTS5 syntax errors return 400
    res.status(400).json({ error: err.message });
  }
});

const PROXY_PORT = 8080;

// Configure the MITM proxy
proxy.onError(function(ctx, err) {
  console.error('Proxy Error:', err);
  if (err && err.code === 'EADDRINUSE') {
    process.exit(1);
  }
});

proxy.onRequest(function(ctx, callback) {
  const host = ctx.clientToProxyRequest.headers.host || '';
  
  // For MVP, we intercept traffic to cursor domains (or api.cursor.sh)
  // To avoid noise, we only log if it's cursor related
  if (host.includes('cursor')) {
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
      return callback(null, chunk);
    });

    ctx.onResponseEnd(function(ctx, callback) {
      let resBody = Buffer.concat(resChunks);
      
      // Handle decompression
      const contentEncoding = ctx.serverToProxyResponse.headers['content-encoding'];
      try {
        if (contentEncoding === 'gzip') {
          resBody = zlib.gunzipSync(resBody);
        } else if (contentEncoding === 'deflate') {
          resBody = zlib.inflateSync(resBody);
        } else if (contentEncoding === 'br') {
          resBody = zlib.brotliDecompressSync(resBody);
        }
      } catch (err) {
        console.error('Decompression error:', err);
      }

      try {
        let reqBodyStr = ctx.reqBody ? ctx.reqBody.toString('utf8') : '';
        let resBodyStr = resBody ? resBody.toString('utf8') : '';

        // Only log if it's an API request with some payload to avoid noise
        if (reqBodyStr || resBodyStr) {
          const urlStr = (ctx.isSSL ? 'https://' : 'http://') + host + (ctx.clientToProxyRequest.url || '');
          insertInteraction.run({
            method: ctx.clientToProxyRequest.method,
            url: urlStr,
            request_headers: JSON.stringify(ctx.clientToProxyRequest.headers),
            request_body: reqBodyStr,
            response_status: ctx.serverToProxyResponse.statusCode,
            response_headers: JSON.stringify(ctx.serverToProxyResponse.headers),
            response_body: resBodyStr
          });
          console.log(`[Proxy] Logged interaction: ${ctx.clientToProxyRequest.method} ${urlStr}`);
        }
      } catch (err) {
        console.error('DB Insert Error:', err);
      }

      return callback();
    });
  }

  return callback();
});

function startApiServer() {
  const server = app.listen(API_PORT, () => {
    console.log(`Agent Story API listening on http://localhost:${API_PORT}`);
  });
  server.on('error', (err) => {
    console.error(`Failed to start API on port ${API_PORT}:`, err.message);
    process.exit(1);
  });
}

startApiServer();

proxy.listen({ port: PROXY_PORT }, function(err) {
  if (err) {
    console.error(`Failed to start MITM proxy on port ${PROXY_PORT}:`, err.message);
    process.exit(1);
  }
  console.log(`MITM Proxy listening on port ${PROXY_PORT}.`);
  console.log('Run Cursor with: --proxy-server="http://127.0.0.1:8080" --ignore-certificate-errors');
});
