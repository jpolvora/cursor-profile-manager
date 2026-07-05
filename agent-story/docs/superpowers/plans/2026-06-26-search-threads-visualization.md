# Search, Thread Grouping & Rich Visualization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add FTS5 server-side search, URL-based thread grouping, and rich visualization (syntax highlighting + markdown rendering + collapsible cards) to the Agent Story dashboard.

**Architecture:** Extend `server/db.js` with an FTS5 virtual table and triggers; add new Express endpoints to `server/index.js`; refactor `ui/src/App.jsx` into four focused components (`ThreadSidebar`, `SearchBar`, `InteractionCard`, `MarkdownRenderer`) with a three-panel layout and syntax highlighting via `react-syntax-highlighter`.

**Tech Stack:** Node.js + Express + better-sqlite3 (FTS5) on the server; React 19 + Vite + react-markdown + react-syntax-highlighter + remark-gfm on the client.

## Global Constraints

- Node.js v18+; existing `better-sqlite3` ^12.11.1 — no version changes
- No new server dependencies (FTS5 is built into SQLite)
- UI new dependencies: `react-syntax-highlighter` and `remark-gfm` only
- All CSS uses existing CSS variable names from `index.css` (`--bg-dark`, `--bg-card`, `--primary-accent`, `--text-main`, `--text-muted`, `--border-color`)
- All API base URL is `http://localhost:3001` (same as existing code)
- Polling interval changes from 3s → 5s
- `thread_key` = URL with query string stripped: `url.split('?')[0]`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `server/db.js` | Modify | Add FTS5 table, triggers, `searchInteractions` statement, `getThreads` statement |
| `server/index.js` | Modify | Add `/api/threads` endpoint, `/api/interactions/search` endpoint, update `/api/interactions` to accept `thread` + `q` + `method` params |
| `ui/src/components/ThreadSidebar.jsx` | Create | Fetches `/api/threads`, renders clickable thread list with count badges |
| `ui/src/components/SearchBar.jsx` | Create | Controlled search input with debounce + method filter `<select>` |
| `ui/src/components/MarkdownRenderer.jsx` | Create | Wraps `react-markdown` + `remark-gfm` for message content rendering |
| `ui/src/components/InteractionCard.jsx` | Create | Single interaction card with collapsible request/response sections, syntax highlighting |
| `ui/src/App.jsx` | Modify | Orchestrates state, fetches data, renders three-panel layout |
| `ui/src/index.css` | Modify | Add three-panel layout styles, sidebar styles, search bar styles, collapsible section styles |

---

## Task 1: Server — FTS5 Table, Triggers & New Queries

**Files:**
- Modify: `server/db.js`

**Interfaces:**
- Produces:
  - `searchInteractions(query, method, limit)` — prepared statement (called with `.all({ query, method, limit })`)
  - `getThreads` — prepared statement (called with `.all()`)
  - `getInteractionsByThread(thread_key, limit)` — prepared statement (called with `.all({ thread_key, limit })`)

Note: The existing module still exports `db`, `insertInteraction`, `getInteractions`.

- [ ] **Step 1: Add FTS5 virtual table and triggers to `server/db.js`**

Replace the `db.exec(...)` block (lines 10-22 in original) with the following expanded version that adds FTS5 and triggers. Keep the `interactions` table creation identical:

```javascript
db.exec(`
  CREATE TABLE IF NOT EXISTS interactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    method TEXT,
    url TEXT,
    request_headers TEXT,
    request_body TEXT,
    response_status INTEGER,
    response_headers TEXT,
    response_body TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
  );

  CREATE VIRTUAL TABLE IF NOT EXISTS interactions_fts
  USING fts5(url, request_body, response_body, content='interactions', content_rowid='id');

  CREATE TRIGGER IF NOT EXISTS interactions_ai AFTER INSERT ON interactions BEGIN
    INSERT INTO interactions_fts(rowid, url, request_body, response_body)
    VALUES (new.id, new.url, new.request_body, new.response_body);
  END;

  CREATE TRIGGER IF NOT EXISTS interactions_ad AFTER DELETE ON interactions BEGIN
    INSERT INTO interactions_fts(interactions_fts, rowid, url, request_body, response_body)
    VALUES ('delete', old.id, old.url, old.request_body, old.response_body);
  END;
