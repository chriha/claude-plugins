#!/usr/bin/env bash
# Case scaffold: a fetched-and-generated tour in the run dir, as /tour:review leaves it after steps 1-4 with every optional
# layer skipped, except that the generated tour.json dropped atom a5 (so the validate/fix loop has work to do).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fix="$here/../../fixtures"
d="$(pwd)/data"
mkdir -p "$d"
cp "$fix/atoms.json" "$d/atoms.json"
jq '.mr as $m | {platform: $m.platform, project: $m.project, iid: $m.iid, title: $m.title, url: $m.url,
   base_sha: $m.base_sha, head_sha: $m.head_sha, dir: "'"$d"'", atoms_file: "'"$d"'/atoms.json", cached: false}' \
   "$fix/tour.base.json" > "$d/meta.json"
jq '(.chapters[].blocks) |= map(.atoms |= map(select(. != "a5"))) | (.chapters[].blocks) |= map(select(.atoms | length > 0))' \
   "$fix/tour.base.json" > "$d/tour.json"
if jq -e '[.chapters[].blocks[].atoms[]] | index("a5")' "$d/tour.json" >/dev/null; then echo "scaffold: a5 still assigned" >&2; exit 1; fi
