const PRINTABLE_SAMPLE = 8192;
const PRINTABLE_THRESHOLD = 0.82;

function isValidUtf8(buffer) {
  if (!buffer || buffer.length === 0) return true;
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(buffer);
    return true;
  } catch {
    return false;
  }
}

function isMostlyText(buffer) {
  if (!buffer || buffer.length === 0) return true;
  if (!isValidUtf8(buffer)) return false;
  const sampleLen = Math.min(buffer.length, PRINTABLE_SAMPLE);
  let printable = 0;
  for (let i = 0; i < sampleLen; i++) {
    const b = buffer[i];
    if (b === 9 || b === 10 || b === 13 || (b >= 32 && b <= 126)) printable++;
    else if (b >= 128) printable++;
  }
  return printable / sampleLen >= PRINTABLE_THRESHOLD;
}

function bufferToStorage(buffer) {
  if (!buffer || buffer.length === 0) {
    return { text: '', encoding: 'empty', byte_length: 0 };
  }
  if (isMostlyText(buffer)) {
    return { text: buffer.toString('utf8'), encoding: 'utf8', byte_length: buffer.length };
  }
  return {
    text: `base64:${buffer.toString('base64')}`,
    encoding: 'base64',
    byte_length: buffer.length
  };
}

function storageToBuffer(text, encoding) {
  if (!text) return Buffer.alloc(0);
  if (encoding === 'base64' || String(text).startsWith('base64:')) {
    return Buffer.from(String(text).replace(/^base64:/, ''), 'base64');
  }
  return Buffer.from(String(text), 'utf8');
}

function normalizeContentType(contentType) {
  if (!contentType) return '';
  return String(Array.isArray(contentType) ? contentType[0] : contentType).split(';')[0].trim().toLowerCase();
}

function isStreamingContentType(contentType) {
  const ct = normalizeContentType(contentType);
  return ct.includes('text/event-stream')
    || ct.includes('application/stream')
    || ct.includes('application/connect')
    || ct.includes('application/grpc')
    || ct.includes('application/x-ndjson')
    || ct.includes('application/jsonl');
}

function parseConnectFrames(buffer) {
  const frames = [];
  let offset = 0;
  while (offset + 5 <= buffer.length) {
    const flags = buffer[offset];
    const length = buffer.readUInt32BE(offset + 1);
    offset += 5;
    if (length < 0 || offset + length > buffer.length) break;
    frames.push({
      flags,
      compressed: (flags & 0x1) === 1,
      endStream: (flags & 0x2) === 2,
      payload: buffer.subarray(offset, offset + length)
    });
    offset += length;
  }
  return frames;
}

function decompressConnectFramePayload(payload, compressed) {
  if (!payload || payload.length === 0) return payload;
  if (!compressed) return payload;
  try {
    return zlibGunzip(payload);
  } catch {
    try {
      return zlibInflate(payload);
    } catch {
      return payload;
    }
  }
}

function decodeConnectBodyToText(buffer) {
  const frames = parseConnectFrames(buffer);
  if (!frames.length) return null;

  const parts = [];
  for (const frame of frames) {
    const payload = decompressConnectFramePayload(frame.payload, frame.compressed);
    if (!payload || payload.length === 0) continue;

    const asText = payload.toString('utf8');
    const parsedJson = tryParseJson(asText);
    if (parsedJson) {
      parts.push(JSON.stringify(parsedJson));
      continue;
    }

    const strings = extractPrintableRuns(payload, 4);
    if (strings.length) {
      parts.push(...strings);
      continue;
    }

    if (isMostlyText(payload)) {
      parts.push(asText.trim());
    }
  }

  if (!parts.length) return null;
  return parts.join('\n');
}

function extractPrintableRuns(buffer, minLength = 12) {
  if (!buffer || buffer.length === 0) return [];
  const runs = [];
  let start = -1;
  for (let i = 0; i <= buffer.length; i++) {
    const b = i < buffer.length ? buffer[i] : -1;
    const printable = b === 9 || b === 10 || b === 13 || (b >= 32 && b <= 126);
    if (printable) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      if (i - start >= minLength) {
        const run = buffer.toString('ascii', start, i).trim();
        if (run) runs.push(run);
      }
      start = -1;
    }
  }
  return runs;
}

