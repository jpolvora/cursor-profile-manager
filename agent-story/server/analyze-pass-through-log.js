#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const {
  readPassThroughLogEntries,
  analyzePassThroughLog,
  formatPassThroughReport
} = require('./passThroughLogAnalysis');

const logPath = process.env.PASS_THROUGH_LOG_PATH
  || path.resolve(__dirname, 'pass-through-proxy.log');
const outPath = path.resolve(__dirname, '../docs/pass-through-endpoints-analysis.md');

if (!fs.existsSync(logPath)) {
  console.error('No pass-through log at', logPath);
  console.error('Start an Alternative proxied profile and use Cursor, then re-run.');
  process.exit(1);
}

const content = fs.readFileSync(logPath, 'utf8');
const entries = readPassThroughLogEntries(content);

if (entries.length === 0) {
  console.error('Pass-through log is empty:', logPath);
  process.exit(1);
}

const summary = analyzePassThroughLog(entries);
const report = formatPassThroughReport(summary);

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, report, 'utf8');

console.log(`Wrote ${outPath} (${summary.total} events, ${Object.keys(summary.hosts).length} unique hosts)`);
const missed = summary.discovery.not_in_default_mitm.length;
if (missed > 0) {
  console.log(`${missed} host(s) seen in pass-through but NOT in default MITM capture list — review Discovery section.`);
}
