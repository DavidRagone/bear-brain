#!/usr/bin/env bash
set -euo pipefail

BRAIN_DB="${BRAIN_DB:-./brain.db}"
COLLECTION="bear_chunks"
TOPK="${TOPK:-8}"
RUN_SYNC="${BRAIN_SYNC:-1}"   # set 0 to skip pre-query sync
MODEL=""

usage() { echo "usage: $(basename "$0") [-m model] <query...>" >&2; exit 2; }

while getopts ":m:" opt; do
  case "$opt" in
    m) MODEL="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND-1))

[[ $# -ge 1 ]] || usage
q="$*"

# Optional incremental sync before asking
if [[ "$RUN_SYNC" != "0" && -x ./bear-sync.sh ]]; then
  ./bear-sync.sh || echo "warn: bear-sync failed; continuing with last index" >&2
fi

embed_all_chunks() {
  # Create/refresh the collection from ALL chunks (idempotent; llm dedupes by hash)
  local count
  count="$(sqlite3 "$BRAIN_DB" "SELECT COUNT(1) FROM chunks")"
  if [[ "${count:-0}" -gt 0 ]]; then
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
}

# Try retrieval; if it fails (likely collection missing), build the collection and retry once.
SIMILAR_JSON=""
if ! SIMILAR_JSON="$(llm similar "$COLLECTION" -d "$BRAIN_DB" -c "$q" -n "$TOPK" 2>/dev/null)"; then
  embed_all_chunks
  SIMILAR_JSON="$(llm similar "$COLLECTION" -d "$BRAIN_DB" -c "$q" -n "$TOPK")" || {
    echo "error: retrieval failed even after embedding collection '$COLLECTION' in $BRAIN_DB" >&2
    exit 1
  }
fi

# Build retrieval context (requires --store at embed time)
ctx="$(printf '%s\n' "$SIMILAR_JSON" \
  | jq -r '"[" + .id + "] score=" + (.score|tostring) + "\n" + (.content // "") + "\n---\n"' \
)"
if [[ -z "${ctx// }" ]]; then
  echo "No matching context found." >&2
  exit 3
fi

# Respect default llm model unless -m provided
LLM_ARGS=( --no-stream -s "Use only the context blocks below. Cite the [ID] after any claim. If unsure, say so." )
[[ -n "$MODEL" ]] && LLM_ARGS=( -m "$MODEL" "${LLM_ARGS[@]}" )

llm "${LLM_ARGS[@]}" \
"Context:
$ctx

Question: $q
Answer:"