`);
```

- [ ] **Step 2: Add the three new prepared statements to `server/db.js`**

After the existing `getInteractions` statement, add:

```javascript
// FTS5 full-text search. When q is empty, returns all (ordered by id DESC).
// method param: pass '%' to match all methods.
const searchInteractions = db.prepare(`
  SELECT i.* FROM interactions i
  JOIN interactions_fts fts ON fts.rowid = i.id
  WHERE interactions_fts MATCH ?
    AND i.method LIKE ?
  ORDER BY i.id DESC
  LIMIT ?
`);

const getThreads = db.prepare(`
  SELECT
    SUBSTR(url, 1, INSTR(url || '?', '?') - 1) AS thread_key,
    COUNT(*) AS count,
    MAX(timestamp) AS last_timestamp,
    MAX(method) AS last_method
  FROM interactions
  GROUP BY thread_key
  ORDER BY last_timestamp DESC
`);

const getInteractionsByThread = db.prepare(`
  SELECT * FROM interactions
  WHERE SUBSTR(url, 1, INSTR(url || '?', '?') - 1) = ?
  ORDER BY id DESC
  LIMIT ?
`);
```

- [ ] **Step 3: Export the new statements from `server/db.js`**

Update the `module.exports` at the bottom:

```javascript
module.exports = {
  db,
  insertInteraction,
  getInteractions,
  searchInteractions,
  getThreads,
  getInteractionsByThread
};
```

- [ ] **Step 4: Manual smoke test — start server and verify no crash**

```bash
cd server
node index.js
```

Expected: `Agent Story API listening on http://localhost:3001` and `MITM Proxy listening on port 8080.` — no error about FTS5 or triggers.

- [ ] **Step 5: Commit**

```bash
git add server/db.js
git commit -m "feat(server): add FTS5 full-text search table, triggers, and new query statements"
```

---

## Task 2: Server — New API Endpoints

**Files:**
- Modify: `server/index.js`

**Interfaces:**
- Consumes: `searchInteractions`, `getThreads`, `getInteractionsByThread` from `server/db.js` (Task 1)
- Produces:
  - `GET /api/threads` → `[{ thread_key, count, last_timestamp, last_method }]`
  - `GET /api/interactions/search?q=<term>&method=<method>&limit=<n>` → `[interaction, ...]`
  - `GET /api/interactions?thread=<key>&q=<term>&method=<method>` (updated)

- [ ] **Step 1: Update the import in `server/index.js`**

Change the top-level require from:

```javascript
const { insertInteraction, getInteractions } = require('./db');
```

to:

```javascript
const { insertInteraction, getInteractions, searchInteractions, getThreads, getInteractionsByThread } = require('./db');
```

- [ ] **Step 2: Add `/api/threads` endpoint in `server/index.js`**

Insert this after the existing `/api/interactions` handler:

```javascript
app.get('/api/threads', (req, res) => {
  try {
    const rows = getThreads.all();
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});
```

- [ ] **Step 3: Add `/api/interactions/search` endpoint in `server/index.js`**

Insert after the `/api/threads` handler:

```javascript
app.get('/api/interactions/search', (req, res) => {
  const { q = '', method = '', limit = 100 } = req.query;
  const methodFilter = method && method !== 'ALL' ? method : '%';
  const parsedLimit = Math.min(parseInt(limit, 10) || 100, 500);
  try {
    let rows;
    if (q.trim()) {
      rows = searchInteractions.all(q.trim() + '*', methodFilter, parsedLimit);
    } else {
      rows = getInteractions.all();
    }
    res.json(rows);
  } catch (err) {
    // FTS5 syntax errors return 400
    res.status(400).json({ error: err.message });
  }
});
```

