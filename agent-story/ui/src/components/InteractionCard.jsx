import { useState } from 'react';
import { Server, Clock, ChevronDown, ChevronRight } from 'lucide-react';
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

function BodySection({ title, raw }) {
  const [open, setOpen] = useState(false);
  const parsed = tryParseJSON(raw);

  // Try to extract markdown content field from Cursor messages or choices
  let markdownContent = null;
  if (parsed) {
    if (Array.isArray(parsed.messages)) {
      const textParts = parsed.messages
        .flatMap(m => {
          if (typeof m.content === 'string') return [m.content];
          if (Array.isArray(m.content)) return m.content.filter(p => p.type === 'text').map(p => p.text);
          return [];
        })
        .join('\n\n---\n\n');
      if (textParts.trim()) markdownContent = textParts;
    } else if (Array.isArray(parsed.choices)) {
      const textParts = parsed.choices
        .flatMap(c => {
          if (c.message && typeof c.message.content === 'string') return [c.message.content];
          if (c.text && typeof c.text === 'string') return [c.text];
          return [];
        })
        .join('\n\n---\n\n');
      if (textParts.trim()) markdownContent = textParts;
    }
  }

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
              <div className="section-label">Message Content</div>
              <MarkdownRenderer content={markdownContent} />
            </div>
          )}
          <div className="section-label">Raw {parsed ? 'JSON' : 'Text'}</div>
          {parsed ? (
            <SyntaxHighlighter
              language="json"
              style={atomOneDark}
              customStyle={{ borderRadius: '8px', fontSize: '0.82rem', margin: 0 }}
            >
              {JSON.stringify(parsed, null, 2)}
            </SyntaxHighlighter>
          ) : (
            <pre className="raw-text">{raw || '(empty)'}</pre>
          )}
        </div>
      )}
    </div>
  );
}

export default function InteractionCard({ interaction }) {
  const isError = interaction.response_status >= 400;
  const baseUrl = interaction.url.split('?')[0];

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
      <BodySection title="Request Payload" raw={interaction.request_body} />
      <BodySection title="Response Payload" raw={interaction.response_body} />
    </div>
  );
}
