const Database = require('better-sqlite3');
const path = require('path');

const dbPath = path.resolve(__dirname, 'agent-story.db');
const db = new Database(dbPath);

db.pragma('journal_mode = WAL');

// Initialize tables
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

const insertInteraction = db.prepare(`
  INSERT INTO interactions (
    method, url, request_headers, request_body, 
    response_status, response_headers, response_body
  ) VALUES (
    @method, @url, @request_headers, @request_body,
    @response_status, @response_headers, @response_body
  )
`);

const getInteractions = db.prepare(`
  SELECT * FROM interactions ORDER BY id DESC LIMIT 100
`);

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

module.exports = {
  db,
  insertInteraction,
  getInteractions,
  searchInteractions,
  getThreads,
  getInteractionsByThread
};