- [ ] **Step 4: Update `/api/interactions` to support `thread` + `q` + `method` filter params**

Replace the existing `/api/interactions` handler:

```javascript
app.get('/api/interactions', (req, res) => {
  const { thread, q, method } = req.query;
  try {
    let rows;
    if (thread) {
      rows = getInteractionsByThread.all(thread, 100);
    } else if (q && q.trim()) {
      const methodFilter = method && method !== 'ALL' ? method : '%';
      rows = searchInteractions.all(q.trim() + '*', methodFilter, 100);
    } else {
      rows = getInteractions.all();
    }
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});
```

- [ ] **Step 5: Manual smoke test — verify all three endpoints**

Start the server (`node index.js`), then in a separate terminal:

```bash
# All interactions (existing behavior)
curl http://localhost:3001/api/interactions
# Expected: JSON array (may be empty if no data yet)

# Threads
curl http://localhost:3001/api/threads
# Expected: JSON array (may be empty)

# Search
curl "http://localhost:3001/api/interactions/search?q=test"
# Expected: JSON array (may be empty), no 500 error
```

- [ ] **Step 6: Commit**

```bash
git add server/index.js
git commit -m "feat(server): add /api/threads and /api/interactions/search endpoints"
```

---

## Task 3: UI — Install New Dependencies & Create `MarkdownRenderer`

**Files:**
- Modify: `ui/package.json` (via npm install)
- Create: `ui/src/components/MarkdownRenderer.jsx`

**Interfaces:**
- Produces: `<MarkdownRenderer content={string} />` — renders markdown string with GFM support

- [ ] **Step 1: Install new UI dependencies**

```bash
cd ui
npm install react-syntax-highlighter remark-gfm
```

Expected: `added N packages` — no errors.

- [ ] **Step 2: Create `ui/src/components/` directory and `MarkdownRenderer.jsx`**

Create `ui/src/components/MarkdownRenderer.jsx`:

```jsx
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

export default function MarkdownRenderer({ content }) {
  if (!content) return null;
  return (
    <div className="markdown-rendered">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>
        {content}
      </ReactMarkdown>
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add ui/package.json ui/package-lock.json ui/src/components/MarkdownRenderer.jsx
git commit -m "feat(ui): add remark-gfm + react-syntax-highlighter, create MarkdownRenderer component"
```

---

## Task 4: UI — `InteractionCard` Component

**Files:**
- Create: `ui/src/components/InteractionCard.jsx`

**Interfaces:**
- Consumes: `<MarkdownRenderer>` from Task 3
- Props: `interaction` — object with fields: `id`, `method`, `url`, `request_body`, `response_body`, `response_status`, `timestamp`
- Produces: `<InteractionCard interaction={interactionObject} />`

- [ ] **Step 1: Create `ui/src/components/InteractionCard.jsx`**

```jsx
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

  // Try to extract markdown content field from Cursor messages
  let markdownContent = null;
  if (parsed && Array.isArray(parsed.messages)) {
    const textParts = parsed.messages
      .flatMap(m => {
        if (typeof m.content === 'string') return [m.content];
        if (Array.isArray(m.content)) return m.content.filter(p => p.type === 'text').map(p => p.text);
        return [];
      })
      .join('\n\n---\n\n');
    if (textParts.trim()) markdownContent = textParts;
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
```

- [ ] **Step 2: Commit**

```bash
git add ui/src/components/InteractionCard.jsx
git commit -m "feat(ui): create InteractionCard component with collapsible sections and syntax highlighting"
```

---

## Task 5: UI — `SearchBar` Component

**Files:**
- Create: `ui/src/components/SearchBar.jsx`

**Interfaces:**
- Props: `onSearch(term: string)`, `onMethodChange(method: string)`, `method: string`
- Produces: `<SearchBar onSearch={fn} onMethodChange={fn} method={string} />`

