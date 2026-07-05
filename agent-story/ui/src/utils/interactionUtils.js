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

export function formatGridTime(timestamp) {
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

export function formatMs(value) {
  if (value == null) return '—';
  return `${value}ms`;
}
