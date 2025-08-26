#!/usr/bin/env bash
set -euo pipefail

# Paths
BEAR_DB="$HOME/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite"
BRAIN_DB="./brain.db"

# Make a tiny state table to track last-synced CoreData timestamp (seconds since 2001-01-01)
sqlite3 "$BRAIN_DB" "
  create table if not exists sync_state(
    key text primary key,
    value real
  );
  insert or ignore into sync_state(key, value) values('last_cfabsolute', 0);
"

LAST=$(sqlite3 "$BRAIN_DB" "select value from sync_state where key='last_cfabsolute'")

# Select only changed notes. Adjust filters after inspecting .schema ZSFNOTE
SQL="select
        ZUNIQUEIDENTIFIER as id,
        ZTITLE            as title,
        ZTEXT             as content
     from ZSFNOTE
     where ZTEXT is not null
       and ZMODIFICATIONDATE > $LAST"

# Embed changed notes into collection `bear_chunks` inside brain.db, storing text for later display
llm embed-multi bear_chunks \
  -d "$BRAIN_DB" \
  --attach src "$BEAR_DB" \
  --sql "select id, title, content from ( $SQL )" \
  --store

# Advance the watermark to the max seen modification time
MAXMOD=$(sqlite3 "$BEAR_DB" "select coalesce(max(ZMODIFICATIONDATE), $LAST) from ZSFNOTE where ZMODIFICATIONDATE > $LAST")
sqlite3 "$BRAIN_DB" "update sync_state set value=$MAXMOD where key='last_cfabsolute'"

# Optional: refresh a keyword FTS index for hybrid search
sqlite3 "$BRAIN_DB" "
  create virtual table if not exists fts_bear using fts5(id, title, content);
  insert into fts_bear(fts_bear) values('rebuild');
" >/dev/null 2>&1 || true
