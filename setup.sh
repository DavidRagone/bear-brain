#!/usr/bin/env bash
set -euo pipefail

echo "|--------  Installing dependencies  --------|"
pip install -r requirements.txt || true
llm install llm-sentence-transformers || true
echo "|--------  Dependencies installed  --------|"

BEAR_SRC="$HOME/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite"
BEAR_COPY="./bear.db"
BRAIN_DB="./brain.db"

echo "|--------  Snapshotting Bear DB (safe)  --------|"
# Use SQLite backup API so we get a consistent snapshot even if Bear is open
sqlite3 "$BEAR_SRC" ".backup '$BEAR_COPY'"

echo "|--------  Initializing brain.db --------|"
sqlite3 "$BRAIN_DB" "
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY,   -- Bear ZUNIQUEIDENTIFIER
  title TEXT,
  content TEXT,
  updated_at REAL
);
CREATE INDEX IF NOT EXISTS notes_updated_idx ON notes(updated_at);
"

echo "|--------  Upserting notes from Bear --------|"
sqlite3 "$BRAIN_DB" "
ATTACH DATABASE '$BEAR_COPY' AS bear;
INSERT INTO notes(id, title, content, updated_at)
SELECT
  ZUNIQUEIDENTIFIER,
  ZTITLE,
  ZTEXT,
  ZMODIFICATIONDATE
FROM bear.ZSFNOTE
WHERE ZTEXT IS NOT NULL
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  content = excluded.content,
  updated_at = excluded.updated_at
WHERE excluded.updated_at > notes.updated_at;
DETACH bear;
"

echo "|--------  Choosing embedding model (optional) --------|"
# Set default embedding model if present; no-op if not installed yet
if llm embed-models | grep -q 'all-MiniLM-L6-v2'; then
  llm embed-models default sentence-transformers/all-MiniLM-L6-v2 || true
fi

echo "|--------  Embedding notes (delta-friendly) --------|"
# Embed from our normalized notes table; llm skips unchanged rows via content-hash
llm embed-multi bear_notes \
  -d "$BRAIN_DB" \
  --sql 'select id, title, content from notes' \
  --store

echo "|--------  Done --------|"
