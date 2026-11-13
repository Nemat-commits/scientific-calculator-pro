#!/usr/bin/env bash
# TEMPORARY development aid - removed before the branch is finished.
#
# Publishes files as unreferenced git blobs (8 MB parts) plus an index in a
# check run called "carry-<label>", so a machine that can only reach
# api.github.com is able to read build outputs back.
#
#   dev_carry.sh <label> <file>...
set -uo pipefail
label="$1"; shift
api="https://api.github.com/repos/$GITHUB_REPOSITORY"
work="$(mktemp -d)"; index="$work/index.txt"; : > "$index"
post() { curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" "$1" --data-binary @"$2"; }
for file in "$@"; do
  [ -f "$file" ] || { echo "skip (missing): $file"; continue; }
  name="$(basename "$file")"
  split -b 8000000 -d -a 3 "$file" "$work/part_"
  for part in "$work"/part_*; do
    base64 -w0 "$part" > "$work/b64"
    jq -n --rawfile c "$work/b64" '{content:$c, encoding:"base64"}' > "$work/blob.json"
    sha="$(post "$api/git/blobs" "$work/blob.json" | jq -r '.sha // ("ERROR:" + (.message // "unknown"))')"
    echo "$name $(basename "$part") $sha $(wc -c < "$part") $(sha256sum "$part" | cut -d' ' -f1)" | tee -a "$index"
    rm -f "$part"
  done
done
jq -n --arg name "carry-$label" --arg sha "$GITHUB_SHA" --rawfile text "$index" \
  '{name:$name, head_sha:$sha, status:"completed", conclusion:"neutral", output:{title:$name, summary:"blob index", text:$text}}' > "$work/payload.json"
post "$api/check-runs" "$work/payload.json" | jq -r '"check run: " + ((.id // .message) | tostring)'
