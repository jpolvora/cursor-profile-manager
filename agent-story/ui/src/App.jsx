import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Activity, Wifi, WifiOff } from 'lucide-react';
import Sidebar from './components/Sidebar';
import SearchBar from './components/SearchBar';
import InteractionGrid from './components/InteractionGrid';
import InteractionDetailPanel from './components/InteractionDetailPanel';
import { API, useAgentStoryEvents } from './hooks/useAgentStoryEvents';
import { useProjects } from './hooks/useProjects';

function useDebouncedCallback(callback, delay) {
  const timerRef = useRef(null);
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => () => {
    if (timerRef.current) clearTimeout(timerRef.current);
  }, []);

  return useCallback((...args) => {
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => callbackRef.current(...args), delay);
  }, [delay]);
}

export default function App() {
  const [interactions, setInteractions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeProject, setActiveProject] = useState(null);
  const [activeInstance, setActiveInstance] = useState(null);
  const [activeThread, setActiveThread] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [methodFilter, setMethodFilter] = useState('ALL');
  const [sidebarRefreshToken, setSidebarRefreshToken] = useState(0);
  const [selectedId, setSelectedId] = useState(null);
  const [detailExpanded, setDetailExpanded] = useState(true);

  const projects = useProjects(sidebarRefreshToken);

  const fetchInteractions = useCallback(async () => {
    const params = new URLSearchParams();
    if (activeProject) params.set('project', activeProject);
    if (activeInstance) params.set('instance', activeInstance);
    if (activeThread) params.set('thread', activeThread);
    if (searchTerm.trim()) params.set('q', searchTerm.trim());
    if (methodFilter !== 'ALL') params.set('method', methodFilter);

    try {
      const res = await fetch(`${API}/api/interactions?${params}`);
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        setError(body.error || `HTTP ${res.status}`);
        return;
      }
      const data = await res.json();
      setInteractions(data);
      setError(null);
      setSelectedId(prev => {
        if (prev == null) return null;
        return data.some(row => row.id === prev) ? prev : null;
      });
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [activeProject, activeInstance, activeThread, searchTerm, methodFilter]);

  useEffect(() => {
    setLoading(true);
    fetchInteractions();
  }, [fetchInteractions]);

  const debouncedRefresh = useDebouncedCallback(() => {
    fetchInteractions();
    setSidebarRefreshToken(token => token + 1);
  }, 250);

  const { connected: liveConnected, activeStreams } = useAgentStoryEvents({
    onInteraction: debouncedRefresh
  });

  const handleSelectProject = useCallback((projectKey) => {
    setActiveProject(projectKey);
    setActiveInstance(null);
    setActiveThread(null);
    setSearchTerm('');
    setSelectedId(null);
  }, []);

  const handleSelectSession = useCallback((projectKey, instanceKey) => {
    setActiveProject(projectKey);
    setActiveInstance(instanceKey);
    setActiveThread(null);
    setSearchTerm('');
    setSelectedId(null);
  }, []);

  const handleSearch = useCallback((term) => {
    setSearchTerm(term);
    if (term) {
      setActiveThread(null);
      setSelectedId(null);
    }
  }, []);

  const handleSelectInteraction = useCallback((id) => {
    setSelectedId(id);
    setDetailExpanded(true);
  }, []);

  const handleProjectFilterChange = useCallback((projectKey) => {
    setActiveProject(projectKey);
    setActiveInstance(null);
    setActiveThread(null);
    setSelectedId(null);
  }, []);

  const handleClearFilters = useCallback(() => {
    setActiveProject(null);
    setActiveInstance(null);
    setActiveThread(null);
    setSearchTerm('');
    setMethodFilter('ALL');
    setSelectedId(null);
  }, []);

  const filtersActive = activeProject != null
    || activeInstance != null
    || activeThread != null
    || methodFilter !== 'ALL'
    || searchTerm.trim().length > 0;

  const selectedInteraction = useMemo(
    () => interactions.find(row => row.id === selectedId) ?? null,
    [interactions, selectedId]
  );

  const filterSummary = [
    activeProject ? `project: ${activeProject.split('/').pop()}` : null,
    activeInstance ? `window: ${activeInstance.slice(0, 8)}…` : null,
    activeThread ? `thread: ${activeThread.split('/').pop()}` : null
  ].filter(Boolean).join(' · ');

  return (
    <div className="app-shell">
      <header className="app-header">
        <Activity size={28} color="var(--primary-accent)" />
        <div className="header-copy">
          <h1>Agent Story</h1>
          <p className="subtitle">Intercepting and Visualizing Cursor AI Traffic</p>
        </div>
        <div className={`live-indicator ${liveConnected ? 'live-on' : 'live-off'}`} title={liveConnected ? 'Live updates connected' : 'Reconnecting live updates…'}>
          {liveConnected ? <Wifi size={16} /> : <WifiOff size={16} />}
          <span>{liveConnected ? 'Live' : 'Offline'}</span>
        </div>
      </header>

      <div className="app-body">
        <Sidebar
          activeProject={activeProject}
          activeInstance={activeInstance}
          onSelectProject={handleSelectProject}
          onSelectSession={handleSelectSession}
          projects={projects}
        />

        <div className="workspace">
          <main className="main-panel">
            <SearchBar
              onSearch={handleSearch}
              onMethodChange={setMethodFilter}
              method={methodFilter}
              projects={projects}
              projectFilter={activeProject}
              onProjectChange={handleProjectFilterChange}
              onClearFilters={handleClearFilters}
              filtersActive={filtersActive}
              externalSearchTerm={searchTerm}
            />

            {filterSummary && (
              <div className="filter-summary">Filtering by {filterSummary}</div>
            )}

            {activeStreams.length > 0 && (
              <div className="stream-banner">
                {activeStreams.map(stream => (
                  <div key={stream.capture_key} className="stream-banner-item">
                    <span className="stream-pulse" />
                    Streaming {stream.method} {stream.url.split('/').pop()} · {stream.bytes} bytes · TTFT {stream.time_to_first_token_ms}ms
                  </div>
                ))}
              </div>
            )}

            <InteractionGrid
              interactions={interactions}
              selectedId={selectedId}
              onSelect={handleSelectInteraction}
              loading={loading}
              error={error}
              searchTerm={searchTerm}
            />
          </main>

          <InteractionDetailPanel
            interaction={selectedInteraction}
            expanded={detailExpanded}
            onToggle={() => setDetailExpanded(value => !value)}
            onClearSelection={() => setSelectedId(null)}
          />
        </div>
      </div>
    </div>
  );
}
