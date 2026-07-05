const test = require('node:test');
const assert = require('node:assert/strict');
const {
  parseSseEvents,
  parseConnectFrames,
  analyzePayload,
  bufferToStorage,
  shouldCaptureHost
} = require('./capture');

test('shouldCaptureHost matches cursor and AI domains', () => {
  assert.equal(shouldCaptureHost('api2.cursor.sh'), true);
  assert.equal(shouldCaptureHost('agent.api5.cursor.sh'), true);
  assert.equal(shouldCaptureHost('api.openai.com'), true);
  assert.equal(shouldCaptureHost('example.com'), false);
});

test('parseSseEvents extracts OpenAI-style stream chunks', () => {
  const text = [
    'data: {"choices":[{"delta":{"content":"Hello"}}]}',
    '',
    'data: {"choices":[{"delta":{"content":" world"}}]}',
    '',
    'data: {"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}',
    '',
    'data: [DONE]',
    ''
  ].join('\n');

  const events = parseSseEvents(text);
  assert.equal(events.length, 3);
  assert.equal(events[0].data.choices[0].delta.content, 'Hello');
  assert.equal(events[2].data.usage.completion_tokens, 2);
});

test('parseConnectFrames splits connect envelopes', () => {
  const payload = Buffer.from('assistant chunk');
  const frame = Buffer.alloc(5 + payload.length);
  frame[0] = 0;
  frame.writeUInt32BE(payload.length, 1);
  payload.copy(frame, 5);

  const frames = parseConnectFrames(frame);
  assert.equal(frames.length, 1);
  assert.equal(frames[0].payload.toString('utf8'), 'assistant chunk');
});

test('analyzePayload extracts messages, usage, and tokens per second', () => {
  const body = JSON.stringify({
    messages: [
      { role: 'system', content: 'You are a coding assistant.' },
      { role: 'user', content: 'Explain recursion.' }
    ],
    tools: [{ name: 'read_file' }]
  });

  const request = analyzePayload(Buffer.from(body), 'application/json');
  assert.equal(request.message_count, 2);
  assert.equal(request.tools[0], 'read_file');
  assert.match(request.system_prompt_preview, /coding assistant/);

  const streamText = [
    'data: {"choices":[{"delta":{"content":"Recursion"}}]}',
    '',
    'data: {"choices":[{"delta":{"content":" calls itself."}}]}',
    '',
    'data: {"usage":{"prompt_tokens":20,"completion_tokens":8,"total_tokens":28}}',
    ''
  ].join('\n');

  const response = analyzePayload(
    Buffer.from(streamText),
    'text/event-stream',
    { duration_ms: 2000, first_chunk_ms: 200, generation_ms: 1800 }
  );

  assert.equal(response.streaming, true);
  assert.equal(response.stream_event_count, 3);
  assert.match(response.assistant_text_preview, /Recursion calls itself/);
  assert.equal(response.usage.completion_tokens, 8);
  assert.ok(response.tokens_per_second > 0);
});

test('bufferToStorage preserves binary as base64', () => {
  const binary = Buffer.from([0x00, 0x01, 0x02, 0xff, 0xfe, 0x00, 0x01, 0x02]);
  const stored = bufferToStorage(binary);
  assert.equal(stored.encoding, 'base64');
  assert.match(stored.text, /^base64:/);
});