- [ ] **Step 1: Create `ui/src/components/SearchBar.jsx`**

```jsx
import { useState, useEffect } from 'react';
import { Search } from 'lucide-react';

const METHODS = ['ALL', 'GET', 'POST', 'PUT', 'DELETE', 'PATCH'];

export default function SearchBar({ onSearch, onMethodChange, method }) {
  const [term, setTerm] = useState('');

  useEffect(() => {
    const timer = setTimeout(() => {
      onSearch(term);
    }, 300);
    return () => clearTimeout(timer);
  }, [term, onSearch]);

  return (
    <div className="search-bar">
      <div className="search-input-wrapper">
        <Search size={16} className="search-icon" />
        <input
          id="search-input"
          type="text"
          className="search-input"
          placeholder="Search requests and responses..."
          value={term}
          onChange={e => setTerm(e.target.value)}
        />
      </div>
      <select
        id="method-filter"
        className="method-select"
        value={method}
        onChange={e => onMethodChange(e.target.value)}
      >
        {METHODS.map(m => (
          <option key={m} value={m}>{m}</option>
        ))}
      </select>
    </div>
  );
}
```

- [ ] **Step 2: Commit**

```bash
git add ui/src/components/SearchBar.jsx
git commit -m "feat(ui): create SearchBar component with debounced search and method filter"
```

---

## Task 6: UI — `ThreadSidebar` Component

**Files:**
- Create: `ui/src/components/ThreadSidebar.jsx`

**Interfaces:**
- Props: `activeThread: string | null`, `onSelectThread(thread_key: string | null): void`
- Fetches: `GET http://localhost:3001/api/threads` → `[{ thread_key, count, last_timestamp }]`
- Produces: `<ThreadSidebar activeThread={str} onSelectThread={fn} />`

- [ ] **Step 1: Create `ui/src/components/ThreadSidebar.jsx`**

```jsx
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
```

- [ ] **Step 2: Commit**

```bash
git add ui/src/components/ThreadSidebar.jsx
git commit -m "feat(ui): create ThreadSidebar component with live-polling thread list"
```

---

## Task 7: UI — Wire Up `App.jsx` with Three-Panel Layout

**Files:**
- Modify: `ui/src/App.jsx`

**Interfaces:**
- Consumes: `ThreadSidebar`, `SearchBar`, `InteractionCard` from Tasks 4–6
- Fetches: `GET http://localhost:3001/api/interactions?thread=<key>&q=<term>&method=<filter>`

- [ ] **Step 1: Rewrite `ui/src/App.jsx`**

Replace the entire file with:

```jsx
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
```

- [ ] **Step 2: Commit**

```bash
git add ui/src/App.jsx
git commit -m "feat(ui): wire up App.jsx with thread sidebar, search bar, and three-panel layout"
```

---

## Task 8: UI — Styles for Three-Panel Layout & New Components

**Files:**
- Modify: `ui/src/index.css`

**Interfaces:**
- CSS classes produced (consumed by Tasks 4–7):
  - `app-shell`, `app-header`, `app-body`, `main-panel` — layout
  - `thread-sidebar`, `sidebar-header`, `thread-list`, `thread-item`, `thread-name`, `thread-count` — sidebar
  - `search-bar`, `search-input-wrapper`, `search-icon`, `search-input`, `method-select` — search
  - `body-section`, `section-toggle`, `section-content`, `section-label`, `raw-text` — card sections
  - `card-header-left`, `card-header-right`, `method-badge`, `timestamp` — card header
  - `markdown-rendered` — markdown rendering wrapper
  - `error-state`, `empty-state` — status states

- [ ] **Step 1: Replace `ui/src/index.css` with the new full stylesheet**

Replace the entire contents of `ui/src/index.css` with:

