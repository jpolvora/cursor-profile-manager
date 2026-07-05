const CAPTURE_DOMAIN_SUFFIXES = [
  '.cursor.sh',
  '.cursor.com',
  'cursor.com',
  'cursor.sh',
  '.cursorapi.com',
  'cursorapi.com'
];

const AI_PROVIDER_SUFFIXES = [
  '.openai.com',
  'openai.com',
  '.anthropic.com',
  'anthropic.com',
  '.claude.ai',
  'claude.ai',
  '.googleapis.com',
  'generativelanguage.googleapis.com',
  '.x.ai',
  'x.ai',
  '.mistral.ai',
  'mistral.ai',
  '.groq.com',
  'groq.com',
  '.fireworks.ai',
  'fireworks.ai',
  '.together.xyz',
  'together.xyz'
];

function hostMatchesSuffix(host, suffix) {
  const h = String(host || '').toLowerCase();
  const s = String(suffix || '').toLowerCase();
  if (!h || !s) return false;
  if (s.startsWith('.')) {
    return h.endsWith(s) || h === s.slice(1);
  }
  return h === s || h.endsWith('.' + s);
}

function shouldCaptureHost(host) {
  const h = String(host || '').toLowerCase();
  if (!h) return false;

  if (CAPTURE_DOMAIN_SUFFIXES.some(suffix => hostMatchesSuffix(h, suffix))) {
    return true;
  }

  if (AI_PROVIDER_SUFFIXES.some(suffix => hostMatchesSuffix(h, suffix))) {
    return true;
  }

  // Legacy subdomain patterns (agent.api5.cursor.sh, api2.cursor.sh, etc.)
  if (h.includes('.cursor.') || h.startsWith('cursor.')) {
    return true;
  }

  return false;
}

function parseInteractionUrl(url) {
  try {
    const parsed = new URL(url);
    return {
      host: parsed.hostname,
      path: parsed.pathname || '/',
      search: parsed.search || ''
    };
  } catch {
    return { host: '', path: url || '', search: '' };
  }
}

function categorizeEndpoint(path, host) {
  const p = String(path || '').toLowerCase();
  const h = String(host || '').toLowerCase();

  if (p.includes('/chat') || p.includes('streamunifiedchat') || p.includes('/v1/chat')) {
    return 'chat';
  }
  if (p.includes('bidiservice') || p.includes('bidiappend')) {
    return 'agent-stream';
  }
  if (p.includes('agentservice') || (p.includes('agent') && p.includes('aiserver'))) {
    return 'agent';
  }
  if (p.includes('composer')) {
    return 'composer';
  }
  if (p.includes('task') && (p.includes('aiserver') || h.includes('agent.api'))) {
    return 'subagent';
  }
  if (
    p.includes('/rgstr')
    || p.includes('telemetry')
    || p.includes('analytics')
    || p.includes('metrics')
    || p.includes('/envelope/')
    || p.includes('onlinemetrics')
    || p.includes('uploadissuetrace')
    || p.includes('reportagentsnapshot')
  ) {
    return 'telemetry';
  }
  if (p.includes('/auth') || p.includes('stripe_profile') || p.includes('token')) {
    return 'auth';
  }
  if (p.includes('extension') || h.includes('marketplace') || p.includes('gallery')) {
    return 'extensions';
  }
  if (p.includes('/updates/') || p.includes('update/')) {
    return 'updates';
  }
  if (p.includes('usage') || p.includes('dashboard') || p.includes('billing')) {
    return 'billing';
  }
  if (p.includes('aiserver.') || p.includes('connect')) {
    return 'aiserver-rpc';
  }
  if (p.includes('model') || p.includes('embedding')) {
    return 'models';
  }
  return 'other';
}

function analyzeInteractions(rows) {
  const summary = {
    total: rows.length,
    methods: {},
    statuses: {},
    hosts: {},
    categories: {},
    endpoints: []
  };

  const endpointMap = new Map();

  for (const row of rows) {
    const method = row.method || 'UNKNOWN';
    const status = row.response_status != null ? String(row.response_status) : '0';
    const { host, path } = parseInteractionUrl(row.url || '');
    const category = categorizeEndpoint(path, host);
    const endpointKey = `${method} ${path}`;

    summary.methods[method] = (summary.methods[method] || 0) + 1;
    summary.statuses[status] = (summary.statuses[status] || 0) + 1;
    summary.hosts[host] = (summary.hosts[host] || 0) + 1;
    summary.categories[category] = (summary.categories[category] || 0) + 1;

    if (!endpointMap.has(endpointKey)) {
      endpointMap.set(endpointKey, {
        method,
        path,
        count: 0,
        hosts: {},
        statuses: {},
        category,
        sample_url: row.url,
        avg_request_bytes: 0,
        avg_response_bytes: 0
      });
    }

    const entry = endpointMap.get(endpointKey);
    entry.count += 1;
    entry.hosts[host] = (entry.hosts[host] || 0) + 1;
    entry.statuses[status] = (entry.statuses[status] || 0) + 1;
    entry.avg_request_bytes += Number(row.request_body?.length || row.req_len || 0);
    entry.avg_response_bytes += Number(row.response_body?.length || row.res_len || 0);
  }

  summary.endpoints = Array.from(endpointMap.values())
    .map(entry => ({
      ...entry,
      hosts: Object.keys(entry.hosts).sort(),
      avg_request_bytes: entry.count ? Math.round(entry.avg_request_bytes / entry.count) : 0,
      avg_response_bytes: entry.count ? Math.round(entry.avg_response_bytes / entry.count) : 0
    }))
    .sort((a, b) => b.count - a.count);

  return summary;
}

function formatEndpointReport(summary) {
  const lines = [];
  lines.push('# Cursor / Agent Story Endpoint Analysis');
  lines.push('');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push(`Total captured interactions: **${summary.total}**`);
  lines.push('');
  lines.push('## Hosts');
  lines.push('');
  for (const [host, count] of Object.entries(summary.hosts).sort((a, b) => b[1] - a[1])) {
    lines.push(`- \`${host}\` — ${count} requests`);
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
  lines.push('| Count | Method | Path | Category | Hosts | Status codes |');
  lines.push('|------:|--------|------|----------|-------|--------------|');
  for (const ep of summary.endpoints.slice(0, 40)) {
    const statuses = Object.entries(ep.statuses).map(([k, v]) => `${k}:${v}`).join(', ');
    lines.push(`| ${ep.count} | ${ep.method} | \`${ep.path}\` | ${ep.category} | ${ep.hosts.join(', ')} | ${statuses} |`);
  }
  lines.push('');
  lines.push('## Capture policy');
  lines.push('');
  lines.push('- MITM + full body capture: Cursor domains (`*.cursor.sh`, `*.cursor.com`, `*.cursorapi.com`) and configured AI provider domains.');
  lines.push('- Direct tunnel (no body capture): hosts in Chromium `--proxy-bypass-list` / Node `NO_PROXY` (localhost, Git hosts).');
  lines.push('- All captured traffic is forwarded immediately; persistence runs asynchronously after response end.');
  return lines.join('\n');
}

module.exports = {
  CAPTURE_DOMAIN_SUFFIXES,
  AI_PROVIDER_SUFFIXES,
  shouldCaptureHost,
  hostMatchesSuffix,
  parseInteractionUrl,
  categorizeEndpoint,
  analyzeInteractions,
  formatEndpointReport
};
