import { useState, useEffect } from 'react';
import { Layers } from 'lucide-react';

export default function ThreadSidebar({ activeThread, onSelectThread }) {
  const [threads, setThreads] = useState([]);

  useEffect(() => {
    const fetch_ = () =>
      fetch('http://localhost:3001/api/threads')
        .then(r => r.json())
        .then(setThreads)
        .catch(console.error);
    fetch_();
    const interval = setInterval(fetch_, 5000);
    return () => clearInterval(interval);
  }, []);

  function shortKey(key) {
    try {
      const u = new URL(key);
      return u.pathname || key;
    } catch {
      return key.length > 40 ? '...' + key.slice(-37) : key;
    }
  }

  return (
    <aside className="thread-sidebar">
      <div className="sidebar-header">
        <Layers size={16} color="var(--primary-accent)" />
        <span>Threads</span>
      </div>
      <ul className="thread-list">
        <li>
          <button
            className={`thread-item ${activeThread === null ? 'active' : ''}`}
            onClick={() => onSelectThread(null)}
          >
            <span className="thread-name">All interactions</span>
            <span className="thread-count">{threads.reduce((a, t) => a + t.count, 0)}</span>
          </button>
        </li>
        {threads.map(t => (
          <li key={t.thread_key}>
            <button
              className={`thread-item ${activeThread === t.thread_key ? 'active' : ''}`}
              onClick={() => onSelectThread(t.thread_key)}
              title={t.thread_key}
            >
              <span className="thread-name">{shortKey(t.thread_key)}</span>
              <span className="thread-count">{t.count}</span>
            </button>
          </li>
        ))}
      </ul>
    </aside>
  );
}