function parseSseEvents(text) {
  const events = [];
  if (!text) return events;

  const blocks = text.split(/\r?\n\r?\n/);
  for (const block of blocks) {
    const lines = block.split(/\r?\n/);
    let eventName = 'message';
    const dataLines = [];
    for (const line of lines) {
      if (line.startsWith('event:')) eventName = line.slice(6).trim();
      else if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());
    }
    if (dataLines.length === 0) continue;
    const payload = dataLines.join('\n');
    if (!payload || payload === '[DONE]') continue;
    let parsed = payload;
    try {
      parsed = JSON.parse(payload);
    } catch {
      // keep raw string
    }
    events.push({ event: eventName, data: parsed, raw: payload });
  }
  return events;
}

function parseNdjson(text) {
  const rows = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      rows.push(JSON.parse(trimmed));
    } catch {
      rows.push(trimmed);
    }
  }
  return rows;
}

function tryParseJson(text) {
  if (!text || !text.trim()) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function collectStringsDeep(value, out, depth = 0) {
  if (depth > 8 || out.length > 200) return;
  if (typeof value === 'string') {
    if (value.trim().length >= 8) out.push(value);
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectStringsDeep(item, out, depth + 1);
    return;
  }
  if (value && typeof value === 'object') {
    for (const v of Object.values(value)) collectStringsDeep(v, out, depth + 1);
  }
}

function extractDeltaText(event) {
  if (!event || typeof event !== 'object') return '';
  const parts = [];
  if (typeof event.text === 'string') parts.push(event.text);
  if (typeof event.content === 'string') parts.push(event.content);
  if (Array.isArray(event.choices)) {
    for (const choice of event.choices) {
      if (choice.delta?.content) parts.push(choice.delta.content);
      if (choice.message?.content) parts.push(choice.message.content);
      if (choice.text) parts.push(choice.text);
    }
  }
  if (event.result?.value) parts.push(String(event.result.value));
  if (event.message?.content) {
    if (typeof event.message.content === 'string') parts.push(event.message.content);
    else if (Array.isArray(event.message.content)) {
      for (const part of event.message.content) {
        if (part?.text) parts.push(part.text);
      }
    }
  }
  return parts.join('');
}

function extractMessagesFromObject(obj) {
  const messages = [];
  if (!obj || typeof obj !== 'object') return messages;

  if (Array.isArray(obj.messages)) {
    for (const msg of obj.messages) {
      if (!msg || typeof msg !== 'object') continue;
      messages.push({
        role: msg.role || msg.author || 'unknown',
        content: flattenMessageContent(msg.content)
      });
    }
  }

  if (Array.isArray(obj.conversation)) {
    for (const msg of obj.conversation) {
      messages.push({
        role: msg.role || msg.type || 'unknown',
        content: flattenMessageContent(msg.content ?? msg.text)
      });
    }
  }

  return messages;
}

function flattenMessageContent(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map(part => {
        if (typeof part === 'string') return part;
        if (part?.type === 'text' && part.text) return part.text;
        if (part?.text) return part.text;
        if (part?.type === 'tool_use') return `[tool:${part.name || 'call'}]`;
        if (part?.type === 'tool_result') return `[tool_result] ${part.content || ''}`;
        return '';
      })
      .filter(Boolean)
      .join('\n');
  }
  if (content && typeof content === 'object') {
    return JSON.stringify(content);
  }
  return content == null ? '' : String(content);
}

function extractToolsFromObject(obj) {
  const tools = [];
  if (!obj || typeof obj !== 'object') return tools;
  const candidates = [obj.tools, obj.functions, obj.functionDefinitions, obj.availableTools];
  for (const list of candidates) {
    if (!Array.isArray(list)) continue;
    for (const tool of list) {
      const name = tool?.name || tool?.function?.name;
      if (name) tools.push(name);
    }
  }
  return tools;
}

function extractUsageFromObject(obj) {
  if (!obj || typeof obj !== 'object') return null;
  if (obj.usage && typeof obj.usage === 'object') return normalizeUsage(obj.usage);
  if (obj.tokenUsage && typeof obj.tokenUsage === 'object') return normalizeUsage(obj.tokenUsage);
  if (obj.metadata?.usage) return normalizeUsage(obj.metadata.usage);
  return null;
}

function normalizeUsage(usage) {
  const prompt = usage.prompt_tokens ?? usage.input_tokens ?? usage.promptTokens ?? null;
  const completion = usage.completion_tokens ?? usage.output_tokens ?? usage.completionTokens ?? null;
  const total = usage.total_tokens ?? usage.totalTokens ?? (
    prompt != null && completion != null ? prompt + completion : null
  );
  if (prompt == null && completion == null && total == null) return null;
  return { prompt_tokens: prompt, completion_tokens: completion, total_tokens: total };
}

function estimateTokens(text) {
  if (!text) return 0;
  return Math.max(1, Math.ceil(text.length / 4));
}

