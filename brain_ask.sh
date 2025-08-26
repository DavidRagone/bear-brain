#!/usr/bin/env bash
q="$*"
ctx="$(llm similar bear_notes -d brain.db -c "$q" | head -n 8 \
    | jq -r '[id="[" + .id + "]", content=(.content // "")] | "\(.[0])\n\(.[1])\n---"' )"
llm -s "Use only the context blocks. Cite the [id] after any claim. If unsure, say so." \
    "Context:\n$ctx\n\nQuestion: $q\nAnswer:"
