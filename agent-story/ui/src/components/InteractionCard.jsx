import { useState } from 'react';
import {
  Server,
  Clock,
  ChevronDown,
  ChevronRight,
  FolderKanban,
  Monitor,
  Timer,
  Zap,
  Radio,
  MessageSquare
} from 'lucide-react';
import { Light as SyntaxHighlighter } from 'react-syntax-highlighter';
import json from 'react-syntax-highlighter/dist/esm/languages/hljs/json';
import { atomOneDark } from 'react-syntax-highlighter/dist/esm/styles/hljs';
import MarkdownRenderer from './MarkdownRenderer';

SyntaxHighlighter.registerLanguage('json', json);

function tryParseJSON(str) {
  try {
    if (!str) return null;
    return JSON.parse(str);
  } catch {
    return null;
  }
}

function shortInstance(key) {
  if (!key) return null;
  if (key.length <= 16) return key;
  return key.slice(0, 8) + '…' + key.slice(-4);
}

function decodeBodyPreview(raw) {
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

function extractMarkdownFromParsed(parsed) {
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

function BodySection({ title, raw, previewText }) {
  const [open, setOpen] = useState(false);
  const decoded = decodeBodyPreview(raw);
  const markdownContent = previewText || extractMarkdownFromParsed(decoded.parsed);

  return (
    <div className="body-section">
      <button className="section-toggle" onClick={() => setOpen(o => !o)}>
        {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        <span className="section-title">{title}</span>
      </button>
      {open && (
        <div className="section-content">
          {markdownContent && (
            <div style={{ marginBottom: '1rem' }}>
              <div className="section-label">Extracted Content</div>
              <MarkdownRenderer content={markdownContent} />
            </div>
          )}
          <div className="section-label">Raw {decoded.label}</div>
          {decoded.isJson ? (
            <SyntaxHighlighter
              language="json"
              style={atomOneDark}
              customStyle={{ borderRadius: '8px', fontSize: '0.82rem', margin: 0 }}
            >
              {decoded.content}
            </SyntaxHighlighter>
          ) : (
            <pre className="raw-text">{decoded.content || '(empty)'}</pre>
          )}
        </div>
      )}
    </div>
  );
}

function MetadataSection({ metadata }) {
  const [open, setOpen] = useState(false);
  const parsed = tryParseJSON(metadata);
  if (!parsed) return null;

  return (
    <div className="body-section">
      <button className="section-toggle" onClick={() => setOpen(o => !o)}>
        {open ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        <span className="section-title">Capture Metadata</span>
      </button>
      {open && (
        <div className="section-content">
          <SyntaxHighlighter
            language="json"
            style={atomOneDark}
            customStyle={{ borderRadius: '8px', fontSize: '0.82rem', margin: 0 }}
          >
            {JSON.stringify(parsed, null, 2)}
          </SyntaxHighlighter>
        </div>
      )}
    </div>
  );
}

export default function InteractionCard({ interaction }) {
  const isError = interaction.response_status >= 400;
  const baseUrl = interaction.url.split('?')[0];
  const metadata = tryParseJSON(interaction.metadata);
  const projectLabel = metadata?.project_label
    || (interaction.project_key ? interaction.project_key.split('/').filter(Boolean).pop() : null);
  const usage = metadata?.usage;
  const hasBadges = projectLabel || interaction.instance_key || metadata?.duration_ms != null
    || metadata?.streaming || metadata?.tokens_per_second || usage?.total_tokens;

  return (
    <div className="interaction-card">
      <div className="card-header">
        <div className="card-header-left">
          <Server size={16} color="var(--primary-accent)" />
          <span className={`method-badge method-${interaction.method.toLowerCase()}`}>
            {interaction.method}
          </span>
          <span className="url" title={interaction.url}>{baseUrl}</span>
        </div>
        <div className="card-header-right">
          <span className="timestamp">
            <Clock size={13} />
            {new Date(interaction.timestamp).toLocaleTimeString()}
          </span>
          <span className={`status-badge ${isError ? 'status-err' : 'status-ok'}`}>
            {interaction.response_status}
          </span>
        </div>
      </div>

      {hasBadges && (
        <div className="metadata-badges">
          {projectLabel && (
            <span className="meta-badge" title={interaction.project_key}>
              <FolderKanban size={12} />
              {projectLabel}
            </span>
          )}
          {interaction.instance_key && (
            <span className="meta-badge" title={interaction.instance_key}>
              <Monitor size={12} />
              {shortInstance(interaction.instance_key)}
            </span>
          )}
          {metadata?.streaming && (
            <span className="meta-badge meta-stream">
              <Radio size={12} />
              stream ×{metadata.stream_event_count || '?'}
            </span>
          )}
          {metadata?.time_to_first_token_ms != null && (
            <span className="meta-badge">
              <Timer size={12} />
              TTFT {metadata.time_to_first_token_ms}ms
            </span>
          )}
          {metadata?.duration_ms != null && (
            <span className="meta-badge">
              <Timer size={12} />
              {metadata.duration_ms}ms
            </span>
          )}
          {metadata?.tokens_per_second != null && (
            <span className="meta-badge meta-accent">
              <Zap size={12} />
              {metadata.tokens_per_second} tok/s
            </span>
          )}
          {usage?.total_tokens != null && (
            <span className="meta-badge" title={`prompt ${usage.prompt_tokens ?? '?'} · completion ${usage.completion_tokens ?? '?'}`}>
              <MessageSquare size={12} />
              {usage.total_tokens} tokens{usage.estimated ? ' est.' : ''}
            </span>
          )}
        </div>
      )}

      {metadata?.system_prompt_preview && (
        <BodySection title="System / Injected Prompt" raw={metadata.system_prompt_preview} previewText={metadata.system_prompt_preview} />
      )}

      {metadata?.prompt_preview && (
        <BodySection title="Request Messages" raw={metadata.prompt_preview} previewText={metadata.prompt_preview} />
      )}

      {metadata?.assistant_text_preview && (
        <BodySection title="Assistant Response" raw={metadata.assistant_text_preview} previewText={metadata.assistant_text_preview} />
      )}

      <MetadataSection metadata={interaction.metadata} />
      <BodySection title="Request Payload" raw={interaction.request_body} previewText={metadata?.prompt_preview} />
      <BodySection title="Response Payload" raw={interaction.response_body} previewText={metadata?.assistant_text_preview} />
    </div>
  );
}
