#!/usr/bin/env bash
set -euo pipefail

echo "|--------  Installing dependencies  --------|"
pip install -r requirements.txt || true
llm install llm-sentence-transformers || true
echo "|--------  Dependencies installed  --------|"

BRAIN_DB="${BRAIN_DB:-./brain.db}"

echo "|--------  Initializing brain.db (notes + chunks) --------|"
sqlite3 "$BRAIN_DB" <<'SQL'
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS sync_state(
  key   TEXT PRIMARY KEY,
  value REAL
);
INSERT OR IGNORE INTO sync_state(key, value) VALUES('last_cfabsolute', 0);

CREATE TABLE IF NOT EXISTS notes (
  id         TEXT PRIMARY KEY,   -- Bear ZUNIQUEIDENTIFIER
  title      TEXT,
  content    TEXT,
  updated_at REAL                -- Core Data absolute time (since 2001-01-01)
);
CREATE INDEX IF NOT EXISTS notes_updated_idx ON notes(updated_at);

CREATE TABLE IF NOT EXISTS chunks (
  chunk_id    TEXT PRIMARY KEY,  -- note_id#sha1(header_path+content)
  note_id     TEXT NOT NULL,
  title       TEXT,
  header_path TEXT,              -- e.g., 'Topic > Subtopic'
  content     TEXT NOT NULL,
  order_index INTEGER NOT NULL,  -- chunk order within note
  updated_at  REAL NOT NULL,
  FOREIGN KEY(note_id) REFERENCES notes(id)
);
CREATE INDEX IF NOT EXISTS chunks_note_idx ON chunks(note_id);
CREATE INDEX IF NOT EXISTS chunks_updated_idx ON chunks(updated_at);
SQL

echo "|--------  First sync + chunk + embed --------|"
./bear-sync.sh

echo "|--------  Done --------|"