```css
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');

:root {
  --bg-dark: #0a0a0f;
  --bg-card: #161622;
  --bg-sidebar: #111119;
  --primary-accent: #6b4cff;
  --text-main: #f3f3f8;
  --text-muted: #8e8e9f;
  --border-color: #27273a;
  --font-family: 'Inter', system-ui, sans-serif;
  --sidebar-width: 260px;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  background-color: var(--bg-dark);
  color: var(--text-main);
  font-family: var(--font-family);
  -webkit-font-smoothing: antialiased;
  height: 100vh;
  overflow: hidden;
}

/* ─── App shell ─── */
.app-shell {
  display: flex;
  flex-direction: column;
  height: 100vh;
}

.app-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1rem 1.5rem;
  border-bottom: 1px solid var(--border-color);
  flex-shrink: 0;
  animation: fadeIn 0.5s ease-out;
}

h1 {
  font-size: 1.5rem;
  font-weight: 700;
  background: linear-gradient(135deg, #e0d4ff 0%, #6b4cff 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
}

.subtitle {
  color: var(--text-muted);
  font-size: 0.8rem;
  margin-top: 0.15rem;
}

.app-body {
  display: flex;
  flex: 1;
  overflow: hidden;
}

/* ─── Thread sidebar ─── */
.thread-sidebar {
  width: var(--sidebar-width);
  flex-shrink: 0;
  background: var(--bg-sidebar);
  border-right: 1px solid var(--border-color);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.sidebar-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.9rem 1rem;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-muted);
  border-bottom: 1px solid var(--border-color);
}

.thread-list {
  list-style: none;
  overflow-y: auto;
  flex: 1;
  padding: 0.4rem 0;
}

.thread-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  padding: 0.55rem 1rem;
  background: transparent;
  border: none;
  color: var(--text-muted);
  font-size: 0.82rem;
  font-family: var(--font-family);
  cursor: pointer;
  text-align: left;
  transition: background 0.15s, color 0.15s;
  gap: 0.5rem;
}

.thread-item:hover { background: rgba(107, 76, 255, 0.08); color: var(--text-main); }
.thread-item.active { background: rgba(107, 76, 255, 0.15); color: var(--primary-accent); font-weight: 600; }

.thread-name {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-family: ui-monospace, Menlo, monospace;
  font-size: 0.78rem;
}

.thread-count {
  flex-shrink: 0;
  background: rgba(107, 76, 255, 0.2);
  color: var(--primary-accent);
  border-radius: 999px;
  padding: 0.1rem 0.5rem;
  font-size: 0.72rem;
  font-weight: 700;
}

/* ─── Main panel ─── */
.main-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

/* ─── Search bar ─── */
.search-bar {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1.25rem;
  border-bottom: 1px solid var(--border-color);
  flex-shrink: 0;
}

.search-input-wrapper {
  flex: 1;
  position: relative;
  display: flex;
  align-items: center;
}

.search-icon {
  position: absolute;
  left: 0.75rem;
  color: var(--text-muted);
  pointer-events: none;
}

.search-input {
  width: 100%;
  padding: 0.55rem 0.75rem 0.55rem 2.25rem;
  background: var(--bg-card);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  color: var(--text-main);
  font-family: var(--font-family);
  font-size: 0.875rem;
  outline: none;
  transition: border-color 0.2s;
}
.search-input:focus { border-color: var(--primary-accent); }
.search-input::placeholder { color: var(--text-muted); }

.method-select {
  padding: 0.55rem 0.75rem;
  background: var(--bg-card);
  border: 1px solid var(--border-color);
  border-radius: 8px;
  color: var(--text-main);
  font-family: var(--font-family);
  font-size: 0.875rem;
  cursor: pointer;
  outline: none;
}

/* ─── Interactions list ─── */
.interactions-list {
  flex: 1;
  overflow-y: auto;
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

/* ─── Interaction card ─── */
.interaction-card {
  background: var(--bg-card);
  border: 1px solid var(--border-color);
  border-radius: 12px;
  padding: 1rem 1.25rem;
  transition: border-color 0.2s, box-shadow 0.2s;
  animation: slideUp 0.3s ease-out forwards;
}
.interaction-card:hover {
  border-color: rgba(107, 76, 255, 0.35);
  box-shadow: 0 8px 24px rgba(107, 76, 255, 0.1);
}

.card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 1rem;
  margin-bottom: 0.5rem;
}

.card-header-left {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  min-width: 0;
}

.card-header-right {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  flex-shrink: 0;
}

.method-badge {
  font-size: 0.7rem;
  font-weight: 700;
  padding: 0.2rem 0.5rem;
  border-radius: 4px;
  text-transform: uppercase;
  background: rgba(107, 76, 255, 0.15);
  color: var(--primary-accent);
  flex-shrink: 0;
}

.url {
  font-size: 0.85rem;
  color: var(--text-muted);
  font-family: ui-monospace, Menlo, monospace;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.timestamp {
  font-size: 0.75rem;
  color: var(--text-muted);
  display: flex;
  align-items: center;
  gap: 0.25rem;
}

.status-badge {
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
  font-size: 0.78rem;
  font-weight: 700;
}
.status-ok  { background: rgba(34, 197, 94, 0.1);  color: #4ade80; }
.status-err { background: rgba(239, 68, 68, 0.1);  color: #f87171; }

/* ─── Body sections (collapsible) ─── */
.body-section { margin-top: 0.5rem; }

.section-toggle {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  background: transparent;
  border: none;
  color: var(--text-muted);
  font-family: var(--font-family);
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  cursor: pointer;
  padding: 0.4rem 0;
  transition: color 0.15s;
}
.section-toggle:hover { color: var(--text-main); }

.section-content {
  margin-top: 0.5rem;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}

.section-label {
  font-size: 0.7rem;
  text-transform: uppercase;
  color: var(--text-muted);
  letter-spacing: 0.06em;
  margin-bottom: 0.3rem;
}

.raw-text {
  background: rgba(0, 0, 0, 0.4);
  padding: 0.75rem 1rem;
  border-radius: 8px;
  border: 1px solid rgba(255,255,255,0.05);
  font-family: ui-monospace, Menlo, monospace;
  font-size: 0.8rem;
  line-height: 1.6;
  overflow-x: auto;
  color: #d1d1e0;
  white-space: pre-wrap;
  word-break: break-all;
}

/* ─── Markdown rendering ─── */
.markdown-rendered {
  background: rgba(0,0,0,0.25);
  padding: 1rem;
  border-radius: 8px;
  border: 1px solid rgba(255,255,255,0.05);
  font-size: 0.875rem;
  line-height: 1.7;
  color: #d1d1e0;
}
.markdown-rendered h1,.markdown-rendered h2,.markdown-rendered h3 { color: var(--text-main); margin: 0.75rem 0 0.4rem; }
.markdown-rendered code { font-family: ui-monospace, Menlo, monospace; font-size: 0.82rem; background: rgba(255,255,255,0.08); padding: 0.1rem 0.3rem; border-radius: 3px; }
.markdown-rendered pre { background: #000; padding: 0.75rem; border-radius: 6px; overflow-x: auto; }
.markdown-rendered pre code { background: none; padding: 0; }
.markdown-rendered p { margin-bottom: 0.5rem; }
.markdown-rendered ul,.markdown-rendered ol { padding-left: 1.4rem; margin-bottom: 0.5rem; }

/* ─── States ─── */
.loading, .empty-state, .error-state {
  text-align: center;
  padding: 4rem 2rem;
  font-size: 0.95rem;
}
.loading    { color: var(--primary-accent); animation: pulse 2s infinite ease-in-out; }
.empty-state { color: var(--text-muted); }
.error-state { color: #f87171; }

/* ─── Animations ─── */
@keyframes fadeIn  { from { opacity: 0; } to { opacity: 1; } }
@keyframes slideUp { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: translateY(0); } }
@keyframes pulse   { 0%, 100% { opacity: 1; } 50% { opacity: 0.4; } }
```

