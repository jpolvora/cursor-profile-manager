export function tryParseJSON(str) {
  try {
    if (!str) return null;
    return JSON.parse(str);
  } catch {
    return null;
  }
}

export function shortInstance(key) {
  if (!key) return null;
  if (key.length <= 16) return key;
  return key.slice(0, 8) + '…' + key.slice(-4);
}

export function decodeBodyPreview(raw) {
  if (!raw) return { label: '(empty)', content: '', isJson: false };
  if (raw.startsWith('base64:')) {
    return {
      label: 'Binary (base64)',
      content: raw,
      isJson: false
    };
  }
  const parsed = tryParseJSON(raw);
  if (parsed) {
    return { label: 'JSON', content: JSON.stringify(parsed, null, 2), isJson: true, parsed };
  }
  return { label: 'Text', content: raw, isJson: false };
}

export function extractMarkdownFromParsed(parsed) {
  if (!parsed) return null;

  if (Array.isArray(parsed.messages)) {
    const textParts = parsed.messages
      .flatMap(m => {
        if (typeof m.content === 'string') return [m.content];
        if (Array.isArray(m.content)) {
          return m.content.filter(p => p.type === 'text').map(p => p.text);
        }
        return [];
      })
      .join('\n\n---\n\n');
    if (textParts.trim()) return textParts;
  }

  if (Array.isArray(parsed.choices)) {
    const textParts = parsed.choices
      .flatMap(c => {
        if (c.message?.content) return [c.message.content];
        if (c.text) return [c.text];
        if (c.delta?.content) return [c.delta.content];
        return [];
      })
      .join('');
    if (textParts.trim()) return textParts;
  }

  return null;
}

export function getInteractionSummary(interaction) {
  const metadata = tryParseJSON(interaction.metadata);
  const baseUrl = interaction.url.split('?')[0];
  const projectLabel = metadata?.profile_manager?.profile_name
    || metadata?.project_label
    || (interaction.project_key ? interaction.project_key.split('/').filter(Boolean).pop() : null);
  const usage = metadata?.usage;

  return {
    metadata,
    baseUrl,
    projectLabel,
    usage,
    isError: interaction.response_status >= 400,
    ttft: metadata?.time_to_first_token_ms,
    duration: metadata?.duration_ms,
    tokens: usage?.total_tokens,
    streaming: metadata?.streaming,
    streamEventCount: metadata?.stream_event_count,
    tokensPerSecond: metadata?.tokens_per_second
  };
}

/** Parse DB/API timestamps stored as UTC (ISO or SQLite "YYYY-MM-DD HH:MM:SS"). */
export function parseUtcTimestamp(timestamp) {
  if (timestamp == null || timestamp === '') return null;
  const normalized = String(timestamp).includes('T')
    ? String(timestamp)
    : String(timestamp).trim().replace(' ', 'T') + 'Z';
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function formatLocaleDateTime(timestamp, options) {
  const date = parseUtcTimestamp(timestamp);
  if (!date) return '—';
  return date.toLocaleString(undefined, options);
}

export function formatGridTime(timestamp) {
  return formatLocaleDateTime(timestamp, {
    year: 'numeric',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
}

export function formatLastSeen(timestamp) {
  const date = parseUtcTimestamp(timestamp);
  if (!date) return '';
  const now = Date.now();
  const diffMs = now - date.getTime();
  if (diffMs < 60_000) return 'just now';
  if (diffMs < 3_600_000) return `${Math.floor(diffMs / 60_000)}m ago`;
  if (diffMs < 86_400_000) {
    return date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  }
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function formatMs(value) {
  if (value == null) return '—';
  return `${value}ms`;
}

/** Newest request activity first; projects with no timestamp sink to the bottom. */
export function sortProjectsByRecentActivity(projects) {
  return [...projects].sort((a, b) => {
    const ta = a.last_timestamp || '';
    const tb = b.last_timestamp || '';
    if (!ta && !tb) return 0;
    if (!ta) return 1;
    if (!tb) return -1;
    return String(tb).localeCompare(String(ta));
  });
}
