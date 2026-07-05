import { useState, useEffect, useCallback } from 'react';
import { Activity, Wifi, WifiOff } from 'lucide-react';
import Sidebar from './components/Sidebar';
import SearchBar from './components/SearchBar';
import InteractionCard from './components/InteractionCard';
import { API, useAgentStoryEvents } from './hooks/useAgentStoryEvents';

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

  const { connected: liveConnected, activeStreams } = useAgentStoryEvents({
    onInteraction: () => {
      fetchInteractions();
      setSidebarRefreshToken(token => token + 1);
    }
  });

  const handleSelectProject = useCallback((projectKey) => {
    setActiveProject(projectKey);
    setActiveInstance(null);
    setActiveThread(null);
    setSearchTerm('');
  }, []);

  const handleSelectSession = useCallback((projectKey, instanceKey) => {
    setActiveProject(projectKey);
    setActiveInstance(instanceKey);
    setActiveThread(null);
    setSearchTerm('');
  }, []);

  const handleSearch = useCallback((term) => {
    setSearchTerm(term);
    if (term) {
      setActiveThread(null);
    }
  }, []);

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
          refreshToken={sidebarRefreshToken}
        />

        <main className="main-panel">
          <SearchBar
            onSearch={handleSearch}
            onMethodChange={setMethodFilter}
            method={methodFilter}
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

          <div className="interactions-list">
            {loading ? (
              <div className="loading">Listening for Cursor traffic...</div>
            ) : error ? (
              <div className="error-state">Search error: {error}</div>
            ) : interactions.length === 0 ? (
              <div className="empty-state">
                {searchTerm
                  ? `No results for "${searchTerm}"`
                  : 'No interactions recorded yet. Configure Cursor to use the MITM proxy on port 8080.'}
              </div>
            ) : (
              interactions.map(interaction => (
                <InteractionCard key={interaction.id} interaction={interaction} />
              ))
            )}
          </div>
        </main>
      </div>
    </div>
  );
}