- [ ] **Step 2: Commit**

```bash
git add ui/src/index.css
git commit -m "feat(ui): add three-panel layout, sidebar, search bar, and card component styles"
```

---

## Task 9: Manual End-to-End Verification

This task has no code — it verifies the full feature set works together.

- [ ] **Step 1: Start the server**

```bash
cd server
node index.js
```

Expected output:
```
Agent Story API listening on http://localhost:3001
MITM Proxy listening on port 8080.
```

- [ ] **Step 2: Start the UI dev server**

In a new terminal:

```bash
cd ui
npm run dev
```

Expected: `Local: http://localhost:5173/`

- [ ] **Step 3: Open browser at `http://localhost:5173`**

Expected: Three-panel layout visible — sidebar on left, search bar at top of main panel, empty state in content area.

- [ ] **Step 4: Insert a test row directly into the database to verify the UI**

In a third terminal:

```bash
cd server
node -e "
const { insertInteraction } = require('./db');
insertInteraction.run({ method:'POST', url:'https://api2.cursor.sh/v1/chat/completions?session=abc', request_headers:'{}', request_body:JSON.stringify({messages:[{role:'user',content:'Hello world, explain **recursion** please'}]}), response_status:200, response_headers:'{}', response_body:JSON.stringify({choices:[{message:{content:'Recursion is a function that calls itself.'}}]}) });
insertInteraction.run({ method:'POST', url:'https://api2.cursor.sh/v1/chat/completions?session=xyz', request_headers:'{}', request_body:JSON.stringify({messages:[{role:'user',content:'What is TypeScript?'}]}), response_status:200, response_headers:'{}', response_body:JSON.stringify({choices:[{message:{content:'TypeScript is a typed superset of JavaScript.'}}]}) });
console.log('inserted');
"
```

