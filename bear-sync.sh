#!/usr/bin/env bash
set -euo pipefail

# Config
BEAR_DB="${BEAR_DB:-$HOME/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite}"
BRAIN_DB="${BRAIN_DB:-./brain.db}"
COLLECTION="bear_chunks"

# Current watermark (Core Data absolute time)
LAST=$(sqlite3 "$BRAIN_DB" "SELECT COALESCE((SELECT value FROM sync_state WHERE key='last_cfabsolute'),0)")

# ---- Markdown-aware chunking + upsert changed notes (Python helper) ----
NEWMAX="$(
python3 - "$BEAR_DB" "$BRAIN_DB" "$LAST" <<'PY'
import sys, sqlite3, re, hashlib

BEAR_DB, BRAIN_DB, LAST = sys.argv[1], sys.argv[2], float(sys.argv[3])

def windows(text, max_chars=1200, overlap=200):
    text = text.strip()
    if not text: return []
    parts = re.split(r'\n{2,}', text)  # paragraph-aware first
    chunks, buf = [], ""
    for p in parts:
        p = p.strip()
        if not p: continue
        if not buf: buf = p; continue
        if len(buf) + 2 + len(p) <= max_chars:
            buf += "\n\n" + p
        else:
            if buf: chunks.append(buf)
            tail = buf[-overlap:] if overlap and len(buf) > overlap else ""
            buf = (tail + ("\n\n" if tail else "") + p).strip()
            while len(buf) > max_chars:
                chunks.append(buf[:max_chars])
                buf = buf[max_chars - overlap:]
    if buf: chunks.append(buf)
    # final safety slice
    out = []
    for c in chunks:
        i = 0
        step = max_chars - overlap if max_chars > overlap else max_chars
        while i < len(c):
            out.append(c[i:i+max_chars].strip())
            i += step
    return [x for x in out if x]

hdr_re = re.compile(r'^(#{1,6})\s+(.*)$', re.M)

def split_by_headings(title, body):
    sections = []
    matches = list(hdr_re.finditer(body))
    stack = []
    if matches:
        preface = body[:matches[0].start()].strip()
        if preface:
            sections.append((title or "", preface))
        for i, m in enumerate(matches):
            level = len(m.group(1))
            text  = m.group(2).strip()
            if level <= len(stack):
                stack[level-1:] = [text]
            else:
                while len(stack) < level-1:
                    stack.append("")
                if len(stack) == level-1:
                    stack.append(text)
                else:
                    stack[level-1] = text
            start = m.end()
            end   = matches[i+1].start() if i+1 < len(matches) else len(body)
            section = body[start:end].strip()
            if section:
                hp = " > ".join([h for h in stack if h]) or (title or "")
                sections.append((hp, section))
    else:
        if body.strip():
            sections.append((title or "", body.strip()))
    return sections

conn_bear  = sqlite3.connect(BEAR_DB)
conn_bear.row_factory = sqlite3.Row
conn_brain = sqlite3.connect(BRAIN_DB)
conn_brain.execute("PRAGMA journal_mode=WAL;")

rows = list(conn_bear.execute("""
    SELECT ZUNIQUEIDENTIFIER AS id, ZTITLE AS title, ZTEXT AS content, ZMODIFICATIONDATE AS updated_at
    FROM ZSFNOTE
    WHERE ZTEXT IS NOT NULL AND ZMODIFICATIONDATE > ?
""", (LAST,)))

max_seen = LAST

with conn_brain:
    for r in rows:
        note_id = r["id"]
        title   = r["title"] or ""
        content = r["content"] or ""
        updated = float(r["updated_at"] or 0.0)
        if updated > max_seen: max_seen = updated

        conn_brain.execute("""
            INSERT INTO notes(id, title, content, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              title=excluded.title,
              content=excluded.content,
              updated_at=excluded.updated_at
            WHERE excluded.updated_at > notes.updated_at
        """, (note_id, title, content, updated))

        # Regenerate chunks for this note
        conn_brain.execute("DELETE FROM chunks WHERE note_id = ?", (note_id,))
        order_idx = 0
        to_add = []
        for header_path, section in split_by_headings(title, content):
            for piece in windows(section, max_chars=1200, overlap=200):
                h = hashlib.sha1((header_path + "\n" + piece).encode("utf-8")).hexdigest()[:10]
                chunk_id = f"{note_id}#{h}"
                to_add.append((chunk_id, note_id, title, header_path, piece, order_idx, updated))
                order_idx += 1
        if to_add:
            conn_brain.executemany("""
                INSERT OR REPLACE INTO chunks
                  (chunk_id, note_id, title, header_path, content, order_index, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, to_add)

# write pending watermark (only finalized after embedding)
with conn_brain:
    conn_brain.execute("""
        INSERT INTO sync_state(key, value) VALUES('pending_cfabsolute', ?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value
    """, (max_seen,))
print(int(max_seen))
PY
)"

# Determine if collection exists (be liberal about output format)
COLL_EXISTS=0
if llm collections list -d "$BRAIN_DB" 2>/dev/null | grep -Fq "$COLLECTION"; then
  COLL_EXISTS=1
fi

# Count chunks overall and since LAST
TOTAL_CHUNKS=$(sqlite3 "$BRAIN_DB" "SELECT COUNT(1) FROM chunks")
NEW_CHUNKS=$(sqlite3 "$BRAIN_DB" "SELECT COUNT(1) FROM chunks WHERE updated_at > $LAST")

# Embed strategy:
# - If collection missing: full embed to create it (even if NEW_CHUNKS=0)
# - Else: embed only deltas
if [[ "$COLL_EXISTS" -eq 0 ]]; then
  if [[ "$TOTAL_CHUNKS" -gt 0 ]]; then
    llm embed-multi "$COLLECTION" \
      -d "$BRAIN_DB" \
      --sql "SELECT
               chunk_id AS id,
               CASE WHEN header_path IS NULL OR header_path=''
                    THEN title
                    ELSE title || ' — ' || header_path
               END AS title,
               content
             FROM chunks" \
      --store
  fi
else
  if [[ "$NEW_CHUNKS" -gt 0 ]]; then
    llm embed-multi "$COLLECTION" \
      -d "$BRAIN_DB" \
      --sql "SELECT
               chunk_id AS id,
               CASE WHEN header_path IS NULL OR header_path=''
                    THEN title
                    ELSE title || ' — ' || header_path
               END AS title,
               content
             FROM chunks
             WHERE updated_at > $LAST" \
      --store
  fi
fi
