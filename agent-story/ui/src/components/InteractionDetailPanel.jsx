import { useState } from 'react';
import {
  ChevronDown,
  ChevronRight,
  ChevronRight as ExpandIcon,
  Clock,
  FolderKanban,
  MessageSquare,
  Monitor,
  Radio,
  Server,
  Timer,
  X,
  Zap
} from 'lucide-react';
import { Light as SyntaxHighlighter } from 'react-syntax-highlighter';
import json from 'react-syntax-highlighter/dist/esm/languages/hljs/json';
import { atomOneDark } from 'react-syntax-highlighter/dist/esm/styles/hljs';
import MarkdownRenderer from './MarkdownRenderer';
import {
  decodeBodyPreview,
  extractMarkdownFromParsed,
  formatLocaleDateTime,
  getInteractionSummary,
  shortInstance,
  tryParseJSON
} from '../utils/interactionUtils';

SyntaxHighlighter.registerLanguage('json', json);

function BodySection({ title, raw, previewText }) {
  const [open, setOpen] = useState(false);
  const decoded = decodeBodyPreview(raw);
  const markdownContent = previewText || extractMarkdownFromParsed(decoded.parsed);

  return (
    <div className="body-section">
      <button type="button" className="section-toggle" onClick={() => setOpen(o => !o)}>
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
      <button type="button" className="section-toggle" onClick={() => setOpen(o => !o)}>
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

function DetailContent({ interaction }) {
  const summary = getInteractionSummary(interaction);
  const { metadata, projectLabel, usage } = summary;
  const hasBadges = projectLabel || interaction.instance_key || metadata?.duration_ms != null
    || metadata?.streaming || metadata?.tokens_per_second || usage?.total_tokens;

  return (
    <div className="detail-content">
      <div className="detail-header">
        <div className="detail-header-top">
          <Server size={16} color="var(--primary-accent)" />
          <span className={`method-badge method-${interaction.method.toLowerCase()}`}>
            {interaction.method}
          </span>
          <span className={`status-badge ${summary.isError ? 'status-err' : 'status-ok'}`}>
            {interaction.response_status}
          </span>
        </div>
        <div className="detail-url" title={interaction.url}>{interaction.url}</div>
        <div className="detail-timestamp">
          <Clock size={13} />
          {formatLocaleDateTime(interaction.timestamp)}
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
            <span
              className="meta-badge"
              title={`prompt ${usage.prompt_tokens ?? '?'} · completion ${usage.completion_tokens ?? '?'}`}
            >
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

export default function InteractionDetailPanel({
  interaction,
  expanded,
  onToggle,
  onClearSelection
}) {
  return (
    <aside className={`detail-panel ${expanded ? 'detail-panel-open' : 'detail-panel-collapsed'}`}>
      <button
        type="button"
        className="detail-panel-toggle"
        onClick={onToggle}
        title={expanded ? 'Collapse details' : 'Expand details'}
        aria-expanded={expanded}
      >
        {expanded ? <ChevronRight size={16} /> : <ExpandIcon size={16} />}
      </button>

      {expanded && (
        <>
          <div className="detail-panel-header">
            <span className="detail-panel-title">Request details</span>
            {interaction && (
              <button
                type="button"
                className="detail-panel-close"
                onClick={onClearSelection}
                title="Clear selection"
              >
                <X size={16} />
              </button>
            )}
          </div>

          <div className="detail-panel-body">
            {interaction ? (
              <DetailContent interaction={interaction} />
            ) : (
              <div className="detail-empty">
                Select a row in the grid to inspect request and response payloads.
              </div>
            )}
          </div>
        </>
      )}
    </aside>
  );
}