Expected: `inserted`

- [ ] **Step 5: Verify thread sidebar**

Within 5 seconds the sidebar should show:
- "All interactions" with count 2
- `https://api2.cursor.sh/v1/chat/completions` with count 2

- [ ] **Step 6: Click a thread — verify filtering**

Click the `cursor.sh` thread. The main panel should show 2 interaction cards, both for that URL.

- [ ] **Step 7: Verify collapsible sections**

Click "Request Payload" on a card — it should expand and show:
- A "Message Content" section with rendered markdown (bold **recursion**, etc.)
- A "Raw JSON" section with syntax-highlighted JSON

- [ ] **Step 8: Verify search**

Type `recursion` in the search bar. Expected: only the first interaction appears.  
Clear the search. Expected: both interactions appear.

- [ ] **Step 9: Commit final state**

```bash
git add -A
git commit -m "chore: verified end-to-end — search, threads, and rich visualization all working"
```

---

## Self-Review

**Spec coverage:**
- ✅ Full-text search via FTS5: Tasks 1 + 2 + 5
- ✅ Thread grouping by base URL: Tasks 1 + 2 + 6
- ✅ Syntax highlighting: Task 4 (`react-syntax-highlighter`)
- ✅ Markdown rendering: Task 3 + 4 (`MarkdownRenderer`)
- ✅ Collapsible cards: Task 4 (`BodySection`)
- ✅ Three-panel layout: Tasks 7 + 8
- ✅ Method filter: Tasks 2 + 5

**Placeholder scan:** No TBDs, TODOs, or vague steps. All code is complete.

**Type consistency:**
- `thread_key` used consistently across Tasks 1 (SQL), 2 (API), 6 (component), 7 (App state)
- `searchInteractions.all(q, method, limit)` positional params match the SQL `?` placeholders in Task 1
- `getInteractionsByThread.all(thread, 100)` matches the SQL `?` in Task 1
- `onSelectThread` / `activeThread` prop names consistent between Tasks 6 and 7
