import { useState, useEffect, useCallback } from 'react';
import { Activity } from 'lucide-react';
import ThreadSidebar from './components/ThreadSidebar';
import SearchBar from './components/SearchBar';
import InteractionCard from './components/InteractionCard';

const API = 'http://localhost:3001';

export default function App() {
  const [interactions, setInteractions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeThread, setActiveThread] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [methodFilter, setMethodFilter] = useState('ALL');

  const fetchInteractions = useCallback(async () => {
    const params = new URLSearchParams();
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
  }, [activeThread, searchTerm, methodFilter]);

  useEffect(() => {
    setLoading(true);
    fetchInteractions();
    const interval = setInterval(fetchInteractions, 5000);
    return () => clearInterval(interval);
  }, [fetchInteractions]);

  const handleSelectThread = useCallback((thread_key) => {
    setActiveThread(thread_key);
    setSearchTerm('');
  }, []);

  const handleSearch = useCallback((term) => {
    setSearchTerm(term);
    if (term) setActiveThread(null); // searching resets thread filter
  }, []);

  return (
    <div className="app-shell">
      <header className="app-header">
        <Activity size={28} color="var(--primary-accent)" />
        <div>
          <h1>Agent Story</h1>
          <p className="subtitle">Intercepting and Visualizing Cursor AI Traffic</p>
        </div>
      </header>

      <div className="app-body">
        <ThreadSidebar activeThread={activeThread} onSelectThread={handleSelectThread} />

        <main className="main-panel">
          <SearchBar
            onSearch={handleSearch}
            onMethodChange={setMethodFilter}
            method={methodFilter}
          />

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
