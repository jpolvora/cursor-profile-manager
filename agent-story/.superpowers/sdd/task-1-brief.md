## Task 1: Server â€” FTS5 Table, Triggers & New Queries

**Files:**
- Modify: `server/db.js`

**Interfaces:**
- Produces:
  - `searchInteractions(query, method, limit)` â€” prepared statement (called with `.all({ query, method, limit })`)
  - `getThreads` â€” prepared statement (called with `.all()`)
  - `getInteractionsByThread(thread_key, limit)` â€” prepared statement (called with `.all({ thread_key, limit })`)

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

- [ ] **Step 4: Manual smoke test â€” start server and verify no crash**

```bash
cd server
node index.js
```

Expected: `Agent Story API listening on http://localhost:3001` and `MITM Proxy listening on port 8080.` â€” no error about FTS5 or triggers.

- [ ] **Step 5: Commit**

```bash
git add server/db.js
git commit -m "feat(server): add FTS5 full-text search table, triggers, and new query statements"
```

---
