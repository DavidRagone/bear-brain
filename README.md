# Bear Brain

A second brain for Bear notes, powered by [Simon Willison’s `llm`](https://github.com/simonw/llm).  
It syncs your Bear notes into a local SQLite DB, chunks them intelligently by headings, embeds them, and lets you query them with any LLM supported by `llm`.

---

## Setup

1. **Install dependencies**

```sh
pip install -r requirements.txt
llm install llm-sentence-transformers
```

2. **Initialize database + first sync**

```sh
./setup.sh
```

This creates brain.db, copies/normalizes Bear’s DB, and runs the first sync.

⸻

## Syncing Notes

To keep up to date:

```sh
./bear-sync.sh
```

  •  Reads Bear’s DB (safe, read-only snapshot)
  •  Diffs against the last sync timestamp
  •  Splits changed notes into heading-aware overlapping chunks
  •  Embeds new/updated chunks into the bear_chunks collection in brain.db

Run manually, via a cron/launchd job, or trigger before queries.

⸻

## Asking Questions

```sh
./brain_ask.sh "what was that idea about curriculum scheduling?"
```

Options:
  •  -m <model> → pick a specific model (e.g. one hosted in LM Studio or OpenAI)
  •  Uses --no-stream by default for reliability
  •  Pulls top-K similar chunks, adds them as context, and asks the LLM to answer with [ID] citations

⸻

## How It Works
  •  Chunking: Notes are split on Markdown headers (#, ##, etc.) with overlapping windows (~1200 chars, 200 overlap). Each chunk has a stable chunk_id.
  •  Embeddings: Stored with content (--store) so retrieval returns text directly.
  •  Incremental sync: Only re-embeds notes that changed since the last run.
  •  Collection: All embeddings live in the bear_chunks collection.

⸻

## Status

Work in progress, tested only on macOS. Use at your own risk.