function extractUsageFromEvents(events) {
  for (let i = events.length - 1; i >= 0; i--) {
    const item = events[i];
    const data = item && item.data !== undefined ? item.data : item;
    const usage = extractUsageFromObject(data);
    if (usage) return usage;
  }
  return null;
}

function buildAssistantText(events, parsedJson) {
  const chunks = [];
  if (parsedJson) {
    if (Array.isArray(parsedJson.choices)) {
      for (const choice of parsedJson.choices) {
        if (choice.message?.content) chunks.push(flattenMessageContent(choice.message.content));
        if (choice.text) chunks.push(choice.text);
      }
    }
    const msgs = extractMessagesFromObject(parsedJson).filter(m => m.role === 'assistant');
    for (const msg of msgs) chunks.push(msg.content);
  }
  for (const event of events) {
    const data = event && event.data !== undefined ? event.data : event;
    const delta = extractDeltaText(data);
    if (delta) chunks.push(delta);
  }
  return chunks.join('');
}

function buildPromptText(messages) {
  return messages
    .map(m => `[${m.role}]\n${m.content}`)
    .filter(Boolean)
    .join('\n\n---\n\n');
}

function analyzePayload(buffer, contentType, timing = {}) {
  const ct = normalizeContentType(contentType);
  const storage = bufferToStorage(buffer);
  const rawBuffer = buffer && buffer.length ? buffer : storageToBuffer(storage.text, storage.encoding);
  const parsedJson = storage.encoding === 'utf8' ? tryParseJson(storage.text) : null;
  const sseEvents = storage.encoding === 'utf8' && (ct.includes('event-stream') || storage.text.includes('data:'))
    ? parseSseEvents(storage.text)
    : [];
  const ndjsonRows = storage.encoding === 'utf8' && (ct.includes('ndjson') || ct.includes('jsonl'))
    ? parseNdjson(storage.text)
    : [];
  const connectFrames = (!parsedJson && rawBuffer.length >= 5) ? parseConnectFrames(rawBuffer) : [];
  const connectStrings = connectFrames.flatMap(frame => {
    const payload = decompressConnectFramePayload(frame.payload, frame.compressed);
    return extractPrintableRuns(payload, 8);
  });

  const streamEvents = sseEvents.length
    ? sseEvents
    : ndjsonRows.length
      ? ndjsonRows.map(row => ({ event: 'message', data: row }))
      : connectFrames.map((frame, index) => {
        const payload = decompressConnectFramePayload(frame.payload, frame.compressed);
        return {
          event: 'connect-frame',
          data: { index, flags: frame.flags, endStream: frame.endStream, strings: extractPrintableRuns(payload, 8) }
        };
      });

  const messages = extractMessagesFromObject(parsedJson);
  const tools = extractToolsFromObject(parsedJson);
  const usage = extractUsageFromObject(parsedJson) || extractUsageFromEvents(streamEvents);
  const assistantText = buildAssistantText(streamEvents, parsedJson);
  let promptText = buildPromptText(messages);
  if (!promptText && connectStrings.length) {
    promptText = connectStrings.join('\n');
  }

  let systemPrompt = messages.find(m => m.role === 'system')?.content || null;
  if (!systemPrompt && parsedJson?.system) {
    systemPrompt = flattenMessageContent(parsedJson.system);
  }

  const completionTokens = usage?.completion_tokens ?? estimateTokens(assistantText);
  const promptTokens = usage?.prompt_tokens ?? estimateTokens(promptText);
  const generationMs = timing.generation_ms ?? (
    timing.first_chunk_ms != null && timing.duration_ms != null
      ? Math.max(0, timing.duration_ms - timing.first_chunk_ms)
      : timing.duration_ms
  );
  const tokensPerSecond = completionTokens && generationMs > 0
    ? Math.round((completionTokens / generationMs) * 1000 * 10) / 10
    : null;

  return {
    encoding: storage.encoding,
    byte_length: storage.byte_length,
    content_type: ct || null,
    streaming: isStreamingContentType(contentType) || sseEvents.length > 1 || connectFrames.length > 1,
    stream_event_count: streamEvents.length,
    connect_frame_count: connectFrames.length,
    messages,
    message_count: messages.length,
    tools,
    system_prompt_preview: systemPrompt ? truncate(systemPrompt, 500) : null,
    prompt_preview: promptText ? truncate(promptText, 1200) : null,
    assistant_text_preview: assistantText ? truncate(assistantText, 2000) : null,
    extracted_strings: connectStrings.slice(0, 20),
    usage: usage || {
      prompt_tokens: promptTokens || null,
      completion_tokens: completionTokens || null,
      total_tokens: (promptTokens || 0) + (completionTokens || 0) || null,
      estimated: !usage
    },
    time_to_first_token_ms: timing.first_chunk_ms ?? null,
    generation_ms: generationMs ?? null,
    tokens_per_second: tokensPerSecond,
    stream_bytes: timing.stream_bytes ?? storage.byte_length
  };
}

