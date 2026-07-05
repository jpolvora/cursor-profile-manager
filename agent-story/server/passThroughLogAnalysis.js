const { shouldCaptureHost, categorizeEndpoint, hostMatchesSuffix, CAPTURE_DOMAIN_SUFFIXES } = require('./endpointAnalysis');

const PASS_THROUGH_LOG_HEADER = '# Pass-Through Proxy Traffic Analysis';

function parsePassThroughLogLine(line) {
  const trimmed = String(line || '').trim();
  if (!trimmed) return null;
  try {
    return JSON.parse(trimmed);
  } catch {
    return null;
  }
}

function readPassThroughLogEntries(content) {
  const lines = String(content || '').split(/\r?\n/);
  const entries = [];
  for (const line of lines) {
    const entry = parsePassThroughLogLine(line);
    if (entry) entries.push(entry);
  }
  return entries;
}

function entryHost(entry) {
  if (entry.host) return String(entry.host).toLowerCase();
  if (entry.url) {
    try {
      return new URL(entry.url).hostname.toLowerCase();
    } catch {
      return '';
    }
  }
  return '';
}

function entryPath(entry) {
  if (entry.kind === 'connect') {
    return '/';
  }
  if (entry.path) return entry.path;
  if (entry.url) {
    try {
      const parsed = new URL(entry.url);
      return parsed.pathname || '/';
    } catch {
      return entry.url;
    }
  }
  return '/';
}

function classifyCapturePolicy(host) {
  const h = String(host || '').toLowerCase();
  if (!h) return 'unknown';
  if (shouldCaptureHost(h)) {
    return 'default_mitm';
  }
  if (h === 'localhost' || h === '127.0.0.1' || h.endsWith('.localhost')) {
    return 'expected_bypass';
  }
  return 'not_in_default_mitm';
}

function analyzePassThroughLog(entries) {
  const summary = {
    total: entries.length,
    kinds: {},
    methods: {},
    hosts: {},
    hostPolicies: {},
    categories: {},
    endpoints: [],
    discovery: {
      default_mitm: [],
      not_in_default_mitm: [],
      expected_bypass: []
    }
  };

  const endpointMap = new Map();
  const hostSet = new Set();

  for (const entry of entries) {
    const kind = entry.kind || 'unknown';
    summary.kinds[kind] = (summary.kinds[kind] || 0) + 1;

    const host = entryHost(entry);
    const path = entryPath(entry);
    const method = entry.method || (kind === 'connect' ? 'CONNECT' : 'UNKNOWN');
    summary.methods[method] = (summary.methods[method] || 0) + 1;

    if (host) {
      summary.hosts[host] = (summary.hosts[host] || 0) + 1;
      hostSet.add(host);
      const policy = classifyCapturePolicy(host);
      summary.hostPolicies[policy] = (summary.hostPolicies[policy] || 0) + 1;
    }

    const category = categorizeEndpoint(path, host);
    summary.categories[category] = (summary.categories[category] || 0) + 1;

    const endpointKey = `${method} ${path} @ ${host || 'unknown'}`;
    if (!endpointMap.has(endpointKey)) {
      endpointMap.set(endpointKey, {
        method,
        path,
        host,
        kind,
        count: 0,
        capture_policy: classifyCapturePolicy(host),
        category
      });
    }
    endpointMap.get(endpointKey).count += 1;
  }

  summary.endpoints = Array.from(endpointMap.values()).sort((a, b) => b.count - a.count);

  for (const host of [...hostSet].sort()) {
    const policy = classifyCapturePolicy(host);
    const item = { host, count: summary.hosts[host], policy };
    summary.discovery[policy].push(item);
  }

  for (const key of Object.keys(summary.discovery)) {
    summary.discovery[key].sort((a, b) => b.count - a.count);
  }

  return summary;
}

function formatPassThroughReport(summary) {
  const lines = [];
  lines.push(PASS_THROUGH_LOG_HEADER);
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Total logged events: **${summary.total}**`);
  lines.push('');
  lines.push('## Event kinds');
  lines.push('');
  for (const [kind, count] of Object.entries(summary.kinds).sort((a, b) => b[1] - a[1])) {
    lines.push(`- **${kind}** — ${count}`);
  }
  lines.push('');
  lines.push('## Host capture policy (vs default MITM)');
  lines.push('');
  lines.push('| Policy | Meaning | Host hits |');
  lines.push('|--------|---------|----------:|');
  lines.push(`| default_mitm | Host is in default Agent Story MITM list | ${summary.hostPolicies.default_mitm || 0} |`);
  lines.push(`| not_in_default_mitm | Seen through pass-through but **not** MITM-captured by default | ${summary.hostPolicies.not_in_default_mitm || 0} |`);
  lines.push(`| expected_bypass | localhost / loopback | ${summary.hostPolicies.expected_bypass || 0} |`);
  lines.push('');
  lines.push('## Hosts (by volume)');
  lines.push('');
  for (const [host, count] of Object.entries(summary.hosts).sort((a, b) => b[1] - a[1])) {
    const policy = classifyCapturePolicy(host);
    lines.push(`- \`${host}\` — ${count} (${policy})`);
  }
  lines.push('');
  lines.push('## Discovery: hosts not in default MITM');
  lines.push('');
  if (summary.discovery.not_in_default_mitm.length === 0) {
    lines.push('_None — all non-local hosts were already in the default capture list._');
  } else {
    for (const item of summary.discovery.not_in_default_mitm) {
      lines.push(`- \`${item.host}\` — ${item.count} events`);
    }
  }
  lines.push('');
  lines.push('## Categories');
  lines.push('');
  for (const [cat, count] of Object.entries(summary.categories).sort((a, b) => b[1] - a[1])) {
    lines.push(`- **${cat}** — ${count}`);
  }
  lines.push('');
  lines.push('## Endpoints (by volume)');
  lines.push('');
  lines.push('| Count | Kind | Method | Host | Path | Category | Default MITM? |');
  lines.push('|------:|------|--------|------|------|----------|---------------|');
  for (const ep of summary.endpoints.slice(0, 60)) {
    const mitm = ep.capture_policy === 'default_mitm' ? 'yes' : 'no';
    lines.push(`| ${ep.count} | ${ep.kind} | ${ep.method} | ${ep.host || ''} | \`${ep.path}\` | ${ep.category} | ${mitm} |`);
  }
  lines.push('');
  lines.push('## Default MITM domain suffixes');
  lines.push('');
  for (const suffix of CAPTURE_DOMAIN_SUFFIXES) {
    lines.push(`- \`${suffix}\``);
  }
  lines.push('');
  lines.push('## Notes');
  lines.push('');
  lines.push('- Pass-through proxy logs CONNECT hostnames and plain HTTP metadata without decrypting TLS.');
  lines.push('- Compare **not_in_default_mitm** hosts here against missing chat/agent traffic in the SQLite capture DB.');
  lines.push('- Re-run with `npm run analyze-pass-through-log` after using an **Alternative** proxied profile.');
  return lines.join('\n');
}

module.exports = {
  PASS_THROUGH_LOG_HEADER,
  parsePassThroughLogLine,
  readPassThroughLogEntries,
  classifyCapturePolicy,
  analyzePassThroughLog,
  formatPassThroughReport,
  entryHost,
  entryPath
};
