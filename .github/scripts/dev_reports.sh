#!/usr/bin/env bash
# TEMPORARY development aid - removed before the branch is finished.
# Mirrors the tail of every "$OUT"/report-*.txt into a check run of that name.
set -uo pipefail
cd "$RUNNER_TEMP"
for f in "$OUT"/report-*.txt; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .txt)"
  tail -c 60000 "$f" > chunk.txt
  jq -n --arg name "$name" --arg sha "$GITHUB_SHA" --arg summary "run=$GITHUB_RUN_ID bytes=$(wc -c < "$f")" --rawfile text chunk.txt \
    '{name:$name, head_sha:$sha, status:"completed", conclusion:"neutral", output:{title:$name, summary:$summary, text:$text}}' > payload.json
  curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/check-runs" --data-binary @payload.json | jq -r '"\(.name // "?"): \(.id // .message)"'
done