function truncate(text, max) {
  if (!text || text.length <= max) return text;
  return text.slice(0, max) + '…';
}

function decompressBody(buffer, contentEncoding) {
  if (!buffer || buffer.length === 0) return buffer;
  const encoding = String(contentEncoding || '').toLowerCase();
  try {
    if (encoding.includes('gzip')) return zlibGunzip(buffer);
    if (encoding.includes('deflate')) return zlibInflate(buffer);
    if (encoding.includes('br')) return zlibBrotli(buffer);
  } catch {
    // keep raw buffer
  }
  return buffer;
}

function isConnectContentType(contentType) {
  const ct = normalizeContentType(contentType);
  return ct.includes('connect') || ct.includes('grpc');
}

function looksLikeConnectEnvelope(buffer) {
  if (!buffer || buffer.length < 5) return false;
  const length = buffer.readUInt32BE(1);
  return length > 0 && 5 + length <= buffer.length;
}

function bufferToPlainText(buffer, contentType, contentEncoding) {
  if (!buffer || buffer.length === 0) return '';

  const raw = decompressBody(buffer, contentEncoding);
  const asText = raw.toString('utf8');

  if (tryParseJson(asText)) {
    return asText;
  }

  if (isConnectContentType(contentType) || looksLikeConnectEnvelope(raw)) {
    const connectText = decodeConnectBodyToText(raw);
    if (connectText) return connectText;
  }

  const strings = extractPrintableRuns(raw, 4);
  if (strings.length) return strings.join('\n');

  if (isMostlyText(raw)) {
    return asText;
  }

  return bufferToStorage(raw).text;
}

function zlibGunzip(buffer) {
  const zlib = require('zlib');
  return zlib.gunzipSync(buffer);
}

function zlibInflate(buffer) {
  const zlib = require('zlib');
  return zlib.inflateSync(buffer);
}

function zlibBrotli(buffer) {
  const zlib = require('zlib');
  return zlib.brotliDecompressSync(buffer);
}

const { shouldCaptureHost } = require('./endpointAnalysis');

function buildCaptureRecord(ctx) {
  const host = ctx.clientToProxyRequest.headers.host || '';
  const urlStr = (ctx.isSSL ? 'https://' : 'http://') + host + (ctx.clientToProxyRequest.url || '');
  const reqHeaders = ctx.clientToProxyRequest.headers;
  const resHeaders = ctx.serverToProxyResponse?.headers || {};
  const durationMs = Date.now() - (ctx.requestStartTime || Date.now());
  const firstChunkMs = ctx.firstChunkTime ? ctx.firstChunkTime - ctx.requestStartTime : null;
  const generationMs = ctx.firstChunkTime ? Date.now() - ctx.firstChunkTime : null;

  const reqRaw = decompressBody(ctx.reqBody || Buffer.alloc(0), reqHeaders['content-encoding']);
  const resRaw = decompressBody(ctx.resBody || Buffer.alloc(0), resHeaders['content-encoding']);

  const requestAnalysis = analyzePayload(reqRaw, reqHeaders['content-type'], {
    duration_ms: durationMs,
    stream_bytes: reqRaw.length
  });
  const responseAnalysis = analyzePayload(resRaw, resHeaders['content-type'], {
    duration_ms: durationMs,
    first_chunk_ms: firstChunkMs,
    generation_ms: generationMs,
    stream_bytes: ctx.totalResponseBytes || resRaw.length
  });

  return {
    method: ctx.clientToProxyRequest.method,
    url: urlStr,
    request_headers: JSON.stringify(reqHeaders),
    request_body: bufferToPlainText(reqRaw, reqHeaders['content-type']),
    response_status: ctx.serverToProxyResponse?.statusCode || 0,
    response_headers: JSON.stringify(resHeaders),
    response_body: bufferToPlainText(resRaw, resHeaders['content-type']),
    capture: {
      request: requestAnalysis,
      response: responseAnalysis
    }
  };
}

module.exports = {
  shouldCaptureHost,
  bufferToStorage,
  bufferToPlainText,
  storageToBuffer,
  parseConnectFrames,
  parseSseEvents,
  analyzePayload,
  buildCaptureRecord,
  isStreamingContentType,
  decompressBody,
  decompressConnectFramePayload,
  decodeConnectBodyToText
};
