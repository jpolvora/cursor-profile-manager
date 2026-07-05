# Agent Story — Search, Thread Grouping & Rich Visualization

**Date:** 2026-06-26  
**Status:** Approved

## Overview

Agent Story already captures and stores Cursor AI traffic. This spec covers the three remaining core features from SPEC.md:

1. **Server-side full-text search** — SQLite FTS5 search across request/response bodies and URLs
2. **Conversation thread grouping** — group interactions by base URL to surface logical conversations
3. **Rich visualization** — syntax highlighting (JSON/code), markdown rendering for message content, collapsible interaction cards, and a sidebar + search UI

---

## Architecture

### Server (server/)

#### FTS5 Full-Text Search

Add a SQLite FTS5 virtual table that mirrors `interactions`:

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS interactions_fts 
USING fts5(url, request_body, response_body, content='interactions', content_rowid='id');
```

Populate via triggers on INSERT. Expose a new endpoint:

- `GET /api/interactions/search?q=<term>&method=<method>&limit=<n>`  
  Returns matching interactions using FTS5 MATCH. Falls back to LIKE if q is empty. method is an optional filter (ALL/GET/POST/etc). limit defaults to 100.

#### Thread Grouping

Grouping is by **base URL** — strip query params and path after the second segment to get a canonical "thread key". Expose:

- `GET /api/threads`  
  Returns [{ thread_key, count, last_timestamp, last_method }] ordered by last_timestamp DESC.

- `GET /api/interactions?thread=<thread_key>&q=<search_term>&method=<method>`  
  Combines thread filter with optional search. thread_key is matched with `url LIKE thread_key || '%'`.

#### Modified files

- `server/db.js` — add FTS5 table, triggers, new prepared statements: searchInteractions, getThreads, getInteractionsByThread
- `server/index.js` — add /api/interactions/search, /api/threads, update /api/interactions to accept thread + q + method params

---

### UI (ui/src/)

#### Layout

Three-panel layout:

```
+-------------+------------------------------------------+
|  Thread      |  [Search bar]  [Method filter]           |
|  Sidebar     +------------------------------------------+
|              |  InteractionCard (collapsed by default)  |
|  (scrollable)|  > Request Payload                       |
|              |  > Response Payload                      |
+-------------+------------------------------------------+
```

#### Components

- **ThreadSidebar.jsx** — fetches /api/threads, lists them as clickable items with count badge. Highlights active thread. "All" item at top.
- **SearchBar.jsx** — controlled input with debounce (300ms). Emits onSearch(term). Alongside a select for method filter.
- **InteractionCard.jsx** — shows URL, method, status badge, timestamp in header. Body sections (Request / Response) are collapsible (closed by default). Uses SyntaxHighlighter for JSON, MarkdownRenderer for markdown content fields.
- **MarkdownRenderer.jsx** — wraps react-markdown with remark-gfm. Used for rendering Cursor message content fields that contain markdown.
- **App.jsx** — orchestrates state: activeThread, searchTerm, methodFilter. Fetches from /api/interactions with combined params. Polls every 5s. Renders ThreadSidebar, SearchBar, and list of InteractionCard.

#### Dependencies to add (UI)

- `react-syntax-highlighter` — syntax highlighting for JSON/code blocks
- `remark-gfm` — GitHub Flavored Markdown support (already has react-markdown)

---

## Data Flow

```
User types in SearchBar
  -> debounce 300ms
  -> App fetches /api/interactions?q=<term>&thread=<key>&method=<filter>
  -> Server runs FTS5 MATCH (or LIKE fallback)
  -> Returns filtered rows
  -> InteractionCards rendered

User clicks Thread in sidebar
  -> App sets activeThread
  -> App fetches /api/interactions?thread=<key>
  -> Shows only interactions for that base URL
```

---

## Error Handling

- FTS5 query errors (e.g., invalid syntax) -> server catches and returns 400 with message; UI shows inline error
- Empty search -> falls back to full list (no FTS, just ORDER BY id DESC)
- Thread with no results -> empty state message in main panel

---

## Testing

### Manual verification
1. Start server, open UI
2. Confirm thread sidebar populates after capturing some Cursor traffic
3. Type a search term -> results filter live
4. Click a thread -> interactions filter to that URL group
5. Confirm JSON payloads are syntax-highlighted
6. Confirm markdown content in message bodies renders correctly

### No automated tests for MVP
The existing codebase has no test infrastructure. Adding tests is out of scope for this spec.

---

## Out of Scope

- Export to Markdown/JSON (future roadmap item)
- SSL CA generation (future roadmap item)
- Session-ID-based thread grouping (requires deeper Cursor schema reverse-engineering)
