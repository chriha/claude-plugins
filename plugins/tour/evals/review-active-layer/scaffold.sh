#!/usr/bin/env bash
# Case scaffold: a fetched tour in the run dir as /tour:review leaves it after step 3 with the cost gate answered "Active review
# only": a valid base-only draft tour.json that the skill must extend with the active layer (layers, intent, probes).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fix="$here/../../fixtures"
d="$(pwd)/data"
mkdir -p "$d"
cp "$fix/atoms.json" "$d/atoms.json"
jq '.mr as $m | {platform: $m.platform, project: $m.project, iid: $m.iid, title: $m.title, url: $m.url,
   base_sha: $m.base_sha, head_sha: $m.head_sha, dir: "'"$d"'", atoms_file: "'"$d"'/atoms.json", cached: false}' \
   "$fix/tour.base.json" > "$d/meta.json"
cp "$fix/tour.base.json" "$d/tour.json"
jq -e '.layers == ["base"]' "$d/tour.json" >/dev/null || { echo "scaffold: base fixture is not base-only" >&2; exit 1; }
