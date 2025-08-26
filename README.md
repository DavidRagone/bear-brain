# Bear Brain

A second brain for Bear notes with LLM integration intended to make the notes
more easily accessible and interactive.

Relies on Simon Willison's [llm](https://github.com/simonw/llm/) tool for LLM
interactions (both chunking and retrieval).

**NOTE**: This project is a work in progress and may not be fully functional or stable. It
has only been tested on macOS.

## Setup

1. Install dependencies

```
pip install llm sqlite-utils

# Optional: local embedding models (no cloud)
llm install llm-sentence-transformers # local MiniLM etc. [oai_citation:2‡llm.datasette.io](https://llm.datasette.io/en/stable/embeddings/cli.html)

# Or use OpenAI embeddings (set your key once)
llm keys set openai
```

2. Copy Bear’s DB (read-only)

```sh
cp ~/Library/Group\ Containers/9K33E3U3T4.net.shinyfrog.bear/Application\ Data/database.sqlite ./bear.db
# Do not write to Bear’s DB; work off the copy.  [oai_citation:5‡Bear Markdown Notes](https://bear.app/faq/where-are-bears-notes-located/?utm_source=chatgpt.com)
```


## Syncing options

We don't want direct access to Bear's SQLite DB, so instead rely on keeping a
copy of the DB in sync with Bear's DB. To keep that copy in sync, we have a few
choices:

1. **Periodic incremental sync**: Run the `bear-sync.sh` script every N minutes
   (e.g. via launchd agent with StartInterval key).
2. **Sync on file changes**: Use a file watcher (e.g. `fswatch`) to monitor
   Bear's data directory for changes and trigger the sync script when changes
   are detected.
3. **Manual sync**: Run the `bear-sync.sh` script manually whenever you want to
   sync, e.g. via an alias in your shell profile such as:
    ```sh
    brain_ask() {
      ~/bin/bear-sync.sh
      llm similar bear_chunks -d ~/brain.db -c "$*" | head -n 8
      # ...or pipe top K into your answer synthesizer
    }
    ```
