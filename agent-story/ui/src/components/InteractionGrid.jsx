import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  formatGridTime,
  formatMs,
  getInteractionSummary
} from '../utils/interactionUtils';

const ROW_HEIGHT = 36;
const OVERSCAN = 8;

function GridRow({ interaction, selected, onSelect }) {
  const summary = getInteractionSummary(interaction);

  return (
    <tr
      className={`grid-row ${selected ? 'grid-row-selected' : ''}`}
      onClick={() => onSelect(interaction.id)}
      role="row"
      aria-selected={selected}
    >
      <td className="grid-cell grid-cell-time">{formatGridTime(interaction.timestamp)}</td>
      <td className="grid-cell grid-cell-method">
        <span className={`method-badge method-${interaction.method.toLowerCase()}`}>
          {interaction.method}
        </span>
      </td>
      <td className="grid-cell grid-cell-url" title={interaction.url}>
        {summary.baseUrl}
      </td>
      <td className="grid-cell grid-cell-status">
        <span className={`status-badge ${summary.isError ? 'status-err' : 'status-ok'}`}>
          {interaction.response_status}
        </span>
      </td>
      <td className="grid-cell grid-cell-num">{formatMs(summary.ttft)}</td>
      <td className="grid-cell grid-cell-num">{formatMs(summary.duration)}</td>
      <td className="grid-cell grid-cell-project" title={interaction.project_key || ''}>
        {summary.projectLabel || '—'}
      </td>
      <td className="grid-cell grid-cell-num">
        {summary.tokens != null ? summary.tokens : '—'}
      </td>
    </tr>
  );
}

export default function InteractionGrid({
  interactions,
  selectedId,
  onSelect,
  loading,
  error,
  searchTerm
}) {
  const scrollRef = useRef(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(480);

  const onScroll = useCallback(() => {
    if (scrollRef.current) {
      setScrollTop(scrollRef.current.scrollTop);
    }
  }, []);

  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return undefined;

    const observer = new ResizeObserver(entries => {
      const entry = entries[0];
      if (entry) setViewportHeight(entry.contentRect.height);
    });
    observer.observe(el);
    setViewportHeight(el.clientHeight);
    return () => observer.disconnect();
  }, [loading, interactions.length]);

  const virtualRange = useMemo(() => {
    const count = interactions.length;
    if (count === 0) {
      return { start: 0, end: 0, paddingTop: 0, paddingBottom: 0 };
    }

    const start = Math.max(0, Math.floor(scrollTop / ROW_HEIGHT) - OVERSCAN);
    const visibleCount = Math.ceil(viewportHeight / ROW_HEIGHT) + OVERSCAN * 2;
    const end = Math.min(count, start + visibleCount);
    const paddingTop = start * ROW_HEIGHT;
    const paddingBottom = Math.max(0, (count - end) * ROW_HEIGHT);

    return { start, end, paddingTop, paddingBottom };
  }, [interactions.length, scrollTop, viewportHeight]);

  const visibleRows = useMemo(
    () => interactions.slice(virtualRange.start, virtualRange.end),
    [interactions, virtualRange.start, virtualRange.end]
  );

  if (loading) {
    return <div className="grid-panel loading">Listening for Cursor traffic...</div>;
  }

  if (error) {
    return <div className="grid-panel error-state">Search error: {error}</div>;
  }

  if (interactions.length === 0) {
    return (
      <div className="grid-panel empty-state">
        {searchTerm
          ? `No results for "${searchTerm}"`
          : 'No interactions recorded yet. Configure Cursor to use the MITM proxy on port 8080.'}
      </div>
    );
  }

  return (
    <div className="grid-panel">
      <div className="grid-toolbar">
        <span className="grid-count">{interactions.length} requests</span>
      </div>
      <div className="grid-scroll" ref={scrollRef} onScroll={onScroll}>
        <table className="interaction-grid">
          <thead className="grid-head">
            <tr>
              <th>Time</th>
              <th>Method</th>
              <th>URL</th>
              <th>Status</th>
              <th>TTFT</th>
              <th>Duration</th>
              <th>Project</th>
              <th>Tokens</th>
            </tr>
          </thead>
          <tbody>
            {virtualRange.paddingTop > 0 && (
              <tr aria-hidden="true" className="grid-spacer">
                <td colSpan={8} style={{ height: virtualRange.paddingTop, padding: 0, border: 'none' }} />
              </tr>
            )}
            {visibleRows.map(interaction => (
              <GridRow
                key={interaction.id}
                interaction={interaction}
                selected={interaction.id === selectedId}
                onSelect={onSelect}
              />
            ))}
            {virtualRange.paddingBottom > 0 && (
              <tr aria-hidden="true" className="grid-spacer">
                <td colSpan={8} style={{ height: virtualRange.paddingBottom, padding: 0, border: 'none' }} />
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
