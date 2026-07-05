import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import {
  formatGridTime,
  formatMs,
  getInteractionSummary
} from '../utils/interactionUtils';

const ROW_HEIGHT = 36;
const OVERSCAN = 8;
const COLUMN_STORAGE_KEY = 'agent-story-grid-columns';

const GRID_COLUMNS = [
  { id: 'expand', label: '', defaultWidth: 32, minWidth: 32 },
  { id: 'time', label: 'Time', defaultWidth: 88, minWidth: 60 },
  { id: 'method', label: 'Method', defaultWidth: 72, minWidth: 52 },
  { id: 'url', label: 'URL', defaultWidth: 280, minWidth: 100 },
  { id: 'status', label: 'Status', defaultWidth: 64, minWidth: 48 },
  { id: 'ttft', label: 'TTFT', defaultWidth: 72, minWidth: 52 },
  { id: 'duration', label: 'Duration', defaultWidth: 72, minWidth: 52 },
  { id: 'project', label: 'Project', defaultWidth: 112, minWidth: 72 },
  { id: 'tokens', label: 'Tokens', defaultWidth: 72, minWidth: 52 }
];

function loadColumnWidths() {
  try {
    const saved = localStorage.getItem(COLUMN_STORAGE_KEY);
    if (!saved) return GRID_COLUMNS.map(col => col.defaultWidth);
    const parsed = JSON.parse(saved);
    if (!Array.isArray(parsed) || parsed.length !== GRID_COLUMNS.length) {
      return GRID_COLUMNS.map(col => col.defaultWidth);
    }
    return parsed.map((width, index) => {
      const min = GRID_COLUMNS[index].minWidth;
      return Math.max(min, Number(width) || GRID_COLUMNS[index].defaultWidth);
    });
  } catch {
    return GRID_COLUMNS.map(col => col.defaultWidth);
  }
}

function GridRow({ interaction, selected, detailsExpanded, onSelect, onToggleDetails }) {
  const summary = getInteractionSummary(interaction);
  const isOpen = selected && detailsExpanded;

  return (
    <tr
      className={`grid-row ${selected ? 'grid-row-selected' : ''}`}
      onClick={() => onSelect(interaction.id)}
      onDoubleClick={() => onToggleDetails(interaction.id)}
      role="row"
      aria-selected={selected}
    >
      <td className="grid-cell grid-cell-expand">
        <button
          type="button"
          className={`grid-expand-btn ${isOpen ? 'expanded' : ''}`}
          aria-label={isOpen ? 'Collapse details' : 'Expand details'}
          title={isOpen ? 'Collapse details' : 'Expand details'}
          onClick={(event) => {
            event.stopPropagation();
            onToggleDetails(interaction.id);
          }}
        >
          {isOpen ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        </button>
      </td>
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
  detailExpanded,
  onSelect,
  onToggleDetails,
  loading,
  error,
  searchTerm,
  resetScrollKey
}) {
  const scrollRef = useRef(null);
  const [scrollTop, setScrollTop] = useState(0);
  const [viewportHeight, setViewportHeight] = useState(480);
  const [columnWidths, setColumnWidths] = useState(loadColumnWidths);
  const resizeRef = useRef(null);

  useEffect(() => {
    setScrollTop(0);
    if (scrollRef.current) {
      scrollRef.current.scrollTop = 0;
    }
  }, [resetScrollKey]);

  useEffect(() => {
    try {
      localStorage.setItem(COLUMN_STORAGE_KEY, JSON.stringify(columnWidths));
    } catch {
      // ignore storage failures
    }
  }, [columnWidths]);

  useEffect(() => () => {
    if (resizeRef.current) {
      document.removeEventListener('mousemove', resizeRef.current.onMove);
      document.removeEventListener('mouseup', resizeRef.current.onUp);
      resizeRef.current = null;
    }
  }, []);

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

  const startColumnResize = useCallback((columnIndex, event) => {
    event.preventDefault();
    event.stopPropagation();

    const startX = event.clientX;
    const startWidth = columnWidths[columnIndex];
    const minWidth = GRID_COLUMNS[columnIndex].minWidth;

    const onMove = (moveEvent) => {
      const nextWidth = Math.max(minWidth, startWidth + (moveEvent.clientX - startX));
      setColumnWidths(prev => {
        if (prev[columnIndex] === nextWidth) return prev;
        const next = [...prev];
        next[columnIndex] = nextWidth;
        return next;
      });
    };

    const onUp = () => {
      document.removeEventListener('mousemove', onMove);
      document.removeEventListener('mouseup', onUp);
      document.body.classList.remove('grid-col-resizing');
      resizeRef.current = null;
    };

    document.body.classList.add('grid-col-resizing');
    document.addEventListener('mousemove', onMove);
    document.addEventListener('mouseup', onUp);
    resizeRef.current = { onMove, onUp };
  }, [columnWidths]);

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

  const tableMinWidth = useMemo(
    () => columnWidths.reduce((sum, width) => sum + width, 0),
    [columnWidths]
  );

  if (loading && interactions.length === 0) {
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
        <table className="interaction-grid" style={{ minWidth: tableMinWidth }}>
          <colgroup>
            {columnWidths.map((width, index) => (
              <col key={GRID_COLUMNS[index].id} style={{ width: `${width}px` }} />
            ))}
          </colgroup>
          <thead className="grid-head">
            <tr>
              {GRID_COLUMNS.map((column, index) => (
                <th
                  key={column.id}
                  style={{ width: columnWidths[index] }}
                  aria-label={column.id === 'expand' ? 'Expand details' : undefined}
                >
                  <span className="grid-head-label">{column.label}</span>
                  {index > 0 && index < GRID_COLUMNS.length - 1 && (
                    <span
                      className="grid-col-resizer"
                      role="separator"
                      aria-orientation="vertical"
                      aria-label={`Resize ${column.label} column`}
                      onMouseDown={(event) => startColumnResize(index, event)}
                    />
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {virtualRange.paddingTop > 0 && (
              <tr aria-hidden="true" className="grid-spacer">
                <td colSpan={GRID_COLUMNS.length} style={{ height: virtualRange.paddingTop, padding: 0, border: 'none' }} />
              </tr>
            )}
            {visibleRows.map(interaction => (
              <GridRow
                key={interaction.id}
                interaction={interaction}
                selected={interaction.id === selectedId}
                detailsExpanded={detailExpanded}
                onSelect={onSelect}
                onToggleDetails={onToggleDetails}
              />
            ))}
            {virtualRange.paddingBottom > 0 && (
              <tr aria-hidden="true" className="grid-spacer">
                <td colSpan={GRID_COLUMNS.length} style={{ height: virtualRange.paddingBottom, padding: 0, border: 'none' }} />
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
