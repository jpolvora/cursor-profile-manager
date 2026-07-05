#!/usr/bin/env node
const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');
const { analyzeInteractions, formatEndpointReport } = require('./endpointAnalysis');

const dbPath = path.resolve(__dirname, 'agent-story.db');
const outPath = path.resolve(__dirname, '../docs/cursor-endpoints-analysis.md');

if (!fs.existsSync(dbPath)) {
  console.error('No capture database at', dbPath);
  process.exit(1);
}

const db = new Database(dbPath, { readonly: true });
const rows = db.prepare(`
  SELECT method, url, response_status,
    length(request_body) AS req_len,
    length(response_body) AS res_len
  FROM interactions
  ORDER BY id DESC
`).all();

const summary = analyzeInteractions(rows);
const report = formatEndpointReport(summary);

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, report, 'utf8');

console.log(`Wrote ${outPath} (${summary.total} interactions, ${summary.endpoints.length} unique endpoints)`);
