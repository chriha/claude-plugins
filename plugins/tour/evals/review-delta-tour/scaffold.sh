#!/usr/bin/env bash
# Case scaffold: an MR toured at an old head (data/old, with its tour.json) and fetched again after a push (data/new). The push
# inserted one new atom (a new file) after a1, edited the ImportService atom and left the rest alone, so ids after a1 shifted by one.
# /tour:review is past the delta question: the user chose "Delta tour".
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
fix="$here/../../fixtures"
d="$(pwd)/data"
mkdir -p "$d/old" "$d/new"
meta() { # <dir> <head sha> <extra json>
    jq --arg dir "$1" --arg head "$2" --argjson extra "$3" '.mr as $m | {platform: $m.platform, project: $m.project, iid: $m.iid,
       title: $m.title, url: $m.url, base_sha: $m.base_sha, head_sha: $head, dir: $dir, worktree: ($dir + "/worktree"),
       atoms_file: ($dir + "/atoms.json"), atom_count: 0, description: "Reject empty import payloads and report skipped rows.", ticket: null, cached: false} + $extra' \
       "$fix/tour.base.json"
}
cp "$fix/atoms.json" "$d/old/atoms.json"
meta "$d/old" "1111111111111111111111111111111111111111" '{}' > "$d/old/meta.json"
jq '.mr.head_sha = "1111111111111111111111111111111111111111"' "$fix/tour.base.json" > "$d/old/tour.json"
# new head: a1 (shifted), NEW a2 (a new file), old a2..a10 become a3..a11, old a3 (ImportService::run) edited
jq '{version: 1, atoms: (.atoms as $a
      | [$a[0] | .new.start += 2]
      + [{id: "x", file: "app/Services/AuditLog.php", status: "added", kind: "hunk", old: {start: 0, count: 0}, new: {start: 1, count: 4},
          lines: ["+<?php", "+", "+final class AuditLog { public static function record(string $e): void { logger()->info($e); } }", "+"]}]
      + [$a[1:][] | if .id == "a3" then .lines += ["+            AuditLog::record(\"import.rejected\");"] | .new.count += 1 else . end]
      | to_entries | map(.value + {id: ("a" + ((.key + 1) | tostring))}))}' "$fix/atoms.json" > "$d/new/atoms.json"
n="$(jq '.atoms | length' "$d/new/atoms.json")"
meta "$d/new" "2222222222222222222222222222222222222222" "{\"previous\": {\"head_sha\": \"1111111111111111111111111111111111111111\", \"dir\": \"$d/old\"}}" \
    | jq --argjson n "$n" '.atom_count = $n' > "$d/new/meta.json"
jq -e '(.atoms | length) == 11 and ([.atoms[].id] | unique | length) == 11' "$d/new/atoms.json" >/dev/null || { echo "scaffold: bad new atoms" >&2; exit 1; }
