const Database = require('better-sqlite3');
const path = require('path');

const dbPath = path.resolve(__dirname, 'agent-story.db');
const db = new Database(dbPath);

db.pragma('journal_mode = WAL');

function ensureColumn(table, column, definition) {
  const columns = db.prepare(`PRAGMA table_info(${table})`).all();
  if (!columns.some(c => c.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}

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

ensureColumn('interactions', 'project_key', 'TEXT');
ensureColumn('interactions', 'instance_key', 'TEXT');
ensureColumn('interactions', 'metadata', 'TEXT');

const insertInteraction = db.prepare(`
  INSERT INTO interactions (
    method, url, request_headers, request_body,
    response_status, response_headers, response_body,
    project_key, instance_key, metadata
  ) VALUES (
    @method, @url, @request_headers, @request_body,
    @response_status, @response_headers, @response_body,
    @project_key, @instance_key, @metadata
  )
`);

function buildInteractionFilters({ thread, project, instance, q, method }) {
  const clauses = [];
  const params = [];

  if (thread) {
    clauses.push(`SUBSTR(url, 1, INSTR(url || '?', '?') - 1) = ?`);
    params.push(thread);
  }
  if (project) {
    if (project === '__unassigned__') {
      clauses.push('(project_key IS NULL OR project_key = \'\')');
    } else {
      clauses.push('project_key = ?');
      params.push(project);
    }
  }
  if (instance) {
    clauses.push('instance_key = ?');
    params.push(instance);
  }
  if (method && method !== 'ALL') {
    clauses.push('method = ?');
    params.push(method);
  }

  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';
  return { where, params, q: q && q.trim() ? q.trim() : '' };
}

function queryInteractions(filters, limit = 100) {
  const { where, params, q } = buildInteractionFilters(filters);

  if (q) {
    const methodLike = filters.method && filters.method !== 'ALL' ? filters.method : '%';
    const ftsWhere = where
      ? `${where} AND interactions_fts MATCH ? AND i.method LIKE ?`
      : 'WHERE interactions_fts MATCH ? AND i.method LIKE ?';
    return db.prepare(`
      SELECT i.* FROM interactions i
      JOIN interactions_fts fts ON fts.rowid = i.id
      ${ftsWhere}
      ORDER BY i.id DESC
      LIMIT ?
    `).all(...params, q + '*', methodLike, limit);
  }

  return db.prepare(`
    SELECT * FROM interactions
    ${where}
    ORDER BY id DESC
    LIMIT ?
  `).all(...params, limit);
}

const getInteractions = {
  all: (filters = {}) => queryInteractions(filters, 100)
};

const searchInteractions = {
  all: (q, methodFilter, limit, extraFilters = {}) =>
    queryInteractions({ ...extraFilters, q, method: methodFilter === '%' ? 'ALL' : methodFilter }, limit)
};

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

const getProjects = db.prepare(`
  SELECT
    COALESCE(NULLIF(project_key, ''), '__unassigned__') AS project_key,
    COUNT(*) AS count,
    MAX(timestamp) AS last_timestamp,
    MAX(method) AS last_method
  FROM interactions
  GROUP BY COALESCE(NULLIF(project_key, ''), '__unassigned__')
  ORDER BY last_timestamp DESC
`);

const getInstances = db.prepare(`
  SELECT
    instance_key,
    project_key,
    COUNT(*) AS count,
    MAX(timestamp) AS last_timestamp,
    MAX(method) AS last_method
  FROM interactions
  WHERE instance_key IS NOT NULL AND instance_key != ''
    AND (? IS NULL OR project_key = ?)
  GROUP BY instance_key, project_key
  ORDER BY last_timestamp DESC
`);

const getLatestInteractionId = db.prepare(`
  SELECT MAX(id) AS max_id FROM interactions
`);

module.exports = {
  db,
  insertInteraction,
  getInteractions,
  searchInteractions,
  getThreads,
  getInteractionsByThread,
  getProjects,
  getInstances,
  getLatestInteractionId,
  queryInteractions
};
